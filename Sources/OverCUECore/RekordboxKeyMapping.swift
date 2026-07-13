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

public enum RekordboxMappingMode: String, Codable, CaseIterable, Identifiable, Sendable {
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
        let pioneerURL = homeDirectory
            .appendingPathComponent("Library/Application Support/Pioneer")
        baseURL = Self.rekordboxDirectory(in: pioneerURL)
            ?? pioneerURL.appendingPathComponent("rekordbox6")
    }

    public func load(mode: RekordboxMappingMode) throws -> LoadedRekordboxKeyMapping {
        let mappings = try availableMappings()
        let settings = try loadSettingsIfPresent()
        let selectedID = settings?.keyMappingID(for: mode)
        let configured = selectedID.flatMap { id in mappings.first { $0.id == id } }
        let selected = if let configured, !configured.mapping.entries.isEmpty {
            configured
        } else {
            Self.originalMapping(for: mode, in: mappings) ?? configured
        }

        guard let selected else {
            throw RekordboxKeyMappingLoaderError.mappingNotFound(mode: mode, selectedID: selectedID)
        }
        return LoadedRekordboxKeyMapping(
            mode: mode,
            mappingID: selected.id,
            url: selected.url,
            mapping: selected.mapping
        )
    }

    private func loadSettingsIfPresent() throws -> RekordboxSettings? {
        let candidates = try FileManager.default.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: nil
        )
        let settingsURL = candidates
            .filter { $0.pathExtension == "settings" && !$0.lastPathComponent.contains("backup") }
            .sorted { lhs, rhs in
                let lhsPreferred = lhs.lastPathComponent == "rekordbox3.settings"
                let rhsPreferred = rhs.lastPathComponent == "rekordbox3.settings"
                if lhsPreferred != rhsPreferred { return lhsPreferred }
                return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
            .first
        guard let settingsURL else { return nil }
        return try RekordboxSettings.parse(data: Data(contentsOf: settingsURL))
    }

    private func availableMappings() throws -> [MappingFile] {
        let mappingsURL = baseURL.appendingPathComponent("KeyMappings")
        guard FileManager.default.fileExists(atPath: mappingsURL.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: mappingsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return try urls
            .filter {
                $0.pathExtension.lowercased() == "mappings"
                    && $0.lastPathComponent.lowercased().hasPrefix("rekordbox_")
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                MappingFile(
                    id: Self.mappingID(from: url),
                    url: url,
                    mapping: try RekordboxKeyMapping.parse(data: Data(contentsOf: url))
                )
            }
    }

    private static func originalMapping(
        for mode: RekordboxMappingMode,
        in mappings: [MappingFile]
    ) -> MappingFile? {
        let originalID: String
        let originalName: String
        switch mode {
        case .performance:
            originalID = "0000000000000"
            originalName = "Performance 1 (Preset)"
        case .export:
            originalID = "0000000000030"
            originalName = "Export (Preset)"
        }

        return mappings.first { $0.id == originalID }
            ?? mappings.first {
                $0.mapping.name.localizedCaseInsensitiveCompare(originalName) == .orderedSame
            }
            ?? mappings
                .filter { $0.mapping.name.localizedCaseInsensitiveContains(mode.rawValue) }
                .sorted {
                    $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent)
                        == .orderedAscending
                }
                .first
    }

    private static func mappingID(from url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .split(separator: "_").last.map(String.init) ?? url.deletingPathExtension().lastPathComponent
    }

    private static func rekordboxDirectory(in pioneerURL: URL) -> URL? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: pioneerURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return urls
            .filter {
                $0.lastPathComponent.lowercased().hasPrefix("rekordbox")
                    && FileManager.default.fileExists(atPath: $0.appendingPathComponent("KeyMappings").path)
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            .first
    }

    private struct MappingFile {
        let id: String
        let url: URL
        let mapping: RekordboxKeyMapping
    }
}

public enum RekordboxKeyMappingLoaderError: Error, LocalizedError {
    case selectedPerformanceMappingNotFound
    case mappingNotFound(mode: RekordboxMappingMode, selectedID: String?)

    public var errorDescription: String? {
        switch self {
        case .selectedPerformanceMappingNotFound:
            "選択中のPERFORMANCEキーマッピングをrekordbox設定から取得できませんでした。"
        case let .mappingNotFound(mode, selectedID):
            if let selectedID {
                "rekordbox設定が参照する\(mode.displayName)キーマッピング（ID: \(selectedID)）が見つかりません。"
            } else {
                "\(mode.displayName)キーマッピングをrekordboxのKeyMappingsから検出できませんでした。"
            }
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
    public let exportKeyMappingID: String?

    public init(performanceKeyMappingID: String?, exportKeyMappingID: String? = nil) {
        self.performanceKeyMappingID = performanceKeyMappingID
        self.exportKeyMappingID = exportKeyMappingID
    }

    public func keyMappingID(for mode: RekordboxMappingMode) -> String? {
        switch mode {
        case .performance: performanceKeyMappingID
        case .export: exportKeyMappingID
        }
    }

    public static func parse(data: Data) throws -> RekordboxSettings {
        let delegate = SettingsXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw parser.parserError ?? RekordboxKeyMappingError.invalidXML
        }
        return RekordboxSettings(
            performanceKeyMappingID: delegate.performanceKeyMappingID,
            exportKeyMappingID: delegate.exportKeyMappingID
        )
    }
}

private final class SettingsXMLDelegate: NSObject, XMLParserDelegate {
    var performanceKeyMappingID: String?
    var exportKeyMappingID: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "VALUE",
              let name = attributeDict["name"]?.lowercased(),
              name.contains("keymapping"),
              let value = attributeDict["val"],
              !value.isEmpty
        else { return }

        if name.contains("performace") || name.contains("performance") {
            performanceKeyMappingID = value
        } else if name.contains("export") {
            exportKeyMappingID = value
        }
    }
}
