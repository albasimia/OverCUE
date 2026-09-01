import Darwin
import Foundation

@_silgen_name("flock")
private func overcueFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

public enum OverCUEConfigurationPersistenceError: Error, LocalizedError, Sendable {
    case missingConfiguration(String)
    case unsupportedVersion(Int)
    case lockOpenFailed(path: String, code: Int32)
    case lockFailed(path: String, code: Int32)
    case revisionReadFailed(path: String, code: Int32)

    public var errorDescription: String? {
        switch self {
        case let .missingConfiguration(path):
            return "Configuration file does not exist at \(path)."
        case let .unsupportedVersion(version):
            return "Unsupported configuration version \(version)."
        case let .lockOpenFailed(path, code):
            return "Could not open configuration lock at \(path) (errno \(code))."
        case let .lockFailed(path, code):
            return "Could not lock configuration at \(path) (errno \(code))."
        case let .revisionReadFailed(path, code):
            return "Could not read configuration revision at \(path) (errno \(code))."
        }
    }
}

public struct OverCUEConfigurationFileRevision: Equatable, Sendable {
    public let inode: UInt64
    public let size: Int64
    public let modificationSeconds: Int64
    public let modificationNanoseconds: Int64

    public init(
        inode: UInt64,
        size: Int64,
        modificationSeconds: Int64,
        modificationNanoseconds: Int64
    ) {
        self.inode = inode
        self.size = size
        self.modificationSeconds = modificationSeconds
        self.modificationNanoseconds = modificationNanoseconds
    }
}

public enum OverCUEConfigurationFileStore {
    public struct Snapshot: Equatable, Sendable {
        public let configuration: OverCUEConfiguration
        public let revision: OverCUEConfigurationFileRevision

        public init(
            configuration: OverCUEConfiguration,
            revision: OverCUEConfigurationFileRevision
        ) {
            self.configuration = configuration
            self.revision = revision
        }
    }

    public struct MigrationResult: Sendable {
        public let configuration: OverCUEConfiguration
        public let originalData: Data?
        public let sourceVersion: Int?
    }

    private struct VersionEnvelope: Decodable {
        let version: Int
    }

    public static func readCurrent(at url: URL) throws -> OverCUEConfiguration {
        let data = try Data(contentsOf: url)
        let configuration = try JSONDecoder().decode(OverCUEConfiguration.self, from: data)
        guard configuration.version == OverCUEConfiguration.currentVersion else {
            throw OverCUEConfigurationPersistenceError.unsupportedVersion(configuration.version)
        }
        return configuration
    }

    public static func revision(at url: URL) throws -> OverCUEConfigurationFileRevision {
        try revisionUnlocked(at: url)
    }

    public static func readCurrentSnapshot(at url: URL) throws -> Snapshot {
        try withExclusiveLock(for: url) {
            Snapshot(
                configuration: try readCurrent(at: url),
                revision: try revisionUnlocked(at: url)
            )
        }
    }

