import Foundation
import OverCUECore

private struct WebAPISessionResponse: Encodable {
    let token: String
}

private struct WebAPIReorderRequest: Decodable {
    let ids: [String]
}

private struct WebAPIIDRequest: Decodable {
    let id: String
}

private struct WebAPINameRequest: Decodable {
    let name: String
}

private struct WebAPIRenameRequest: Decodable {
    let id: String
    let name: String
}

private struct WebAPIGroupPresetIncludeRequest: Decodable {
    let groupPresetID: String
    let logicalDeviceID: String
    let included: Bool
}

private struct WebAPIGroupPresetAssignmentRequest: Decodable {
    let groupPresetID: String
    let logicalDeviceID: String
    let presetID: String
}

private struct WebAPIPresetSummary: Encodable {
    let id: String
    let name: String
    let order: Int
    let profileName: String
    let rekordboxMode: String?
}

private struct WebAPIGroupPresetAssignment: Encodable {
    let logicalDeviceID: String
    let presetID: String
}

private struct WebAPIGroupPresetSummary: Encodable {
    let id: String
    let name: String
    let order: Int
    let assignments: [WebAPIGroupPresetAssignment]
}

private struct WebAPIDevicePresetOption: Encodable {
    let id: String
    let name: String
    let order: Int
}

private struct WebAPIDeviceSummary: Encodable {
    let id: String
    let name: String
    let profileName: String
    let connected: Bool
    let presets: [WebAPIDevicePresetOption]
}

private struct WebAPIRuntimeStatus: Encodable {
    let inputEnabled: Bool
    let bridgeStatus: String
    let activeGroupPresetID: String?
}

private struct WebAPISnapshot: Encodable {
    let presets: [WebAPIPresetSummary]
    let groupPresets: [WebAPIGroupPresetSummary]
    let devices: [WebAPIDeviceSummary]
    let runtime: WebAPIRuntimeStatus
}

private struct WebAPIShortcutAssignment: Encodable {
    let functionName: String
    let shortcut: String?
}

private struct WebAPIShortcutKeyState: Encodable {
    let id: String
    let assignment: WebAPIShortcutAssignment?
    let pressed: Bool
}

private struct WebAPIShortcutDialState: Encodable {
    let direction: String
    let assignment: WebAPIShortcutAssignment?
    let active: Bool
}

private struct WebAPIShortcutPanel: Encodable {
    let deviceKind: String
    let deviceName: String
    let rotationQuarterTurns: Int
    let presetID: String?
    let presetName: String?
    let presetOrder: Int?
    let keys: [WebAPIShortcutKeyState]
    let dial: [WebAPIShortcutDialState]
}

@MainActor
final class OverCUEWebAPICoordinator: ObservableObject {
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false

    private static let allowedWriteOrigins: Set<String> = [
        "http://127.0.0.1:4173",
        "http://localhost:4173",
        "http://127.0.0.1:4174",
        "http://localhost:4174",
    ]

    private weak var shortcutModel: ShortcutSettingsModel?
    private weak var deviceModel: DeviceManagementModel?
    private var server: OverCUELocalHTTPServer?
    private var sessionToken = UUID().uuidString.lowercased()
    private let webUIAssets = OverCUEWebUIAssetStore()
    private let groupPresetModel = GroupPresetManagementModel()

    func start(shortcutModel: ShortcutSettingsModel, deviceModel: DeviceManagementModel) {
        self.shortcutModel = shortcutModel
        self.deviceModel = deviceModel
        guard server == nil else { return }

        sessionToken = UUID().uuidString.lowercased()
        let server = OverCUELocalHTTPServer { [weak self] request in
            guard let self else {
                return Self.errorResponse(
                    statusCode: 503,
                    reason: "Service Unavailable",
                    "Web API is unavailable."
                )
            }
            return await self.handle(request)
        }

        do {
            try server.start()
            self.server = server
            isRunning = true
            errorMessage = nil
        } catch {
            isRunning = false
            errorMessage = error.localizedDescription
            NSLog("OverCUE local Web API failed to start: %@", error.localizedDescription)
        }
    }

    func stop() {
        server?.stop()
        server = nil
        isRunning = false
    }

