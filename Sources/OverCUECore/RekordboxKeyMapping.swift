import Foundation

public struct RekordboxShortcutEntry: Equatable, Identifiable, Sendable {
    public let index: Int
    public let commandID: String
    public let description: String
    public let shortcut: String

    public init(index: Int, commandID: String, description: String, shortcut: String) {
        self.index = index
        self.commandID = commandID
        self.description = description
        self.shortcut = shortcut
    }

    public var id: String {
        "\(commandID):\(index)"
    }
}

public struct RekordboxKeyMapping: Equatable, Sendable {
    public let name: String
    public let entries: [RekordboxShortcutEntry]
    public let shortcutsByCommandID: [String: String]

    public init(
        name: String,
        entries: [RekordboxShortcutEntry] = [],
        shortcutsByCommandID: [String: String]
    ) {
        self.name = name
        self.entries = entries
        self.shortcutsByCommandID = shortcutsByCommandID
    }

    public func shortcut(for commandID: String) -> String? {
        shortcutsByCommandID[commandID]
    }

    public static func parse(data: Data) throws -> RekordboxKeyMapping {
        let delegate = MappingXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw parser.parserError ?? RekordboxKeyMappingError.invalidXML
        }
        return RekordboxKeyMapping(
            name: delegate.mappingName ?? "Unknown",
            entries: delegate.entries,
            shortcutsByCommandID: delegate.shortcutsByCommandID
        )
    }
}

public enum RekordboxKeyMappingError: Error {
    case invalidXML
}

private final class MappingXMLDelegate: NSObject, XMLParserDelegate {
    var mappingName: String?
    var entries: [RekordboxShortcutEntry] = []
    var shortcutsByCommandID: [String: String] = [:]

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "VALUE",
           attributeDict["name"] == "keyMappingName" {
            mappingName = attributeDict["val"]
        } else if elementName == "MAPPING",
                  let commandID = attributeDict["commandId"],
                  let key = attributeDict["key"],
                  !key.isEmpty {
            entries.append(
                RekordboxShortcutEntry(
                    index: entries.count,
                    commandID: commandID,
                    description: attributeDict["description"] ?? commandID,
                    shortcut: key
                )
            )
            shortcutsByCommandID[commandID] = key
        }
    }
}

public enum RekordboxMappingMode: String, CaseIterable, Identifiable, Sendable {
    case performance
    case export

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .performance: "PERFORMANCE"
        case .export: "EXPORT"
        }
    }
}

public struct LoadedRekordboxKeyMapping: Equatable, Sendable {
    public let mode: RekordboxMappingMode
    public let mappingID: String
    public let url: URL
    public let mapping: RekordboxKeyMapping

    public init(
        mode: RekordboxMappingMode,
        mappingID: String,
        url: URL,
        mapping: RekordboxKeyMapping
    ) {
        self.mode = mode
        self.mappingID = mappingID
        self.url = url
        self.mapping = mapping
    }
}

public struct RekordboxKeyMappingLoader: Sendable {
    public let baseURL: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        baseURL = homeDirectory
            .appendingPathComponent("Library/Application Support/Pioneer/rekordbox6")
    }

    public func load(mode: RekordboxMappingMode) throws -> LoadedRekordboxKeyMapping {
        let mappingID: String
        switch mode {
        case .export:
            mappingID = "0000000000030"
        case .performance:
            let settingsURL = baseURL.appendingPathComponent("rekordbox3.settings")
            let settings = try RekordboxSettings.parse(data: Data(contentsOf: settingsURL))
            guard let selectedID = settings.performanceKeyMappingID else {
                throw RekordboxKeyMappingLoaderError.selectedPerformanceMappingNotFound
            }
            mappingID = selectedID
        }

        let mappingURL = baseURL
            .appendingPathComponent("KeyMappings")
            .appendingPathComponent("rekordbox_\(mappingID).mappings")
        let mapping = try RekordboxKeyMapping.parse(data: Data(contentsOf: mappingURL))
        return LoadedRekordboxKeyMapping(
            mode: mode,
            mappingID: mappingID,
            url: mappingURL,
            mapping: mapping
        )
    }
}

public enum RekordboxKeyMappingLoaderError: Error, LocalizedError {
    case selectedPerformanceMappingNotFound

    public var errorDescription: String? {
        switch self {
        case .selectedPerformanceMappingNotFound:
            "選択中のPERFORMANCEキーマッピングをrekordbox設定から取得できませんでした。"
        }
    }
}

public enum RekordboxShortcutCategory: String, CaseIterable, Identifiable, Sendable {
    case browse = "Browse"
    case deck1 = "Deck 1"
    case deck2 = "Deck 2"
    case allDecks = "All Decks"
    case sampler = "Sampler"
    case recordings = "Recordings"
    case general = "General"
    case view = "View"
    case playlist = "Playlist"
    case other = "Other"

    public var id: String { rawValue }

    public static func category(for commandID: String) -> RekordboxShortcutCategory {
        switch commandID.lowercased() {
        case "3000", "3001", "3002":
            return .allDecks
        case let value where value.hasPrefix("30"):
            return .deck1
        case let value where value.hasPrefix("31"):
            return .deck2
        case let value where value.hasPrefix("f"):
            return .sampler
        case "d0f0":
            return .recordings
        case "7000", "7003":
            return .general
        case "b04d":
            return .view
        case "500a":
            return .playlist
        case let value where value.hasPrefix("b"):
            return .browse
        default:
            return .other
        }
    }
}

public struct RekordboxSettings: Equatable, Sendable {
    public let performanceKeyMappingID: String?

    public static func parse(data: Data) throws -> RekordboxSettings {
        let delegate = SettingsXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw parser.parserError ?? RekordboxKeyMappingError.invalidXML
        }
        return RekordboxSettings(performanceKeyMappingID: delegate.performanceKeyMappingID)
    }
}

private final class SettingsXMLDelegate: NSObject, XMLParserDelegate {
    var performanceKeyMappingID: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "VALUE",
           attributeDict["name"] == "performaceKeyMapping" {
            performanceKeyMappingID = attributeDict["val"]
        }
    }
}
