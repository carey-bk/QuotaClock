import Foundation

public enum LocalTokenScope: String, Codable, Sendable {
    case claudeCLI, claudeDesktop
}
public enum LocalTokenStatus: String, Codable, Sendable {
    case available, noRecords, incomplete
}

/// Claude Code JSONL accounting, following CodexBar's cache-inclusive token and
/// message/request deduplication semantics. Only numeric usage metadata is retained.
/// This is machine-local Code history, never subscription-wide or ordinary chat usage.
public actor ClaudeLocalUsage {
    public static let shared = ClaudeLocalUsage()
    struct Row: Sendable {
        var key: String
        var session: String
        var date: Date
        var tokens: Int64
        var incomplete: Bool
        var sidechain: Bool
        var desktop: Bool
        var subagent: Bool
        var path: String
    }
    private struct CachedFile {
        var size: Int
        var modified: Date
        var rows: [Row]
    }
    private var files: [String: CachedFile] = [:]
    private var memo: [LocalTokenScope: UsageStatistics] = [:]
    private var memoDate: Date?
    private var memoHome: URL?
    private var memoZone: String?
    private enum ScanError: Error { case limit, malformed }
    private static let skipped: Set<String> = ["node_modules", ".git", ".build", "build", "DerivedData", "outputs", "target", "worktrees"]

    public init() {}

    public func statistics(scope: LocalTokenScope, at date: Date, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           calendar: Calendar = .current, force: Bool = false) -> UsageStatistics {
        if !force, memoHome == home, memoZone == calendar.timeZone.identifier, let previous = memoDate,
           date.timeIntervalSince(previous) >= 0, date.timeIntervalSince(previous) < 60,
           calendar.isDate(date, inSameDayAs: previous), let cached = memo[scope] { return cached }
        do {
            let rows = try scan(home: home)
            for source in [LocalTokenScope.claudeCLI, .claudeDesktop] {
                memo[source] = try Self.aggregate(rows: rows, scope: source, at: date, calendar: calendar)
            }
        } catch {
            // A bounded/failed scan must not masquerade as a complete zero or partial total.
            for source in [LocalTokenScope.claudeCLI, .claudeDesktop] {
                memo[source] = UsageStatistics(localScope: source, localStatus: .incomplete)
            }
        }
        memoDate = date; memoHome = home; memoZone = calendar.timeZone.identifier
        return memo[scope]!
    }

    private func scan(home: URL) throws -> [Row] {
        let fm = FileManager.default
        let start = ProcessInfo.processInfo.systemUptime
        var visited = 0
        func children(_ directory: URL) throws -> [URL] {
            guard fm.fileExists(atPath: directory.path) else { return [] }
            let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { return [] }
            let entries = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
            visited += entries.count
            guard visited <= 20_000, ProcessInfo.processInfo.systemUptime - start < 8 else { throw ScanError.limit }
            return entries.sorted { $0.path < $1.path }
        }
        var roots: [(URL, Bool)] = [
            (home.appendingPathComponent(".claude/projects"), false),
            (home.appendingPathComponent(".config/claude/projects"), false)
        ]
        let desktop = home.appendingPathComponent("Library/Application Support/Claude")
        var queue = ["claude-code-sessions", "local-agent-mode-sessions"].map { (desktop.appendingPathComponent($0), 0) }
        var sessionIDs = Set<String>()
        var metadataBytes = 0
        func linkedSessions(_ object: Any, depth: Int = 0) {
            guard depth < 8 else { return }
            if let dict = object as? [String: Any] {
                if let id = dict["cliSessionId"] as? String, !id.isEmpty { sessionIDs.insert(id) }
                for value in dict.values { linkedSessions(value, depth: depth + 1) }
            } else if let array = object as? [Any] {
                for value in array { linkedSessions(value, depth: depth + 1) }
            }
        }
        while !queue.isEmpty {
            let (dir, depth) = queue.removeFirst()
            let embedded = dir.appendingPathComponent(".claude/projects")
            if fm.fileExists(atPath: embedded.path) { roots.append((embedded, true)) }
            for item in try children(dir) {
                let info = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                guard info.isSymbolicLink != true, !Self.skipped.contains(item.lastPathComponent) else { continue }
                if info.isDirectory == true {
                    if depth < 4, !item.lastPathComponent.hasPrefix(".") { queue.append((item, depth + 1)) }
                } else if item.pathExtension == "json" {
                    guard let size = info.fileSize, size <= 2_000_000 else { throw ScanError.limit }
                    metadataBytes += size
                    guard metadataBytes <= 16_000_000 else { throw ScanError.limit }
                    let data = try Data(contentsOf: item)
                    if let object = try? JSONSerialization.jsonObject(with: data) { linkedSessions(object) }
                    else { throw ScanError.malformed }
                }
            }
        }
        var pending = roots.map { ($0.0, $0.1, 0) }
        var found: [(URL, Bool)] = []
        var seen = Set<String>()
        while !pending.isEmpty {
            let (dir, isDesktop, depth) = pending.removeFirst()
            guard seen.insert(dir.standardizedFileURL.path).inserted else { continue }
            for item in try children(dir) {
                let info = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard info.isSymbolicLink != true else { continue }
                if info.isDirectory == true {
                    guard !Self.skipped.contains(item.lastPathComponent) else { continue }
                    guard depth < 6 else { throw ScanError.limit }
                    pending.append((item, isDesktop, depth + 1))
                } else if item.pathExtension == "jsonl" { found.append((item, isDesktop)) }
            }
        }
        var output: [Row] = [], active = Set<String>(), readBytes = 0
        for (url, isDesktop) in found.sorted(by: { $0.0.path < $1.0.path }) {
            let info = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard let size = info.fileSize, let modified = info.contentModificationDate, size <= 32_000_000 else { throw ScanError.limit }
            active.insert(url.path)
            let rows: [Row]
            if let cached = files[url.path], cached.size == size, cached.modified == modified { rows = cached.rows }
            else {
                readBytes += size
                guard readBytes <= 256_000_000, ProcessInfo.processInfo.systemUptime - start < 8 else { throw ScanError.limit }
                let data = try Data(contentsOf: url)
                rows = try Self.parse(data, path: url.path, desktop: isDesktop)
                files[url.path] = CachedFile(size: size, modified: modified, rows: rows)
            }
            output.append(contentsOf: rows.map { row in
                var row = row
                row.desktop = isDesktop || sessionIDs.contains(row.session) || sessionIDs.contains(url.deletingPathExtension().lastPathComponent) || url.pathComponents.contains(where: sessionIDs.contains)
                return row
            })
            guard output.count <= 200_000 else { throw ScanError.limit }
        }
        files = files.filter { active.contains($0.key) }
        return output
    }

    static func parse(_ data: Data, path: String, desktop: Bool) throws -> [Row] {
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        var rows: [Row] = []
        let lines = data.split(separator: 10, omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() where !line.isEmpty {
            guard line.count <= 2_000_000 else { throw ScanError.limit }
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                if index == lines.count - 1 { continue } // in-flight append; retry on next file change
                throw ScanError.malformed
            }
            guard object["type"] as? String == "assistant", let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let text = object["timestamp"] as? String, let date = fractional.date(from: text) ?? plain.date(from: text) else { continue }
            var total: Int64 = 0
            for key in ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"] {
                guard let value = usage[key] else { continue }
                guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
                      n.doubleValue >= 0, n.doubleValue.rounded() == n.doubleValue, n.doubleValue < Double(Int64.max) else { throw ScanError.malformed }
                let (sum, overflow) = total.addingReportingOverflow(n.int64Value)
                guard !overflow else { throw ScanError.limit }; total = sum
            }
            guard total > 0 else { continue }
            let session = object["sessionId"] as? String ?? object["session_id"] as? String ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let messageID = message["id"] as? String
            let requestID = object["requestId"] as? String
            let key: String
            if let messageID, !messageID.isEmpty { key = "m:\(messageID)|r:\(requestID ?? "session:" + session)" }
            else { key = "file:\(path):\(index)" }
            let incomplete = message["stop_reason"] is NSNull && (usage["input_tokens"] as? NSNumber)?.int64Value ?? 0 > 0 && (usage["output_tokens"] as? NSNumber)?.int64Value ?? 0 == 0 && usage["cache_read_input_tokens"] == nil && usage["cache_creation_input_tokens"] == nil
            rows.append(Row(key: key, session: session, date: date, tokens: total, incomplete: incomplete,
                            sidechain: object["isSidechain"] as? Bool ?? false, desktop: desktop,
                            subagent: path.contains("/subagents/"), path: path))
        }
        return rows
    }

    static func aggregate(rows: [Row], scope: LocalTokenScope, at now: Date, calendar: Calendar) throws -> UsageStatistics {
        var winners: [String: Row] = [:]
        for row in rows where row.date <= now {
            if let old = winners[row.key] {
                // Prefer complete, parent copies; within one file use the final cumulative chunk.
                let replace: Bool
                if old.incomplete != row.incomplete { replace = !row.incomplete }
                else if old.sidechain != row.sidechain { replace = !row.sidechain }
                else if old.subagent != row.subagent { replace = !row.subagent }
                else { replace = old.path == row.path || row.path < old.path }
                var winner = replace ? row : old
                winner.desktop = old.desktop || row.desktop
                winners[row.key] = winner
            } else { winners[row.key] = row }
        }
        var daily: [Date: Int64] = [:], total: Int64 = 0
        for row in winners.values where !row.incomplete && row.desktop == (scope == .claudeDesktop) {
            let day = calendar.startOfDay(for: row.date)
            let (sum, overflow) = total.addingReportingOverflow(row.tokens)
            let (daySum, dayOverflow) = (daily[day] ?? 0).addingReportingOverflow(row.tokens)
            guard !overflow, !dayOverflow else { throw ScanError.limit }
            total = sum; daily[day] = daySum
        }
        guard !daily.isEmpty else { return UsageStatistics(localScope: scope, localStatus: .noRecords) }
        let today = calendar.startOfDay(for: now)
        // Last seven completed local calendar days, matching LAST DAY = yesterday.
        let history = (1...7).reversed().map { offset -> UsageDay in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
            return UsageDay(date: utc.date(from: parts)!, tokens: daily[day] ?? 0)
        }
        return UsageStatistics(totalTokens: total, peakDailyTokens: daily.values.max(), lastDailyTokens: history.last?.tokens,
                               dailyHistory: history, localScope: scope, localStatus: .available)
    }
}
