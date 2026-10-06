import AppKit
import SwiftUI
import QuotaCore

@main struct SurfaceCards {
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
        var cards = [account("Work", value: 88), account("Home", value: 64), account("Backup", value: 32)]
        cards[0].account?.isCurrent = true
        cards[0].products?[0].account?.isCurrent = true
        for count in 1...3 {
            var snapshot = QuotaSnapshot(generatedAt: date, providers: cards)
            var platform = PlatformPreferences()
            platform.surfaces = SurfaceConfiguration(menu: cards.map(\.id), hero: "codex", secondary: Array(cards.dropFirst().prefix(count - 1).map(\.id)))
            snapshot.platformPreferences = platform
            for (name, w, h) in [("landscape",1600.0,1000.0),("portrait",720,1280),("wide",1600,675)] {
                try render(AmbientDisplay(snapshot: snapshot, preferences: AmbientPreferences(), now: date, page: 99, preview: false, accelerated: false, allowsMotion: false)
                    .frame(width: w, height: h), output: output.appendingPathComponent("\(name)-1+\(count-1).png"))
            }
        }
        var balance = ProviderQuota(id: "deepseek", displayName: "DeepSeek", planName: nil, limits: [], lastUpdated: date,
            balances: [BalanceAmount(currency: "CNY", total: 42)], balanceAvailable: true)
        var pref = ProviderDisplayPreference(); pref.nickname = "Studio"; balance.displayPreference = pref
        try render(ProviderCard(provider: balance, density: .full, saverPanel: true, language: .english).frame(width: 360, height: 360), output: output.appendingPathComponent("provider-nickname.png"))
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
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark)); renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("render") }
        try data.write(to: output)
    }
}