    private func handle(_ request: OverCUELocalHTTPRequest) -> OverCUELocalHTTPResponse {
        do {
            switch (request.method, request.path) {
            case ("GET", "/api/v1/session"):
                return try jsonResponse(WebAPISessionResponse(token: sessionToken))

            case ("GET", "/api/v1/snapshot"):
                return try jsonResponse(makeSnapshot())

            case ("GET", "/api/v1/shortcuts/panel"):
                return try jsonResponse(makeShortcutPanel())

            case ("PUT", "/api/v1/presets/order"):
                guard let rejection = validateWrite(request) else {
                    let payload = try JSONDecoder().decode(WebAPIReorderRequest.self, from: request.body)
                    try reorderPresets(ids: payload.ids)
                    return try jsonResponse(makeSnapshot())
                }
                return rejection

            case ("PUT", "/api/v1/group-presets/order"):
                guard let rejection = validateWrite(request) else {
                    let payload = try JSONDecoder().decode(WebAPIReorderRequest.self, from: request.body)
                    try reorderGroupPresets(ids: payload.ids)
                    return try jsonResponse(makeSnapshot())
                }
                return rejection

            case ("PUT", "/api/v1/group-presets/active"):
                guard let rejection = validateWrite(request) else {
                    let payload = try JSONDecoder().decode(WebAPIIDRequest.self, from: request.body)
                    try groupPresetModel.activate(id: payload.id)
                    return try jsonResponse(makeSnapshot())
                }
                return rejection

            case ("PUT", "/api/v1/group-presets/add"):
                guard let rejection = validateWrite(request) else {
                    let payload = try JSONDecoder().decode(WebAPINameRequest.self, from: request.body)
                    _ = try groupPresetModel.add(name: payload.name)
                    return try jsonResponse(makeSnapshot())
                }
                return rejection

            case ("PUT", "/api/v1/group-presets/rename"):
                guard let rejection = validateWrite(request) else {
                    let payload = try JSONDecoder().decode(WebAPIRenameRequest.self, from: request.body)
                    try groupPresetModel.rename(id: payload.id, name: payload.name)
                    return try jsonResponse(makeSnapshot())
                }
                return rejection

            case ("PUT", "/api/v1/group-presets/delete"):
                guard let rejection = validateWrite(request) else {
                    let payload = try JSONDecoder().decode(WebAPIIDRequest.self, from: request.body)
                    try groupPresetModel.delete(id: payload.id)
                    return try jsonResponse(makeSnapshot())
                }
                return rejection

            case ("PUT", "/api/v1/group-presets/include"):
                guard let rejection = validateWrite(request) else {
                    let payload = try JSONDecoder().decode(WebAPIGroupPresetIncludeRequest.self, from: request.body)
                    try groupPresetModel.setIncluded(
                        groupPresetID: payload.groupPresetID,
                        logicalDeviceID: payload.logicalDeviceID,
                        included: payload.included
                    )
                    return try jsonResponse(makeSnapshot())
                }
                return rejection

            case ("PUT", "/api/v1/group-presets/assignment"):
                guard let rejection = validateWrite(request) else {
                    let payload = try JSONDecoder().decode(WebAPIGroupPresetAssignmentRequest.self, from: request.body)
                    try groupPresetModel.assignPreset(
                        groupPresetID: payload.groupPresetID,
                        logicalDeviceID: payload.logicalDeviceID,
                        presetID: payload.presetID
                    )
                    return try jsonResponse(makeSnapshot())
                }
                return rejection

            default:
                if request.method == "GET", !request.path.hasPrefix("/api/") {
                    return webUIAssets.response(for: request.path)
                }
                return Self.errorResponse(statusCode: 404, reason: "Not Found", "Endpoint not found.")
            }
        } catch let error as DecodingError {
            return Self.errorResponse(statusCode: 400, reason: "Bad Request", error.localizedDescription)
        } catch let error as OverCUEConfigurationOrderingError {
            return Self.errorResponse(statusCode: 422, reason: "Unprocessable Content", error.localizedDescription)
        } catch let error as GroupPresetManagementError {
            return Self.errorResponse(statusCode: 422, reason: "Unprocessable Content", error.localizedDescription)
        } catch {
            return Self.errorResponse(statusCode: 500, reason: "Internal Server Error", error.localizedDescription)
        }
    }

    private func validateWrite(_ request: OverCUELocalHTTPRequest) -> OverCUELocalHTTPResponse? {
        if let origin = request.headers["origin"], !Self.allowedWriteOrigins.contains(origin) {
            return Self.errorResponse(statusCode: 403, reason: "Forbidden", "Origin is not allowed.")
        }
        guard request.headers["x-overcue-session"] == sessionToken else {
            return Self.errorResponse(statusCode: 403, reason: "Forbidden", "Invalid OverCUE session token.")
        }
        return nil
    }

