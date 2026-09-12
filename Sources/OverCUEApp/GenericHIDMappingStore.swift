import Foundation
import OverCUECore

struct GenericHIDStoredAssignment: Codable, Equatable, Sendable {
    var input: GenericHIDInputBindingKey
    var target: String
}

struct GenericHIDMappingDocument: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int = currentVersion
    var logicalDevices: [String: [String: [GenericHIDStoredAssignment]]] = [:]
}

enum GenericHIDMappingStoreError: Error, LocalizedError, Sendable {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            "Unsupported Generic HID mapping version \(version)."
        }
    }
}

enum GenericHIDMappingChangedNotification {
    static let name = Notification.Name("com.overcue.generic-hid-mapping-changed")

    static func post() {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

enum GenericHIDMappingStore {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/OverCUE/generic-hid.json")

    /// OverCUE Control is device-scoped, not Preset-scoped. Keep the existing
    /// sidecar shape for compatibility and reserve one synthetic Preset key for
    /// device-level internal actions.
    static let controlPresetID = "__overcue-control__"

    private static let lock = NSLock()

    static func read(at documentURL: URL = url) throws -> GenericHIDMappingDocument {
        // Atomic replacement guarantees one complete old/new document. A reader
        // must not wait behind an unrelated sidecar writer on the UI runloop.
        // Read-modify-write transactions still hold the lock in update().
        return try readUnlocked(at: documentURL)
    }

    static func mapping(
        logicalDeviceID: String,
        presetID: String,
        in document: GenericHIDMappingDocument
    ) -> [GenericHIDInputBindingKey: ActionTarget] {
        let presetMappings = document.logicalDevices[logicalDeviceID] ?? [:]
        let presetRecords = presetMappings[presetID] ?? []
        let explicitControlRecords = presetMappings[controlPresetID] ?? []

        // Before device-level OverCUE Control existed, internal actions lived in
        // whichever Preset happened to be edited. Preserve those users by taking
        // one deterministic legacy internal mapping whenever the new device-level
        // bucket has not been written yet. Once a Control is edited, assign()
        // persists it in controlPresetID and it becomes independent of Presets.
        let legacyControlRecords: [GenericHIDStoredAssignment]
        if explicitControlRecords.isEmpty {
            legacyControlRecords = presetMappings
                .filter { $0.key != controlPresetID }
                .sorted { $0.key < $1.key }
                .flatMap(\.value)
                .filter { record in
                    ActionTarget(configurationValue: record.target)?.behavior.isInternal == true
                }
                .reduce(into: [GenericHIDInputBindingKey: GenericHIDStoredAssignment]()) {
                    result, record in
                    if result[record.input] == nil { result[record.input] = record }
                }
                .values
                .sorted { $0.input.overCUEStableSortKey < $1.input.overCUEStableSortKey }
        } else {
            legacyControlRecords = []
        }

        var result: [GenericHIDInputBindingKey: ActionTarget] = [:]
        for record in presetRecords {
            guard let target = ActionTarget(configurationValue: record.target),
                  !target.behavior.isInternal
            else { continue }
            result[record.input] = target
        }
        for record in explicitControlRecords + legacyControlRecords {
            guard let target = ActionTarget(configurationValue: record.target),
                  target.behavior.isInternal
            else { continue }
            result[record.input] = target
        }
        return result
    }

    static func mapping(
        logicalDeviceID: String,
        presetID: String
    ) throws -> [GenericHIDInputBindingKey: ActionTarget] {
        mapping(
            logicalDeviceID: logicalDeviceID,
            presetID: presetID,
            in: try read()
        )
    }

    static func assign(
        logicalDeviceID: String,
        presetID: String,
        input: GenericHIDInputBindingKey,
        target: ActionTarget,
        at documentURL: URL = url,
        postsNotification: Bool = true
    ) throws {
        try update(at: documentURL) { document in
            var presetMappings = document.logicalDevices[logicalDeviceID] ?? [:]
            let storagePresetID = target.behavior.isInternal ? controlPresetID : presetID
            var records = presetMappings[storagePresetID] ?? []
            records.removeAll { $0.input == input }
            records.append(
                GenericHIDStoredAssignment(
                    input: input,
                    target: target.configurationValue
                )
            )
            records.sort { lhs, rhs in
                lhs.input.overCUEStableSortKey < rhs.input.overCUEStableSortKey
            }
            presetMappings[storagePresetID] = records
            document.logicalDevices[logicalDeviceID] = presetMappings
        }
        if postsNotification { GenericHIDMappingChangedNotification.post() }
    }

    static func remove(
        logicalDeviceID: String,
        presetID: String,
        input: GenericHIDInputBindingKey
    ) throws {
        try update { document in
            guard var presetMappings = document.logicalDevices[logicalDeviceID] else { return }
            for storagePresetID in [presetID, controlPresetID] {
                guard var records = presetMappings[storagePresetID] else { continue }
                records.removeAll { $0.input == input }
                if records.isEmpty {
                    presetMappings.removeValue(forKey: storagePresetID)
                } else {
                    presetMappings[storagePresetID] = records
                }
            }
            if presetMappings.isEmpty {
                document.logicalDevices.removeValue(forKey: logicalDeviceID)
            } else {
                document.logicalDevices[logicalDeviceID] = presetMappings
            }
        }
        GenericHIDMappingChangedNotification.post()
    }

    static func removeTarget(
        logicalDeviceIDs: Set<String>,
        presetID: String,
        target: ActionTarget,
        at documentURL: URL = url,
        postsNotification: Bool = true
    ) throws {
        try update(at: documentURL) { document in
            for logicalDeviceID in logicalDeviceIDs {
                guard var presetMappings = document.logicalDevices[logicalDeviceID] else { continue }
                let storagePresetIDs: [String]
                if target.behavior.isInternal {
                    // Delete both the new device-level Control mapping and any
                    // legacy Preset-scoped copies so a removed Control cannot
                    // reappear through compatibility fallback.
                    storagePresetIDs = Array(presetMappings.keys)
                } else {
                    storagePresetIDs = [presetID]
                }
                for storagePresetID in storagePresetIDs {
                    guard var records = presetMappings[storagePresetID] else { continue }
                    records.removeAll { $0.target == target.configurationValue }
                    if records.isEmpty {
                        presetMappings.removeValue(forKey: storagePresetID)
                    } else {
                        presetMappings[storagePresetID] = records
                    }
                }
                if presetMappings.isEmpty {
                    document.logicalDevices.removeValue(forKey: logicalDeviceID)
                } else {
                    document.logicalDevices[logicalDeviceID] = presetMappings
                }
            }
        }
        if postsNotification { GenericHIDMappingChangedNotification.post() }
    }

    private static func update(
        at documentURL: URL = url,
        _ body: (inout GenericHIDMappingDocument) throws -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        var document = try readUnlocked(at: documentURL)
        try body(&document)
        try writeUnlocked(document, at: documentURL)
    }

    private static func readUnlocked(at url: URL) throws -> GenericHIDMappingDocument {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return GenericHIDMappingDocument()
        }
        let document = try JSONDecoder().decode(
            GenericHIDMappingDocument.self,
            from: Data(contentsOf: url)
        )
        guard document.version == GenericHIDMappingDocument.currentVersion else {
            throw GenericHIDMappingStoreError.unsupportedVersion(document.version)
        }
        return document
    }

    private static func writeUnlocked(_ document: GenericHIDMappingDocument, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url, options: .atomic)
    }
}

