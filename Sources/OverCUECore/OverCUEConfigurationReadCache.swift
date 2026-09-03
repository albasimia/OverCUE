import Foundation

/// Read-only cache for frequent runtime status consumers. Disk remains the
/// authority: even without a notification, atomic replacement invalidates it.
/// This is not a baseline for editing or a replacement for locked writes.
public struct OverCUEConfigurationReadCache {
    private var cached: (url: URL, revision: OverCUEConfigurationFileRevision,
                         configuration: OverCUEConfiguration)?

    public init() {}

    public mutating func invalidate() { cached = nil }

    public mutating func read(at url: URL) throws -> OverCUEConfiguration {
        // lstat-based revisions must describe the target, not an unchanged
        // symlink whose destination was atomically replaced.
        let url = url.resolvingSymlinksInPath()
        do {
            let before = try OverCUEConfigurationFileStore.revision(at: url)
            if let cached, cached.url == url, cached.revision == before {
                return cached.configuration
            }
            let configuration = try OverCUEConfigurationFileStore.readCurrent(at: url)
            let after = try OverCUEConfigurationFileStore.revision(at: url)
            // A writer may replace the file between read and stat. Never tag
            // the old contents with the new revision; read again on next use.
            cached = before == after ? (url, after, configuration) : nil
            return configuration
        } catch {
            cached = nil
            throw error // Do not silently use stale data on invalid/missing config.
        }
    }
}
