import Foundation

/// Snapshot-only projection; no adapters, publisher or storage.
public enum MenuPreviewProjection {
    public static func snapshot(_ current: QuotaSnapshot?, platform: PlatformPreferences) -> QuotaSnapshot? {
        guard var current else { return nil }
        current.platformPreferences = platform
        return current
    }
}