    private static func revisionUnlocked(at url: URL) throws -> OverCUEConfigurationFileRevision {
        var information = stat()
        guard Darwin.lstat(url.path, &information) == 0 else {
            throw OverCUEConfigurationPersistenceError.revisionReadFailed(
                path: url.path,
                code: errno
            )
        }
        return OverCUEConfigurationFileRevision(
            inode: UInt64(information.st_ino),
            size: Int64(information.st_size),
            modificationSeconds: Int64(information.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(information.st_mtimespec.tv_nsec)
        )
    }

    public static func writeCurrent(_ configuration: OverCUEConfiguration, at url: URL) throws {
        try withExclusiveLock(for: url) {
            try writeUnlocked(configuration, to: url)
        }
    }

    public static func migrateCurrentIfNeeded(
        at url: URL,
        migrate: (_ latestData: Data, _ sourceVersion: Int) throws -> OverCUEConfiguration
    ) throws -> MigrationResult {
        try withExclusiveLock(for: url) {
            let data = try Data(contentsOf: url)
            let version = try JSONDecoder().decode(VersionEnvelope.self, from: data).version
            if version == OverCUEConfiguration.currentVersion {
                return MigrationResult(
                    configuration: try JSONDecoder().decode(OverCUEConfiguration.self, from: data),
                    originalData: nil,
                    sourceVersion: nil
                )
            }
            guard version < OverCUEConfiguration.currentVersion else {
                throw OverCUEConfigurationPersistenceError.unsupportedVersion(version)
            }
            let configuration = try migrate(data, version)
            let backupURL = url.deletingLastPathComponent()
                .appendingPathComponent("config.v\(version).backup.json")
            if !FileManager.default.fileExists(atPath: backupURL.path) {
                try data.write(to: backupURL, options: .atomic)
            }
            try writeUnlocked(configuration, to: url)
            return MigrationResult(
                configuration: configuration,
                originalData: data,
                sourceVersion: version
            )
        }
    }

    @discardableResult
    public static func updateCurrent(
        at url: URL,
        fallback: OverCUEConfiguration? = nil,
        _ update: (inout OverCUEConfiguration) throws -> Void
    ) throws -> OverCUEConfiguration {
        try withExclusiveLock(for: url) {
            var configuration: OverCUEConfiguration
            if FileManager.default.fileExists(atPath: url.path) {
                configuration = try readCurrent(at: url)
            } else if let fallback {
                configuration = fallback
            } else {
                throw OverCUEConfigurationPersistenceError.missingConfiguration(url.path)
            }

            try update(&configuration)
            try writeUnlocked(configuration, to: url)
            return configuration
        }
    }

    private static func writeUnlocked(_ configuration: OverCUEConfiguration, to url: URL) throws {
        guard configuration.version == OverCUEConfiguration.currentVersion else {
            throw OverCUEConfigurationPersistenceError.unsupportedVersion(configuration.version)
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: url, options: .atomic)
    }

    private static func withExclusiveLock<Result>(
        for configurationURL: URL,
        _ operation: () throws -> Result
    ) throws -> Result {
        let directory = configurationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = configurationURL.appendingPathExtension("lock")
        let descriptor = Darwin.open(
            lockURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw OverCUEConfigurationPersistenceError.lockOpenFailed(
                path: lockURL.path,
                code: errno
            )
        }
        defer { Darwin.close(descriptor) }

        while overcueFlock(descriptor, LOCK_EX) != 0 {
            let code = errno
            if code == EINTR { continue }
            throw OverCUEConfigurationPersistenceError.lockFailed(path: lockURL.path, code: code)
        }
        defer {
            while overcueFlock(descriptor, LOCK_UN) != 0, errno == EINTR {}
        }
        return try operation()
    }
}

public enum OverCUEConfigurationMerger {
    public static func merge(
        base: OverCUEConfiguration,
        local: OverCUEConfiguration,
        remote: OverCUEConfiguration
    ) -> OverCUEConfiguration {
        var result = remote
        if local.version != base.version {
            result.version = local.version
        }
        if local.defaultProfile != base.defaultProfile {
            result.defaultProfile = local.defaultProfile
        }
        result.profiles = mergeProfiles(
            base: base.profiles,
            local: local.profiles,
            remote: remote.profiles
        )
        result.deviceProfiles = mergeSimpleDictionary(
            base: base.deviceProfiles,
            local: local.deviceProfiles,
            remote: remote.deviceProfiles
        )
        result.logicalDevices = mergeSimpleDictionary(
            base: base.logicalDevices,
            local: local.logicalDevices,
            remote: remote.logicalDevices
        )
        if local.physicalDeviceBindings != base.physicalDeviceBindings {
            result.physicalDeviceBindings = local.physicalDeviceBindings
        }
        return result
    }

    private static func mergeProfiles(
        base: [String: OverCUEProfile],
        local: [String: OverCUEProfile],
        remote: [String: OverCUEProfile]
    ) -> [String: OverCUEProfile] {
        var result = remote
        let keys = Set(base.keys).union(local.keys)
        for key in keys {
            let baseValue = base[key]
            let localValue = local[key]
            guard localValue != baseValue else { continue }
            guard let localValue else {
                result.removeValue(forKey: key)
                continue
            }
            guard let baseValue, let remoteValue = remote[key] else {
                result[key] = localValue
                continue
            }
            result[key] = mergeProfile(base: baseValue, local: localValue, remote: remoteValue)
        }
        return result
    }

