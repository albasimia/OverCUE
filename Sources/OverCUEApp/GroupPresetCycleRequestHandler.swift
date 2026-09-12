import Foundation
import OverCUECore

private final class GroupPresetCycleObserverToken: @unchecked Sendable {
    let value: any NSObjectProtocol

    init(_ value: any NSObjectProtocol) {
        self.value = value
    }
}

/// Owns hardware-triggered Group Preset cycling. The legacy `cycle_group`
/// actions are converted into a distributed request in OverCUECore, while the
/// app remains the single writer of activeGroupPresetID. Existing configuration
/// notifications then hot-apply the new baseline to every included device.
@MainActor
enum GroupPresetCycleRequestHandler {
    private static var observer: GroupPresetCycleObserverToken?

    static func install() {
        guard observer == nil else { return }
        observer = GroupPresetCycleObserverToken(
            DistributedNotificationCenter.default().addObserver(
                forName: OverCUEGroupPresetCycleRequestNotification.name,
                object: nil,
                queue: .main
            ) { notification in
                guard let step = notification.userInfo?[
                    OverCUEGroupPresetCycleRequestNotification.stepKey
                ] as? Int,
                      step != 0
                else { return }
                Task { @MainActor in
                    await cycle(step: step)
                }
            }
        )
    }

    private static func cycle(step: Int) async {
        let direction = step < 0 ? -1 : 1
        let url = OverCUEAppConfigurationLocation.url
        let span = OverCUEPerformanceSpan("group preset cycle")
        do {
            let (_, changed) = try await OverCUEPersistenceWorker.run {
                var changed = false
                let saved = try OverCUEConfigurationFileStore.updateCurrent(
                    at: url,
                    fallback: .defaultValue
                ) { latest in
                    let presets = latest.orderedGroupPresets
                    guard !presets.isEmpty else { return }

                    let nextID: String
                    if let activeID = latest.activeGroupPresetID,
                       let currentIndex = presets.firstIndex(where: { $0.id == activeID }) {
                        let offset = ((currentIndex + direction) % presets.count + presets.count)
                            % presets.count
                        nextID = presets[offset].id
                    } else {
                        nextID = direction < 0 ? presets.last!.id : presets.first!.id
                    }

                    changed = latest.activeGroupPresetID != nextID
                    latest.activeGroupPresetID = nextID
                }
                span.mark("config saved")
                return (saved, changed)
            }
            guard changed else {
                span.mark("operation end")
                return
            }
            OverCUEConfigurationChangedNotification.post()
            span.mark("operation end")
        } catch {
            NSLog("OverCUE Group Preset cycle failed: %@", error.localizedDescription)
            span.mark("operation failed")
        }
    }
}
