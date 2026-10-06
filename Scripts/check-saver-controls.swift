import AppKit
import QuotaCore

@main struct CheckSaverControls {
    @MainActor static func main() {
        let domainName = "com.quotaclock.saver-test." + UUID().uuidString
        let domain = domainName as CFString
        let defaults = UserDefaults(suiteName: domainName)!
        CFPreferencesSetValue("idleTime" as CFString, NSNumber(value: 1800), domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        precondition(CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost))
        defer {
            CFPreferencesSetValue("idleTime" as CFString, nil, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
            CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
            defaults.removePersistentDomain(forName: domainName)
        }
        let controller = ScreenSaverSystemController(domain: domainName, defaults: defaults)
        precondition(controller.autoStart && controller.idleSeconds == 1800)
        controller.setAutoStart(false)
        precondition(!controller.autoStart && controller.idleSeconds == 0 && controller.error == nil)
        controller.setAutoStart(true)
        precondition(controller.autoStart && controller.idleSeconds == 1800 && controller.error == nil)
        let recreated = ScreenSaverSystemController(domain: domainName, defaults: defaults)
        precondition(recreated.idleSeconds == 1800)
        recreated.setAutoStart(false)
        let reopened = ScreenSaverSystemController(domain: domainName, defaults: defaults)
        reopened.setAutoStart(true)
        precondition(reopened.idleSeconds == 1800)
        let preview = ScreenSaverSystemController(preview: true, domain: domainName, defaults: defaults)
        preview.setAutoStart(false); preview.openSettings()
        precondition(preview.error != nil)
        precondition(ScreenSaverSystemController(domain: domainName, defaults: defaults).idleSeconds == 1800)
        let system = ScreenSaverSystemController()
        print("PASS: isolated CFPreferences domain off/on, persisted restoration across recreation; preview has no writes or launch; production read-only installed=\(system.installed), selected=\(String(describing: system.selected)), idleSeconds=\(String(describing: system.idleSeconds)).")
    }
}
