import Foundation
import Darwin

/// Separate from CodexBar's own settings. Provider credentials never enter shared app-group snapshots.
public struct ProviderEngineSettings: Codable, Equatable, Sendable {
    public var source = "auto"
    public var apiKey = ""
    public var cookieHeader = ""
    public var automaticCookies = false
    public var region = ""
    public var enterpriseHost = ""
    public var workspaceID = ""
    public init() {}
}
public enum ProviderEngineConfiguration {
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/QuotaClock/ProviderEngine")
    }
    public static func url(_ provider: String, root: URL = directory) throws -> URL {
        guard ProviderEngineCatalog.all.contains(where: { $0.id == provider }) else { throw ProviderFetchError.invalidResponse }
        return root.appendingPathComponent(provider, isDirectory: true).appendingPathComponent("config.json")
    }
    public static func load(_ provider: String, root: URL = directory) throws -> ProviderEngineSettings {
        let file = try url(provider, root: root)
        guard FileManager.default.fileExists(atPath: file.path) else { return .init() }
        let data = try Data(contentsOf: file)
        guard data.count <= 262_144, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["providers"] as? [[String: Any]], rows.count == 1,
              let row = rows.first, row["id"] as? String == provider else { throw ProviderFetchError.invalidResponse }
        var settings = ProviderEngineSettings()
        settings.source = row["source"] as? String ?? "auto"
        settings.apiKey = row["apiKey"] as? String ?? ""
        settings.cookieHeader = row["cookieHeader"] as? String ?? ""
        settings.automaticCookies = row["cookieSource"] as? String == "auto"
        settings.region = row["region"] as? String ?? ""
        settings.enterpriseHost = row["enterpriseHost"] as? String ?? ""
        settings.workspaceID = row["workspaceID"] as? String ?? ""
        return settings
    }
    public static func save(_ settings: ProviderEngineSettings, provider: String, root: URL = directory) throws {
        guard let definition = ProviderEngineCatalog.all.first(where: { $0.id == provider }), definition.sources.contains(settings.source) else { throw ProviderFetchError.invalidResponse }
        let file = try url(provider, root: root)
        let parent = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lockFD = open(file.path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lockFD >= 0 else { throw ProviderFetchError.unavailable }
        defer { close(lockFD) }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { throw ProviderFetchError.unavailable }
        defer { flock(lockFD, LOCK_UN) }
        var row: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: file.path) {
            _ = try load(provider, root: root)
            let existing = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
            row = (existing?["providers"] as? [[String: Any]])?.first ?? [:]
        }
        row["id"] = provider; row["enabled"] = true; row["source"] = settings.source
        row["cookieSource"] = settings.automaticCookies ? "auto" : settings.cookieHeader.isEmpty ? "off" : "manual"
        for (key, value) in [("apiKey", settings.apiKey), ("cookieHeader", settings.cookieHeader), ("region", settings.region),
                             ("enterpriseHost", settings.enterpriseHost), ("workspaceID", settings.workspaceID)] {
            row[key] = value.isEmpty ? nil : value
        }
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "providers": [row]], options: [.prettyPrinted, .sortedKeys])
        guard data.count <= 262_144 else { throw ProviderFetchError.invalidResponse }
        // Private staging prevents a readable temporary file during atomic replacement.
        let staging = parent.appendingPathComponent(UUID().uuidString + ".tmp")
        guard FileManager.default.createFile(atPath: staging.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw ProviderFetchError.unavailable }
        defer { try? FileManager.default.removeItem(at: staging) }
        if FileManager.default.fileExists(atPath: file.path) { _ = try FileManager.default.replaceItemAt(file, withItemAt: staging) }
        else { try FileManager.default.moveItem(at: staging, to: file) }
    }
    public static func ensure(_ provider: String) throws -> URL {
        let file = try url(provider)
        if !FileManager.default.fileExists(atPath: file.path) { try save(.init(), provider: provider) }
        _ = try load(provider)
        return file
    }
}
