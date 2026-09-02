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

    private static let lock = NSLock()

    static func read() throws -> GenericHIDMappingDocument {
        lock.lock()
        defer { lock.unlock() }
        return try readUnlocked()
    }

    static func mapping(
        logicalDeviceID: String,
        presetID: String,
        in document: GenericHIDMappingDocument
    ) -> [GenericHIDInputBindingKey: ActionTarget] {
        let records = document.logicalDevices[logicalDeviceID]?[presetID] ?? []
        var result: [GenericHIDInputBindingKey: ActionTarget] = [:]
        for record in records {
            guard let target = ActionTarget(configurationValue: record.target) else { continue }
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
        target: ActionTarget
    ) throws {
        try update { document in
            var presetMappings = document.logicalDevices[logicalDeviceID] ?? [:]
            var records = presetMappings[presetID] ?? []
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
            presetMappings[presetID] = records
            document.logicalDevices[logicalDeviceID] = presetMappings
        }
        GenericHIDMappingChangedNotification.post()
    }

    static func remove(
        logicalDeviceID: String,
        presetID: String,
        input: GenericHIDInputBindingKey
    ) throws {
        try update { document in
            guard var presetMappings = document.logicalDevices[logicalDeviceID],
                  var records = presetMappings[presetID]
            else { return }
            records.removeAll { $0.input == input }
            if records.isEmpty {
                presetMappings.removeValue(forKey: presetID)
            } else {
                presetMappings[presetID] = records
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
        target: ActionTarget
    ) throws {
        try update { document in
            for logicalDeviceID in logicalDeviceIDs {
                guard var presetMappings = document.logicalDevices[logicalDeviceID],
                      var records = presetMappings[presetID]
                else { continue }
                records.removeAll { $0.target == target.configurationValue }
                if records.isEmpty {
                    presetMappings.removeValue(forKey: presetID)
                } else {
                    presetMappings[presetID] = records
                }
                if presetMappings.isEmpty {
                    document.logicalDevices.removeValue(forKey: logicalDeviceID)
                } else {
                    document.logicalDevices[logicalDeviceID] = presetMappings
                }
            }
        }
        GenericHIDMappingChangedNotification.post()
    }

    private static func update(
        _ body: (inout GenericHIDMappingDocument) throws -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        var document = try readUnlocked()
        try body(&document)
        try writeUnlocked(document)
    }

    private static func readUnlocked() throws -> GenericHIDMappingDocument {
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

    private static func writeUnlocked(_ document: GenericHIDMappingDocument) throws {
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