    private static func mergeProfile(
        base: OverCUEProfile,
        local: OverCUEProfile,
        remote: OverCUEProfile
    ) -> OverCUEProfile {
        var result = remote
        if local.waveformPosition != base.waveformPosition {
            result.waveformPosition = local.waveformPosition
        }
        result.presetGroups = mergePresetGroups(
            base: base.presetGroups,
            local: local.presetGroups,
            remote: remote.presetGroups
        )
        return result
    }

    private static func mergePresetGroups(
        base: [OverCUEPresetGroup],
        local: [OverCUEPresetGroup],
        remote: [OverCUEPresetGroup]
    ) -> [OverCUEPresetGroup] {
        let baseByID = Dictionary(uniqueKeysWithValues: base.map { ($0.id, $0) })
        let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        var resultByID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        for key in Set(baseByID.keys).union(localByID.keys) {
            let baseValue = baseByID[key]
            let localValue = localByID[key]
            guard localValue != baseValue else { continue }
            guard let localValue else {
                resultByID.removeValue(forKey: key)
                continue
            }
            guard let baseValue, let remoteValue = resultByID[key] else {
                resultByID[key] = localValue
                continue
            }
            var merged = remoteValue
            if localValue.name != baseValue.name { merged.name = localValue.name }
            if localValue.order != baseValue.order { merged.order = localValue.order }
            merged.mapping = mergeGroupMapping(
                base: baseValue.mapping,
                local: localValue.mapping,
                remote: remoteValue.mapping
            )
            resultByID[key] = merged
        }
        return resultByID.values.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id < $1.id
        }
    }

    private static func mergeGroupMapping(
        base: OverCUEGroupMapping,
        local: OverCUEGroupMapping,
        remote: OverCUEGroupMapping
    ) -> OverCUEGroupMapping {
        var result = remote
        if local.waveformPosition != base.waveformPosition {
            result.waveformPosition = local.waveformPosition
        }
        result.keyMap = mergeSimpleDictionary(
            base: base.keyMap,
            local: local.keyMap,
            remote: remote.keyMap
        )
        result.chordMap = mergeSimpleDictionary(
            base: base.chordMap,
            local: local.chordMap,
            remote: remote.chordMap
        )
        result.dialMap = mergeSimpleDictionary(
            base: base.dialMap,
            local: local.dialMap,
            remote: remote.dialMap
        )
        result.dialChordMap = mergeSimpleDictionary(
            base: base.dialChordMap,
            local: local.dialChordMap,
            remote: remote.dialChordMap
        )
        if local.rekordboxMode != base.rekordboxMode {
            result.rekordboxMode = local.rekordboxMode
        }
        result.legacyRekordboxDeck = nil
        return result
    }

    private static func mergeSimpleDictionary<Key: Hashable, Value: Equatable>(
        base: [Key: Value],
        local: [Key: Value],
        remote: [Key: Value]
    ) -> [Key: Value] {
        var result = remote
        let keys = Set(base.keys).union(local.keys)
        for key in keys {
            let baseValue = base[key]
            let localValue = local[key]
            guard localValue != baseValue else { continue }
            if let localValue {
                result[key] = localValue
            } else {
                result.removeValue(forKey: key)
            }
        }
        return result
    }
}

public struct OverCUEConfigurationReconciliation: Equatable, Sendable {
    public let configuration: OverCUEConfiguration
    public let persistedConfiguration: OverCUEConfiguration

    public init(
        configuration: OverCUEConfiguration,
        persistedConfiguration: OverCUEConfiguration
    ) {
        self.configuration = configuration
        self.persistedConfiguration = persistedConfiguration
    }
}

public enum OverCUEConfigurationSnapshotSynchronizer {
    public static func reconcile(
        configuration local: OverCUEConfiguration,
        persistedConfiguration baseline: OverCUEConfiguration,
        remote: OverCUEConfiguration
    ) -> OverCUEConfigurationReconciliation {
        OverCUEConfigurationReconciliation(
            configuration: OverCUEConfigurationMerger.merge(
                base: baseline,
                local: local,
                remote: remote
            ),
            persistedConfiguration: remote
        )
    }
}