    private func makeSnapshot() throws -> WebAPISnapshot {
        guard let shortcutModel, let deviceModel else {
            throw NSError(
                domain: "OverCUE.WebAPI",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Web API models are not attached."]
            )
        }

        let configuration = try readConfiguration()
        let defaultProfileName = configuration.defaultProfile
        let presets = configuration.profiles[defaultProfileName]?.orderedPresetGroups.map { preset in
            WebAPIPresetSummary(
                id: preset.id,
                name: preset.name,
                order: preset.order,
                profileName: defaultProfileName,
                rekordboxMode: preset.mapping.rekordboxMode?.rawValue
            )
        } ?? []

        let groupPresets = configuration.orderedGroupPresets.map { groupPreset in
            WebAPIGroupPresetSummary(
                id: groupPreset.id,
                name: groupPreset.name,
                order: groupPreset.order,
                assignments: groupPreset.devicePresetAssignments
                    .map { WebAPIGroupPresetAssignment(logicalDeviceID: $0.key, presetID: $0.value) }
                    .sorted { $0.logicalDeviceID < $1.logicalDeviceID }
            )
        }

        let connectedByID = Dictionary(uniqueKeysWithValues: deviceModel.devices.map { ($0.id, $0.isConnected) })
        let devices = configuration.logicalDevices.map { id, device in
            let devicePresets = configuration.profiles[device.profileName]?.orderedPresetGroups.map { preset in
                WebAPIDevicePresetOption(
                    id: preset.id,
                    name: preset.name,
                    order: preset.order
                )
            } ?? []
            return WebAPIDeviceSummary(
                id: id,
                name: device.name,
                profileName: device.profileName,
                connected: connectedByID[id] ?? false,
                presets: devicePresets
            )
        }
        .sorted {
            let nameOrder = $0.name.localizedStandardCompare($1.name)
            return nameOrder == .orderedSame ? $0.id < $1.id : nameOrder == .orderedAscending
        }

        return WebAPISnapshot(
            presets: presets,
            groupPresets: groupPresets,
            devices: devices,
            runtime: WebAPIRuntimeStatus(
                inputEnabled: shortcutModel.isBridgeEnabled,
                bridgeStatus: bridgeStatusValue(shortcutModel.bridgeStatus),
                activeGroupPresetID: configuration.activeGroupPresetID
            )
        )
    }

    private func makeShortcutPanel() throws -> WebAPIShortcutPanel {
        guard let shortcutModel else {
            throw NSError(
                domain: "OverCUE.WebAPI",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Shortcut model is not attached."]
            )
        }

        let preset = shortcutModel.availablePresetGroups.indices.contains(shortcutModel.selectedGroup - 1)
            ? shortcutModel.availablePresetGroups[shortcutModel.selectedGroup - 1]
            : nil

        let keys = ACK05Key.allCases.map { key in
            WebAPIShortcutKeyState(
                id: key.rawValue,
                assignment: shortcutModel.deviceAssignment(to: key).map {
                    WebAPIShortcutAssignment(functionName: $0.functionName, shortcut: $0.shortcut)
                },
                pressed: shortcutModel.pressedDeviceKeys.contains(key)
            )
        }

        let dialDirections: [(DialDirection, String)] = [
            (.counterclockwise, "counterclockwise"),
            (.clockwise, "clockwise"),
        ]
        let dial = dialDirections.map { direction, value in
            WebAPIShortcutDialState(
                direction: value,
                assignment: shortcutModel.dialAssignment(direction).map {
                    WebAPIShortcutAssignment(functionName: $0.functionName, shortcut: $0.shortcut)
                },
                active: shortcutModel.activeDialDirection == direction
            )
        }

        return WebAPIShortcutPanel(
            deviceKind: "ack05",
            deviceName: "ACK05",
            rotationQuarterTurns: shortcutModel.rotationQuarterTurns,
            presetID: preset?.id,
            presetName: preset?.name,
            presetOrder: preset?.order,
            keys: keys,
            dial: dial
        )
    }

    private func reorderPresets(ids: [String]) throws {
        _ = try OverCUEConfigurationFileStore.updateCurrent(
            at: OverCUEAppConfigurationLocation.url,
            fallback: .defaultValue
        ) { latest in
            try OverCUEConfigurationOrdering.reorderPresets(ids: ids, in: &latest)
        }
        OverCUEConfigurationChangedNotification.post()
    }

    private func reorderGroupPresets(ids: [String]) throws {
        _ = try OverCUEConfigurationFileStore.updateCurrent(
            at: OverCUEAppConfigurationLocation.url,
            fallback: .defaultValue
        ) { latest in
            try OverCUEConfigurationOrdering.reorderGroupPresets(ids: ids, in: &latest)
        }
        OverCUEConfigurationChangedNotification.post()
    }

    private func readConfiguration() throws -> OverCUEConfiguration {
        if FileManager.default.fileExists(atPath: OverCUEAppConfigurationLocation.url.path) {
            return try OverCUEConfigurationFileStore.readCurrent(at: OverCUEAppConfigurationLocation.url)
        }
        return .defaultValue
    }

    private func bridgeStatusValue(_ status: OverCUECLIRuntime.Status) -> String {
        switch status {
        case .stopped: "stopped"
        case .starting: "starting"
        case .running: "running"
        case .degraded: "degraded"
        case .failed: "failed"
        }
    }

    private func jsonResponse<T: Encodable>(_ value: T) throws -> OverCUELocalHTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return .json(body: try encoder.encode(value))
    }

    nonisolated private static func errorResponse(
        statusCode: Int,
        reason: String,
        _ message: String
    ) -> OverCUELocalHTTPResponse {
        let body = (try? JSONEncoder().encode(["error": message]))
            ?? Data("{\"error\":\"Request failed.\"}".utf8)
        return .json(statusCode: statusCode, reason: reason, body: body)
    }
}
