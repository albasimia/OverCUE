import Foundation

public struct GenericHIDShortcutEditorScope: Equatable, Hashable, Sendable {
    public let logicalDeviceID: String
    public let presetID: String

    public init(logicalDeviceID: String, presetID: String) {
        self.logicalDeviceID = logicalDeviceID
        self.presetID = presetID
    }
}

public enum GenericHIDShortcutEditorScopeResolver {
    /// Shortcuts edits one Preset across all Generic HID Logical Devices in the
    /// selected Profile. Group Preset assignments are runtime-only inputs and
    /// intentionally do not participate in this resolution.
    public static func scopes(
        configuration: OverCUEConfiguration,
        profileName: String,
        editorPresetID: String
    ) -> [GenericHIDShortcutEditorScope] {
        let genericLogicalDeviceIDs = Set(
            configuration.physicalDeviceBindings.compactMap { binding in
                binding.kind == .genericHID ? binding.logicalDeviceID : nil
            }
        )
        return configuration.logicalDevices.compactMap { logicalDeviceID, logicalDevice in
            guard logicalDevice.profileName == profileName,
                  genericLogicalDeviceIDs.contains(logicalDeviceID)
            else { return nil }
            return GenericHIDShortcutEditorScope(
                logicalDeviceID: logicalDeviceID,
                presetID: editorPresetID
            )
        }.sorted { $0.logicalDeviceID < $1.logicalDeviceID }
    }
}
