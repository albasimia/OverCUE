import ApplicationServices
import AppKit
import Foundation
import IOKit.hid
import OverCUECore

private final class GenericHIDRuntimeObserverToken: @unchecked Sendable {
    let value: any NSObjectProtocol
    init(_ value: any NSObjectProtocol) { self.value = value }
}

private final class GenericHIDDeviceRuntimeState: @unchecked Sendable {
    let descriptor: HIDPhysicalDeviceDescriptor
    var logicalDeviceID: String
    var profileName: String
    var presetID: String
    var mode: RekordboxMappingMode
    var mapping: [GenericHIDInputBindingKey: ActionTarget]
    var resolver = GenericHIDActionResolver()
    var repeatSourceID: ActionSourceID?
    var repeatStartedAt: TimeInterval?
    var repeatTimer: Timer?

    init(
        descriptor: HIDPhysicalDeviceDescriptor,
        logicalDeviceID: String,
        profileName: String,
        presetID: String,
        mode: RekordboxMappingMode,
        mapping: [GenericHIDInputBindingKey: ActionTarget]
    ) {
        self.descriptor = descriptor
        self.logicalDeviceID = logicalDeviceID
        self.profileName = profileName
        self.presetID = presetID
        self.mode = mode
        self.mapping = mapping
    }

    deinit { repeatTimer?.invalidate() }
}

private final class GenericHIDKeyboardOutput {
    private var heldBySource: [ActionSourceID: RekordboxKeyboardShortcut] = [:]

    func trigger(_ shortcut: RekordboxKeyboardShortcut, count: Int = 1) {
        guard isRekordboxFrontmostForGenericHID() else { return }
        for _ in 0..<max(1, count) {
            post(shortcut, keyDown: true)
            post(shortcut, keyDown: false)
        }
    }

    func press(_ shortcut: RekordboxKeyboardShortcut, sourceID: ActionSourceID) {
        guard heldBySource[sourceID] == nil,
              isRekordboxFrontmostForGenericHID()
        else { return }
        post(shortcut, keyDown: true)
        heldBySource[sourceID] = shortcut
    }

    func release(sourceID: ActionSourceID) {
        guard let shortcut = heldBySource.removeValue(forKey: sourceID) else { return }
        post(shortcut, keyDown: false)
    }

    func releaseAll() {
        for sourceID in Array(heldBySource.keys) {
            release(sourceID: sourceID)
        }
    }

    private func post(_ shortcut: RekordboxKeyboardShortcut, keyDown: Bool) {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(shortcut.keyCode),
            keyDown: keyDown
        ) else { return }
        var flags: CGEventFlags = []
        if shortcut.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if shortcut.modifiers.contains(.shift) { flags.insert(.maskShift) }
        if shortcut.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if shortcut.modifiers.contains(.control) { flags.insert(.maskControl) }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
}

/// Runtime capture is exclusive only for Generic HID devices already bound in
/// config. Shortcuts Learn reuses this same exclusive owner instead of closing
/// the runtime and opening a second IOHIDManager, so composite devices never
/// cross an exclusive handoff boundary during mapping edits.
final class GenericHIDRuntimeCoordinator: @unchecked Sendable {
    private struct LiveGroupKey: Hashable {
        let persistentIdentifier: String
        let connectionQualifier: String
    }

    private struct LiveGroup {
        var representative: HIDPhysicalDeviceDescriptor
        var interfaceIDs: Set<UInt>
    }

    private let manager: IOHIDManager
    private let loader = RekordboxKeyMappingLoader()
    private let keyboardOutput = GenericHIDKeyboardOutput()
    private let repeatProfile = AcceleratingKeyRepeatProfile()
    private var configuration: OverCUEConfiguration = .defaultValue
    private var groups: [LiveGroupKey: LiveGroup] = [:]
    private var groupKeyByInterfaceID: [UInt: LiveGroupKey] = [:]
    private var statesBySessionID: [String: GenericHIDDeviceRuntimeState] = [:]
    private var keyMappingsByMode: [RekordboxMappingMode: RekordboxKeyMapping] = [:]
    private var configurationObserver: GenericHIDRuntimeObserverToken?
    private var genericMappingObserver: GenericHIDRuntimeObserverToken?
    private var runtimeControlObserver: GenericHIDRuntimeObserverToken?
    private var isOpen = false
    private var isCaptureMode = false
    private var captureSession = GenericHIDLearnSession()
    private var captureHandler: ((String, GenericHIDInputBindingKey) -> Void)?

