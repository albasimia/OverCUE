/// Immutable metadata for one live HID interface. Cookies never leave runtime memory.
public struct GenericHIDElementCatalog: Sendable {
    public struct Element: Sendable {
        public let cookie: UInt64
        public let input: GenericHIDInputDescriptor
        public let isRelative: Bool

        public init(cookie: UInt64, input: GenericHIDInputDescriptor, isRelative: Bool) {
            self.cookie = cookie
            self.input = input
            self.isRelative = isRelative
        }
    }

    public let elementsByCookie: [UInt64: GenericHIDRuntimeElementDescriptor]

    /// Supply the complete interface enumeration, not just mapped/input elements:
    /// descriptor ambiguity has the same scope as the original matching scan.
    public init(elements: [Element]) {
        var descriptorCounts: [GenericHIDInputDescriptor: Int] = [:]
        var cookieCounts: [UInt64: Int] = [:]
        for element in elements {
            descriptorCounts[element.input, default: 0] += 1
            cookieCounts[element.cookie, default: 0] += 1
        }
        var metadata: [UInt64: GenericHIDRuntimeElementDescriptor] = [:]
        for element in elements where cookieCounts[element.cookie] == 1 {
            metadata[element.cookie] = GenericHIDRuntimeElementDescriptor(
                input: element.input,
                cookie: element.cookie,
                isRelative: element.isRelative,
                matchingElementCount: descriptorCounts[element.input]
            )
        }
        // An unexpected duplicate cookie is not a safe lookup key: omit it.
        elementsByCookie = metadata
    }
}

/// Owner-serialized storage. Preload is a lifecycle operation; lookup cannot load
/// or retry. A failed enumeration is fail-closed until the next explicit preload.
public struct GenericHIDElementCatalogStore: Sendable {
    private var catalogs: [UInt: GenericHIDElementCatalog] = [:]

    public init() {}

    public func isReady(interfaceID: UInt) -> Bool { catalogs[interfaceID] != nil }

    @discardableResult
    public mutating func preload(
        interfaceID: UInt,
        enumerate: () -> [GenericHIDElementCatalog.Element]?
    ) -> Bool {
        if isReady(interfaceID: interfaceID) { return true }
        guard let elements = enumerate(), !elements.isEmpty else { return false }
        catalogs[interfaceID] = GenericHIDElementCatalog(elements: elements)
        return true
    }

    public func element(interfaceID: UInt, cookie: UInt64) -> GenericHIDRuntimeElementDescriptor? {
        catalogs[interfaceID]?.elementsByCookie[cookie]
    }

    public mutating func remove(interfaceID: UInt) { catalogs.removeValue(forKey: interfaceID) }
    public mutating func removeAll() { catalogs.removeAll() }
}