extension GenericHIDInputBindingKey {
    var overCUEStableSortKey: String {
        let report = input.reportID.map(String.init) ?? "-"
        let path = input.collectionPath.map {
            String(format: "%04X:%04X", $0.page, $0.usage)
        }.joined(separator: "/")
        return String(
            format: "%04X:%04X:%@:%@:%@",
            input.usage.page,
            input.usage.usage,
            report,
            path,
            activation.rawValue
        )
    }

    var overCUEDisplayName: String {
        let base: String
        switch (input.usage.page, input.usage.usage) {
        case (0x07, 0x59...0x62):
            base = "Keypad \(input.usage.usage - 0x58)"
        case (0x0C, 0x00E9):
            base = "Consumer Volume +"
        case (0x0C, 0x00EA):
            base = "Consumer Volume -"
        case (0x0C, 0x00E2):
            base = "Consumer Mute"
        case (0x07, _):
            base = String(format: "Keyboard 0x%04X", input.usage.usage)
        case (0x0C, _):
            base = String(format: "Consumer 0x%04X", input.usage.usage)
        case (0x09, _):
            base = String(format: "Button %u", input.usage.usage)
        default:
            base = String(
                format: "HID 0x%04X:0x%04X",
                input.usage.page,
                input.usage.usage
            )
        }

        switch activation {
        case .press:
            return base
        case .relativePositive:
            return "\(base) +"
        case .relativeNegative:
            return "\(base) -"
        }
    }
}
