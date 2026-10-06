import AppKit
import QuotaCore

@main struct CheckMenuStatus {
    static func main() throws {
        _ = NSApplication.shared
        let provider = ProviderQuota(id: "deepseek", displayName: "DeepSeek", planName: nil,
            limits: [.init(id: "quota", displayName: "Quota", remainingPercentage: 42, isPrimary: true)], lastUpdated: .now)
        let snapshot = QuotaSnapshot(generatedAt: .now, providers: [provider])
        for icon in MenuBarIconStyle.allCases {
            for value in [true, false] {
                let empty = MenuBarStatusLabel(snapshot: nil, language: .english, iconStyle: icon, showValue: value).statusImage
                precondition(empty.size.width == 18 && empty.isTemplate)
                let configured = MenuBarStatusLabel(snapshot: snapshot, language: .english, iconStyle: icon, showValue: value).statusImage
                precondition(value ? configured.size.width > 18 : configured.size.width == 18)
                precondition(configured.isTemplate)
            }
        }
        print("Menu status checks passed: empty always 18pt, both icon styles, value on/off, adaptive template rendering.")
    }
}
