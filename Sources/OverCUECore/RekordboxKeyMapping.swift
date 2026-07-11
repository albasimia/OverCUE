import Foundation

public struct RekordboxKeyMapping: Equatable, Sendable {
    public let name: String
    public let shortcutsByCommandID: [String: String]

    public init(name: String, shortcutsByCommandID: [String: String]) {
        self.name = name
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
            shortcutsByCommandID: delegate.shortcutsByCommandID
        )
    }
}

public enum RekordboxKeyMappingError: Error {
    case invalidXML
}

private final class MappingXMLDelegate: NSObject, XMLParserDelegate {
    var mappingName: String?
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
            shortcutsByCommandID[commandID] = key
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
