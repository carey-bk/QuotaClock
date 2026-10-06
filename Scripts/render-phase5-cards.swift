import AppKit
import SwiftUI
import QuotaCore

@main struct Phase5Cards {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_790_467_200)
        func account(_ signature: String?, value: Double) -> ProviderQuota {
            var provider = ProviderQuota(id: "codex", displayName: "Codex", planName: "Pro 5x", limits: [
                LimitWindow(id: "5h", displayName: "5-hour", remainingPercentage: value, resetAt: date.addingTimeInterval(18000), isPrimary: true),
                LimitWindow(id: "week", displayName: "Weekly", remainingPercentage: 72, resetAt: date.addingTimeInterval(604800))
            ], lastUpdated: date, bankResetCount: 2)
            provider.health = ProviderHealth(state: .healthy, lastSuccess: date)
            if let signature {
                let account = AccountPresentation(id: UUID(), signature: signature)
                var product = ProductMigration.product(provider); product.account = account
                product.id = "codex.subscription.account." + account.id.uuidString.lowercased()
                provider.id = product.sourceID; provider.products = [product]; provider.account = account
            }
            return provider
        }
        let names: [String?] = [nil, "Carey", "Work", "HanzQ", "Abcdefghijkl"]
        for (index, name) in names.enumerated() {
            let provider = account(name, value: index == 1 ? 88 : 46)
            for language in [AppLanguage.english, .chinese] {
                for (density, width, height, suffix) in [(ProviderCardDensity.compact, 170.0, 170.0, "small"), (.medium, 360, 170, "medium"), (.full, 360, 360, "large")] {
                    try render(ProviderCard(provider: provider, density: density, saverPanel: true, language: language)
                        .frame(width: width, height: height), output: output.appendingPathComponent("\(name ?? "single")-\(suffix)-\(language.rawValue).png"))
                }
            }
        }
        let cards = [account("Carey", value: 88), account("Work", value: 64), account("Backup", value: 32)]
        let snapshot = QuotaSnapshot(generatedAt: date, providers: cards)
        try render(AmbientDisplay(snapshot: snapshot, preferences: AmbientPreferences(), now: date, page: 0, preview: false, accelerated: false)
            .frame(width: 1600, height: 1000), output: output.appendingPathComponent("three-account-saver.png"))
        if CommandLine.arguments.contains("--show-menu") {
            showMenu(snapshot)
        }
    }
    /// ScrollView needs a visible native host for pixel inspection; it cannot use ImageRenderer.
    @MainActor static func showMenu(_ snapshot: QuotaSnapshot) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let frame = NSRect(x: 180, y: 180, width: 380, height: 610)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Phase 5 — Synthetic Menu Preview"
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: MenuCardsView(choosingAccount: .constant(false), snapshot: snapshot, language: .english, refreshing: false,
            refresh: {}, showSettings: {}, quit: { NSApp.terminate(nil) }).frame(width: 380, height: 610))
        host.frame = NSRect(origin: .zero, size: frame.size); window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        withExtendedLifetime(window) { NSApp.run() }
    }
    @MainActor static func render<V: View>(_ view: V, output: URL) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark)); renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("render") }
        try data.write(to: output)
    }
}
