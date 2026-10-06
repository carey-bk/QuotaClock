import Foundation
import QuotaCore

// Exercise the actual UI translation dictionary, which Core-only tests do not load.
@main struct CheckLocalization {
    static func main() {
        precondition(AppText.value("Appearance", .chinese) == "外观")
        precondition(AppText.value("Follow System", .chinese) == "跟随系统")
        precondition(AppText.value("Appearance", .english) == "Appearance")
        precondition(AppText.value("unknown-key", .chinese) == "unknown-key")
        let menuKeys = ["Use a large card for Hero", "Switch Codex Account", "Hero provider", "Auto Hero follows the signed-in account of your Hero provider. When off, displays follow your provider order.", "Gauge icon", "Dropdown position", "Monochrome", "Color", "Checking account…", "Closing Codex…", "Saving login…", "Sign In Required"]
        precondition(Set(menuKeys).isSubset(of: AppText.allKeys))
        let saverKeys = ["Automatically start screen saver", "Select QuotaClock in macOS", "QuotaClock is selected in macOS", "Install QuotaClock.saver first", "Open Screen Saver Settings", "Screen saver timing is managed by your organization.", "Could not change screen saver timing. Open System Settings to try again.", "Could not open System Settings. Open Screen Saver settings manually."]
        precondition(Set(saverKeys).isSubset(of: AppText.allKeys))
        for language in AppLanguage.allCases where language != .english {
            precondition(Set(AppText.table(language).keys) == AppText.allKeys)
            for key in AppText.allKeys { precondition(!AppText.value(key, language).isEmpty) }
            precondition(!AppText.value("Configured QuotaClock widgets: 4.", language).hasPrefix("Configured"))
        }
        print("UI localization runtime check passed: six languages, complete key coverage")
    }
}