    var isRunning: Bool { isOpen }

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, genericRuntimeDeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, genericRuntimeDeviceRemoved, context)
        IOHIDManagerRegisterInputValueCallback(manager, genericRuntimeInputValueReceived, context)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
    }

    deinit {
        stop()
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
    }

    func start() throws {
        guard !isOpen else { return }
        configuration = try OverCUEConfigurationFileStore.readCurrent(
            at: OverCUEAppConfigurationLocation.url
        )
        groups = [:]
        groupKeyByInterfaceID = [:]
        statesBySessionID = [:]
        keyMappingsByMode = [:]
        configureDeviceMatching()
        installObservers()

        let result = HIDManagerOpenRetry.open(
            manager,
            options: IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
        )
        guard result == kIOReturnSuccess else {
            removeObservers()
            throw GenericHIDDeviceIdentifierMonitorError.openFailed(result)
        }
        isOpen = true
    }

    func beginCapture(
        onCaptured: @escaping (String, GenericHIDInputBindingKey) -> Void
    ) {
        keyboardOutput.releaseAll()
        for state in statesBySessionID.values {
            _ = state.resolver.reset(mapping: state.mapping)
            stopRepeat(state)
        }
        captureSession.begin()
        captureHandler = onCaptured
        isCaptureMode = true
    }

    func endCapture() {
        guard isCaptureMode || captureHandler != nil else { return }
        captureHandler = nil
        isCaptureMode = false
        captureSession.cancel()
        keyboardOutput.releaseAll()
        for state in statesBySessionID.values {
            _ = state.resolver.reset(mapping: state.mapping)
            stopRepeat(state)
        }
    }

    func stop() {
        guard isOpen || configurationObserver != nil else { return }
        endCapture()
        for state in statesBySessionID.values {
            publishRuntimeStatus(state, connected: false)
            stopRepeat(state)
        }
        keyboardOutput.releaseAll()
        if isOpen {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        isOpen = false
        groups = [:]
        groupKeyByInterfaceID = [:]
        statesBySessionID = [:]
        keyMappingsByMode = [:]
        removeObservers()
    }

    fileprivate func didMatch(device: IOHIDDevice, result: IOReturn) {
        guard result == kIOReturnSuccess,
              registerInterface(device) != nil
        else { return }
        refreshRuntimeStates()
    }

    fileprivate func didRemove(device: IOHIDDevice, result: IOReturn) {
        guard result == kIOReturnSuccess else { return }
        let interfaceID = interfaceIdentifier(device)
        guard let groupKey = groupKeyByInterfaceID.removeValue(forKey: interfaceID),
              var group = groups[groupKey]
        else { return }
        group.interfaceIDs.remove(interfaceID)
        if group.interfaceIDs.isEmpty {
            let sessionID = group.representative.sessionIdentifier
            groups.removeValue(forKey: groupKey)
            if let state = statesBySessionID.removeValue(forKey: sessionID) {
                publishRuntimeStatus(state, connected: false)
                stopRepeat(state)
            }
        } else {
            groups[groupKey] = group
        }
        refreshRuntimeStates()
    }

    fileprivate func didReceiveValue(result: IOReturn, value: IOHIDValue) {
        guard result == kIOReturnSuccess else { return }
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        guard let descriptor = registerInterface(device) else { return }
        if statesBySessionID[descriptor.sessionIdentifier] == nil {
            refreshRuntimeStates()
        }
        guard let state = statesBySessionID[descriptor.sessionIdentifier] else { return }

        let reportID = UInt32(IOHIDElementGetReportID(element))
        let input = GenericHIDInputDescriptor(
            usagePage: IOHIDElementGetUsagePage(element),
            usage: IOHIDElementGetUsage(element),
            reportID: reportID == 0 ? nil : reportID,
            collectionPath: collectionPath(for: element)
        )
        let runtimeElement = GenericHIDRuntimeElementDescriptor(
            input: input,
            cookie: UInt64(IOHIDElementGetCookie(element)),
            isRelative: IOHIDElementIsRelative(element),
            matchingElementCount: matchingElementCount(for: element, input: input)
        )
        guard runtimeElement.persistentInput != nil,
              let event = GenericHIDEventNormalizer.normalize(
                  GenericHIDRawValue(
                      sessionDeviceID: descriptor.sessionIdentifier,
                      element: runtimeElement,
                      value: IOHIDValueGetIntegerValue(value)
                  )
              )
        else { return }

        if isCaptureMode {
            guard let handler = captureHandler,
                  case let .captured(candidate) = captureSession.observe(event),
                  let bindingKey = candidate.persistentBindingKey
            else { return }
            captureHandler = nil
            handler(state.logicalDeviceID, bindingKey)
            return
        }

        if case .released = event.phase { stopRepeat(state) }
        let events = state.resolver.resolve(event: event, mapping: state.mapping)
        guard !events.isEmpty else { return }
        publishRuntimeStatus(state, connected: true)
        for event in events { route(event, state: state) }
    }

    private func configureDeviceMatching() {
        let matches: [[String: Any]] = configuration.physicalDeviceBindings.compactMap { binding in
            guard binding.kind == .genericHID,
                  let serial = binding.serialNumber
            else { return nil }
            return [
                kIOHIDVendorIDKey as String: binding.vendorID,
                kIOHIDProductIDKey as String: binding.productID,
                kIOHIDSerialNumberKey as String: serial,
            ]
        }
        if matches.isEmpty {
            IOHIDManagerSetDeviceMatching(
                manager,
                [
                    kIOHIDVendorIDKey as String: Int.max,
                    kIOHIDProductIDKey as String: Int.max,
                ] as CFDictionary
            )
        } else {
            IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        }
    }

    private func installObservers() {
        configurationObserver = GenericHIDRuntimeObserverToken(
            DistributedNotificationCenter.default().addObserver(
                forName: OverCUEConfigurationChangedNotification.name,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.reloadConfigurationAndMappings() }
        )
        genericMappingObserver = GenericHIDRuntimeObserverToken(
            NotificationCenter.default.addObserver(
                forName: GenericHIDMappingChangedNotification.name,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.reloadLearnedMappings() }
        )
        runtimeControlObserver = GenericHIDRuntimeObserverToken(
            DistributedNotificationCenter.default().addObserver(
                forName: OverCUERuntimeControlNotification.name,
                object: nil,
                queue: .main
            ) { [weak self] notification in self?.applyRuntimeControl(notification) }
        )
    }

    private func removeObservers() {
        if let configurationObserver {
            DistributedNotificationCenter.default().removeObserver(configurationObserver.value)
        }
        if let genericMappingObserver {
            NotificationCenter.default.removeObserver(genericMappingObserver.value)
        }
        if let runtimeControlObserver {
            DistributedNotificationCenter.default().removeObserver(runtimeControlObserver.value)
        }
        configurationObserver = nil
        genericMappingObserver = nil
        runtimeControlObserver = nil
    }

    private func reloadConfigurationAndMappings() {
        guard let latest = try? OverCUEConfigurationFileStore.readCurrent(
            at: OverCUEAppConfigurationLocation.url
        ) else { return }
        configuration = latest
        configureDeviceMatching()
        keyMappingsByMode = [:]
        refreshRuntimeStates()
        reloadLearnedMappings()
    }

    private func reloadLearnedMappings() {
        keyboardOutput.releaseAll()
        for state in statesBySessionID.values {
            _ = state.resolver.reset(mapping: state.mapping)
            stopRepeat(state)
            state.mapping = (try? GenericHIDMappingStore.mapping(
                logicalDeviceID: state.logicalDeviceID,
                presetID: state.presetID
            )) ?? [:]
        }
    }

    private func refreshRuntimeStates() {
        let connected = connectedDescriptors
        let connectedSessionIDs = Set(connected.map(\.sessionIdentifier))
        for sessionID in Array(statesBySessionID.keys) where !connectedSessionIDs.contains(sessionID) {
            if let state = statesBySessionID.removeValue(forKey: sessionID) {
                publishRuntimeStatus(state, connected: false)
                stopRepeat(state)
            }
        }

        for descriptor in connected {
            guard case let .bound(logicalDeviceID) = configuration.bindingResolution(
                for: descriptor,
                among: connected
            ),
                  let logicalDevice = configuration.logicalDevices[logicalDeviceID],
                  let profile = configuration.profiles[logicalDevice.profileName],
                  let presetID = initialPresetID(
                      logicalDeviceID: logicalDeviceID,
                      profile: profile
                  )
            else {
                if let state = statesBySessionID.removeValue(forKey: descriptor.sessionIdentifier) {
                    publishRuntimeStatus(state, connected: false)
                    stopRepeat(state)
                }
                continue
            }

            if let state = statesBySessionID[descriptor.sessionIdentifier] {
                if state.logicalDeviceID == logicalDeviceID,
                   state.profileName == logicalDevice.profileName {
                    publishRuntimeStatus(state, connected: true)
                    continue
                }
                publishRuntimeStatus(state, connected: false)
                stopRepeat(state)
                statesBySessionID.removeValue(forKey: descriptor.sessionIdentifier)
            }

            let mode = modeForPreset(
                presetID: presetID,
                profile: profile,
                fallback: .performance
            )
            let mapping = (try? GenericHIDMappingStore.mapping(
                logicalDeviceID: logicalDeviceID,
                presetID: presetID
            )) ?? [:]
            let state = GenericHIDDeviceRuntimeState(
                descriptor: descriptor,
                logicalDeviceID: logicalDeviceID,
                profileName: logicalDevice.profileName,
                presetID: presetID,
                mode: mode,
                mapping: mapping
            )
            statesBySessionID[descriptor.sessionIdentifier] = state
            publishRuntimeStatus(state, connected: true)
        }
    }

    private func initialPresetID(
        logicalDeviceID: String,
        profile: OverCUEProfile
    ) -> String? {
        if let assigned = configuration.assignedPresetID(for: logicalDeviceID),
           profile.presetGroup(id: assigned) != nil {
            return assigned
        }
        return profile.orderedPresetGroups.first?.id
    }

    private func applyRuntimeControl(_ notification: Notification) {
        guard let deviceID = notification.userInfo?[
            OverCUERuntimeControlNotification.deviceIDKey
        ] as? String,
              let state = statesBySessionID[deviceID],
              let profile = configuration.profiles[state.profileName]
        else { return }

        let requestedPresetID = notification.userInfo?[
            OverCUERuntimeControlNotification.presetGroupIDKey
        ] as? String
        let requestedGroup = notification.userInfo?[
            OverCUERuntimeControlNotification.groupKey
        ] as? Int
        let requestedMode = (notification.userInfo?[
            OverCUERuntimeControlNotification.modeKey
        ] as? String).flatMap { RekordboxMappingMode(rawValue: $0) }

        let nextPresetID: String?
        if let requestedPresetID, profile.presetGroup(id: requestedPresetID) != nil {
            nextPresetID = requestedPresetID
        } else if let requestedGroup,
                  profile.orderedPresetGroups.indices.contains(requestedGroup - 1) {
            nextPresetID = profile.orderedPresetGroups[requestedGroup - 1].id
        } else {
            nextPresetID = nil
        }
        guard let nextPresetID else { return }
        switchPreset(state, to: nextPresetID, preferredMode: requestedMode)
    }

    private func switchPreset(
        _ state: GenericHIDDeviceRuntimeState,
        to presetID: String,
        preferredMode: RekordboxMappingMode? = nil
    ) {
        guard let profile = configuration.profiles[state.profileName],
              profile.presetGroup(id: presetID) != nil
        else { return }
        keyboardOutput.releaseAll()
        _ = state.resolver.reset(mapping: state.mapping)
        stopRepeat(state)
        state.presetID = presetID
        state.mode = preferredMode ?? modeForPreset(
            presetID: presetID,
            profile: profile,
            fallback: state.mode
        )
        state.mapping = (try? GenericHIDMappingStore.mapping(
            logicalDeviceID: state.logicalDeviceID,
            presetID: presetID
        )) ?? [:]
        publishRuntimeStatus(state, connected: true)
    }

    private func route(_ event: ActionEvent, state: GenericHIDDeviceRuntimeState) {
        if let action = event.target.semanticAction,
           action.behavior == .internalCommand {
            guard event.phase == .triggered || event.phase == .repeated else { return }
            handleInternal(action, state: state)
            return
        }
        guard let shortcut = shortcut(for: event.target, mode: state.mode) else { return }
        switch event.phase {
        case .triggered, .repeated:
            keyboardOutput.trigger(shortcut, count: event.activationCount)
        case .pressed:
            guard let sourceID = event.sourceID else { return }
            if event.target.behavior == .hold {
                keyboardOutput.press(shortcut, sourceID: sourceID)
            } else {
                keyboardOutput.trigger(shortcut, count: event.activationCount)
                if event.target.behavior == .acceleratingRepeat {
                    startRepeat(state, sourceID: sourceID)
                }
            }
        case .released:
            if let sourceID = event.sourceID { keyboardOutput.release(sourceID: sourceID) }
        }
    }

    private func handleInternal(_ action: ActionID, state: GenericHIDDeviceRuntimeState) {
        switch action {
        case .cycleGroup:
            cyclePreset(state, step: 1)
        case .cycleGroupBackward:
            cyclePreset(state, step: -1)
        case .toggleRekordboxMode:
            state.mode = state.mode == .performance ? .export : .performance
            publishRuntimeStatus(state, connected: true)
        case .captureWaveformPosition:
            captureWaveformPosition(state)
        case .jogSearchLeft:
            jogSearch(state, direction: -1)
        case .jogSearchRight:
            jogSearch(state, direction: 1)
        default:
            break
        }
    }

    private func cyclePreset(_ state: GenericHIDDeviceRuntimeState, step: Int) {
        guard let profile = configuration.profiles[state.profileName],
              let nextID = OverCUEPresetGroupNavigator.nextID(
                  currentID: state.presetID,
                  step: step,
                  in: profile
              )
        else { return }
        switchPreset(state, to: nextID)
    }

    private func captureWaveformPosition(_ state: GenericHIDDeviceRuntimeState) {
        guard let location = CGEvent(source: nil)?.location else { return }
        guard let latest = try? OverCUEConfigurationFileStore.updateCurrent(
            at: OverCUEAppConfigurationLocation.url,
            fallback: configuration,
            { config in
                guard var profile = config.profiles[state.profileName] else { return }
                var mapping = profile.mapping(forPresetID: state.presetID)
                mapping.waveformPosition = WaveformPosition(x: location.x, y: location.y)
                profile.setMapping(mapping, forPresetID: state.presetID)
                config.profiles[state.profileName] = profile
            }
        ) else { return }
        configuration = latest
        OverCUEConfigurationChangedNotification.post()
    }

    private func jogSearch(_ state: GenericHIDDeviceRuntimeState, direction: CGFloat) {
        guard isRekordboxFrontmostForGenericHID(),
              let profile = configuration.profiles[state.profileName],
              let position = profile.mapping(forPresetID: state.presetID).waveformPosition,
              let original = CGEvent(source: nil)?.location
        else { return }
        let anchor = CGPoint(x: position.x, y: position.y)
        let destination = CGPoint(x: anchor.x + direction, y: anchor.y)
        postMouse(type: .mouseMoved, at: anchor)
        postMouse(type: .leftMouseDown, at: anchor)
        postMouse(type: .leftMouseDragged, at: destination)
        postMouse(type: .leftMouseUp, at: destination)
        postMouse(type: .mouseMoved, at: original)
    }

    private func postMouse(type: CGEventType, at point: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func startRepeat(_ state: GenericHIDDeviceRuntimeState, sourceID: ActionSourceID) {
        stopRepeat(state)
        state.repeatSourceID = sourceID
        state.repeatStartedAt = ProcessInfo.processInfo.systemUptime
        scheduleRepeat(state, afterMilliseconds: repeatProfile.initialDelayMilliseconds)
    }

    private func scheduleRepeat(
        _ state: GenericHIDDeviceRuntimeState,
        afterMilliseconds delay: Double
    ) {
        state.repeatTimer?.invalidate()
        let timer = Timer(timeInterval: delay / 1_000, repeats: false) { [weak self, weak state] _ in
            guard let self, let state else { return }
            self.repeatTimerFired(state)
        }
        state.repeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func repeatTimerFired(_ state: GenericHIDDeviceRuntimeState) {
        guard let sourceID = state.repeatSourceID,
              let startedAt = state.repeatStartedAt,
              let event = state.resolver.repeatedEvent(for: sourceID, mapping: state.mapping)
        else {
            stopRepeat(state)
            return
        }
        route(event, state: state)
        let heldMilliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        scheduleRepeat(
            state,
            afterMilliseconds: repeatProfile.repeatInterval(heldMilliseconds: heldMilliseconds)
        )
    }

    private func stopRepeat(_ state: GenericHIDDeviceRuntimeState) {
        state.repeatTimer?.invalidate()
        state.repeatTimer = nil
        state.repeatSourceID = nil
        state.repeatStartedAt = nil
    }

    private func shortcut(
        for target: ActionTarget,
        mode: RekordboxMappingMode
    ) -> RekordboxKeyboardShortcut? {
        guard let commandID = RekordboxActionAdapter.commandID(for: target) else { return nil }
        let mapping: RekordboxKeyMapping
        if let cached = keyMappingsByMode[mode] {
            mapping = cached
        } else {
            guard let loaded = try? loader.load(mode: mode).mapping else { return nil }
            keyMappingsByMode[mode] = loaded
            mapping = loaded
        }
        guard let raw = mapping.shortcut(for: commandID) else { return nil }
        return try? RekordboxKeyboardShortcut(rawValue: raw)
    }

    private func publishRuntimeStatus(_ state: GenericHIDDeviceRuntimeState, connected: Bool) {
        guard let profile = configuration.profiles[state.profileName],
              let index = profile.orderedPresetGroups.firstIndex(where: { $0.id == state.presetID })
        else { return }
        DistributedNotificationCenter.default().postNotificationName(
            OverCUERuntimeStatusNotification.name,
            object: nil,
            userInfo: [
                OverCUERuntimeStatusNotification.modeKey: state.mode.rawValue,
                OverCUERuntimeStatusNotification.groupKey: index + 1,
                OverCUERuntimeStatusNotification.presetGroupIDKey: state.presetID,
                OverCUERuntimeStatusNotification.scopeKey: OverCUERuntimeNotificationScope.device.rawValue,
                OverCUERuntimeStatusNotification.deviceIDKey: state.descriptor.sessionIdentifier,
                OverCUERuntimeStatusNotification.logicalDeviceIDKey: state.logicalDeviceID,
                OverCUERuntimeStatusNotification.profileNameKey: state.profileName,
                OverCUERuntimeStatusNotification.connectedKey: connected,
            ],
            deliverImmediately: true
        )
    }

    private func modeForPreset(
        presetID: String,
        profile: OverCUEProfile,
        fallback: RekordboxMappingMode
    ) -> RekordboxMappingMode {
        profile.mapping(forPresetID: presetID).rekordboxMode ?? fallback
    }

    private var connectedDescriptors: [HIDPhysicalDeviceDescriptor] {
        groups.values.map(\.representative).sorted { $0.sessionIdentifier < $1.sessionIdentifier }
    }

    @discardableResult
    private func registerInterface(_ device: IOHIDDevice) -> HIDPhysicalDeviceDescriptor? {
        guard let raw = candidateDescriptor(for: device),
              let persistentIdentifier = raw.persistentIdentifier
        else { return nil }
        let interfaceID = interfaceIdentifier(device)
        if let existingKey = groupKeyByInterfaceID[interfaceID],
           let group = groups[existingKey] {
            return group.representative
        }
        let key = LiveGroupKey(
            persistentIdentifier: persistentIdentifier,
            connectionQualifier: connectionQualifier(descriptor: raw, interfaceID: interfaceID)
        )
        groupKeyByInterfaceID[interfaceID] = key
        if var group = groups[key] {
            group.interfaceIDs.insert(interfaceID)
            groups[key] = group
            return group.representative
        }
        groups[key] = LiveGroup(representative: raw, interfaceIDs: [interfaceID])
        return raw
    }

    private func candidateDescriptor(for device: IOHIDDevice) -> HIDPhysicalDeviceDescriptor? {
        let vendorID = (property(device, kIOHIDVendorIDKey) as? NSNumber)?.intValue ?? 0
        let productID = (property(device, kIOHIDProductIDKey) as? NSNumber)?.intValue ?? 0
        guard vendorID != 0,
              productID != 0,
              let serial = (property(device, kIOHIDSerialNumberKey) as? String)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !serial.isEmpty,
              configuration.physicalDeviceBindings.contains(where: {
                  $0.kind == .genericHID
                      && $0.vendorID == vendorID
                      && $0.productID == productID
                      && $0.serialNumber == serial
              })
        else { return nil }
        return HIDPhysicalDeviceDescriptor(
            kind: .genericHID,
            vendorID: vendorID,
            productID: productID,
            serialNumber: serial,
            productName: property(device, kIOHIDProductKey) as? String,
            manufacturerName: property(device, kIOHIDManufacturerKey) as? String,
            transport: property(device, kIOHIDTransportKey) as? String,
            locationID: (property(device, kIOHIDLocationIDKey) as? NSNumber)?.uint32Value,
            transportIdentifier: String(interfaceIdentifier(device), radix: 16)
        )
    }

    private func connectionQualifier(
        descriptor: HIDPhysicalDeviceDescriptor,
        interfaceID: UInt
    ) -> String {
        if let locationID = descriptor.locationID, locationID != 0 {
            return String(format: "location:%08X", locationID)
        }
        return "interface:\(String(interfaceID, radix: 16))"
    }

    private func interfaceIdentifier(_ device: IOHIDDevice) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
    }

    private func collectionPath(for element: IOHIDElement) -> [HIDUsage] {
        var path: [HIDUsage] = []
        var parent = IOHIDElementGetParent(element)
        while let current = parent {
            path.append(HIDUsage(
                page: IOHIDElementGetUsagePage(current),
                usage: IOHIDElementGetUsage(current)
            ))
            parent = IOHIDElementGetParent(current)
        }
        return path.reversed()
    }

    private func matchingElementCount(
        for element: IOHIDElement,
        input: GenericHIDInputDescriptor
    ) -> Int? {
        let device = IOHIDElementGetDevice(element)
        guard let elements = IOHIDDeviceCopyMatchingElements(
            device,
            nil,
            IOOptionBits(kIOHIDOptionsTypeNone)
        ) as? [IOHIDElement] else { return nil }
        return elements.filter { candidate in
            let reportID = UInt32(IOHIDElementGetReportID(candidate))
            return GenericHIDInputDescriptor(
                usagePage: IOHIDElementGetUsagePage(candidate),
                usage: IOHIDElementGetUsage(candidate),
                reportID: reportID == 0 ? nil : reportID,
                collectionPath: collectionPath(for: candidate)
            ) == input
        }.count
    }

    private func property(_ device: IOHIDDevice, _ key: String) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }
}

private func isRekordboxFrontmostForGenericHID() -> Bool {
    MainActor.assumeIsolated {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.pioneerdj.rekordboxdj"
    }
}

private func genericRuntimeDeviceMatched(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<GenericHIDRuntimeCoordinator>.fromOpaque(context).takeUnretainedValue()
        .didMatch(device: device, result: result)
}

private func genericRuntimeDeviceRemoved(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<GenericHIDRuntimeCoordinator>.fromOpaque(context).takeUnretainedValue()
        .didRemove(device: device, result: result)
}

private func genericRuntimeInputValueReceived(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard let context else { return }
    Unmanaged<GenericHIDRuntimeCoordinator>.fromOpaque(context).takeUnretainedValue()
        .didReceiveValue(result: result, value: value)
}
