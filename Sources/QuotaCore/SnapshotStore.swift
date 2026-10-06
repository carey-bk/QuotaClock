import Foundation
import Darwin

public enum SnapshotLocations {
    public static let appGroup = "666N9BJMD7.com.quotaclock.shared"
    public static let widgetKind = "QuotaClockProviderCardV2"
    public static func shared() throws -> URL {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { throw SnapshotError.groupUnavailable }
        return container.appendingPathComponent("Library/Application Support/QuotaClock/snapshot.json")
    }
    /// Public POSIX account lookup avoids the saver host's sandbox-remapped NSHomeDirectory.
    /// This is an explicitly exported display file, NOT another app's private container.
    public static func saverExport() throws -> URL {
        guard let account = getpwuid(getuid()), let home = account.pointee.pw_dir else { throw SnapshotError.invalidData }
        return URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appendingPathComponent("Library/Application Support/QuotaClock/Display/snapshot.json")
    }
    public static func saverPreferences() throws -> URL {
        try saverExport().deletingLastPathComponent().appendingPathComponent("preferences.json")
    }
}
public struct SnapshotStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func read() throws -> QuotaSnapshot {
        let data = try Data(contentsOf: url)
        guard data.count <= 1_048_576 else { throw SnapshotError.invalidData }
        return try JSONDecoder().decode(QuotaSnapshot.self, from: data).validated()
    }
    public static func encode(_ snapshot: QuotaSnapshot) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot.validated())
    }
    public func write(_ snapshot: QuotaSnapshot) throws { try writeEncoded(Self.encode(snapshot)) }
    public func writeEncoded(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
/// One writer. The group file is canonical; export has the same logical revision.
/// The two file replacements are individually atomic, not a cross-file transaction.
public struct SnapshotPublisher {
    public let shared: SnapshotStore
    public let display: SnapshotStore
    public init(shared: SnapshotStore, display: SnapshotStore) { self.shared = shared; self.display = display }
    public func publish(_ snapshot: QuotaSnapshot) throws {
        let bytes = try SnapshotStore.encode(snapshot)
        try shared.writeEncoded(bytes)
        try display.writeEncoded(SnapshotStore.encode(snapshot.displayProjection()))
    }
    public func repairDisplay() throws { try display.writeEncoded(SnapshotStore.encode(shared.read().displayProjection())) }
}
