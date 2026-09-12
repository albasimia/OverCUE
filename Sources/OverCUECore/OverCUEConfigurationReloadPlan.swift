/// Runtime refresh scope is derived from actual persisted changes, so older
/// notification senders and external configuration writers remain supported.
public struct OverCUEConfigurationReloadPlan: Equatable, Sendable {
    public let requiresHIDEnumeration: Bool

    public init(previous: OverCUEConfiguration, latest: OverCUEConfiguration) {
        requiresHIDEnumeration = previous.physicalDeviceBindings.filter { $0.kind == .genericHID }
            != latest.physicalDeviceBindings.filter { $0.kind == .genericHID }
    }
}
