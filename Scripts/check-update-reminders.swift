import AppKit
import Combine
import QuotaCore
import Sparkle

/// Disposable bundle only. Exercises the shipping updater's reminder state without downloads.
@main struct UpdateReminderProbe {
    @MainActor static func main() {
        _ = NSApplication.shared
        let mode = CommandLine.arguments.last!
        let defaults = UserDefaults.standard
        defaults.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        if mode == "opt-out" { defaults.set(false, forKey: "SUEnableAutomaticChecks") }
        if mode == "cached" { defaults.set("v2.0.0", forKey: "updater.availableVersion") }
        if mode == "installed" { defaults.set("v1.3.0", forKey: "updater.availableVersion") }
        let subject = AppUpdater.shared
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(subject.automaticallyChecks == (mode != "opt-out"))
        precondition(subject.hasAvailableUpdate == (mode == "cached"))
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        let item = SUAppcastItem(dictionary: ["title": "2.0.0", "sparkle:version": "100", "sparkle:shortVersionString": "2.0.0", "enclosure": ["url": "https://example.invalid/update.zip", "length": "100", "type": "application/octet-stream"]])!
        subject.updater(controller.updater, didFindValidUpdate: item)
        precondition(subject.availableVersion == "v2.0.0")
        precondition(defaults.string(forKey: "updater.availableVersion") == "v2.0.0")
        // A failed background cycle keeps the known update and never invokes a manual alert.
        subject.updater(controller.updater, didFinishUpdateCycleFor: .updates, error: NSError(domain: NSURLErrorDomain, code: -1009))
        precondition(subject.hasAvailableUpdate)
        subject.updaterDidNotFindUpdate(controller.updater)
        precondition(!subject.hasAvailableUpdate)
        precondition(defaults.string(forKey: "updater.availableVersion") == nil)
        defaults.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        print("PASS \(mode): defaults, discovery, persisted reminder, offline retention, current-version clearing")
    }
}
