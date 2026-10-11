#if !ONBOARDING_PREVIEW
import Foundation
import Sparkle
#if !VERSION_POLICY_PROBE
import QuotaCore
#endif

/// Older feeds use monotonically increasing build numbers. Resolve those through
/// their display versions before comparing. The lock also covers Sparkle worker threads.
final class ReleaseVersionComparison: NSObject, SUVersionComparison {
    private let lock = NSLock()
    private var versions: [String: AppVersion] = [:]
    func load(_ items: [SUAppcastItem]) {
        lock.lock(); defer { lock.unlock() }
        versions = [:]
        for item in items { versions[item.versionString] = AppVersion(item.displayVersionString) }
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            versions[build] = AppVersion(version)
        }
    }
    func best(in appcast: SUAppcast) -> SUAppcastItem? {
        guard let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let local = AppVersion(current) else { return SUAppcastItem.empty() }
        return appcast.items.filter { item in
            guard let version = AppVersion(item.displayVersionString) else { return false }
            return version > local
        }.max { AppVersion($0.displayVersionString)! < AppVersion($1.displayVersionString)! } ?? SUAppcastItem.empty()
    }
    func compareVersion(_ a: String, toVersion b: String) -> ComparisonResult {
        lock.lock(); defer { lock.unlock() }
        guard let lhs = versions[a] ?? AppVersion(a), let rhs = versions[b] ?? AppVersion(b) else {
            return SUStandardVersionComparator.default.compareVersion(a, toVersion: b)
        }
        return lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending)
    }
}

#endif
