import AppKit
import SwiftUI
import WidgetKit
import QuotaCore

@MainActor final class CaptureDirector: NSObject {
    var advance: () -> Void = {}
    @objc func next() { advance() }
}
final class ArtworkWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Website artwork from unchanged production views. The preview controller never
/// loads accounts, credentials, preferences, timers or network services.
@main struct WebsiteNative {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let date = ISO8601DateFormatter().date(from: "2026-10-06T05:02:00Z")!
        let accounts = ["Alpha", "Beta"].enumerated().map { index, name in
            ProviderAccount(id: UUID(uuidString: "00000000-0000-4000-8000-00000000000\(index + 1)")!,
                signature: name, identityKey: "website-fictional-\(name)", connection: .independent)
        }
        func snapshot(current: Int, allAccounts: Bool = false) -> QuotaSnapshot {
            func quota(_ account: ProviderAccount, index: Int) -> ProviderQuota {
                var p = ProviderQuota(id: account.sourceID, displayName: "Codex", planName: "Plus", limits: [
                    .init(id: "5h", displayName: "5-hour", remainingPercentage: index == 0 ? 87 : 100, resetAt: date.addingTimeInterval(18000), isPrimary: true),
                    .init(id: "week", displayName: "Weekly", remainingPercentage: index == 0 ? 20 : 84, resetAt: date.addingTimeInterval(259200))
                ], lastUpdated: date, bankResetCount: 2, usage: .init(totalTokens: 412_800_000, peakDailyTokens: 82_000_000, lastDailyTokens: 18_800_000,
                    dailyHistory: [29,34,21,58,82,47,18].enumerated().map { UsageDay(date: date.addingTimeInterval(Double($0.offset - 6) * 86400), tokens: Int64($0.element) * 1_000_000) }))
                p.account = account.presentation(currentIdentity: accounts[current].identityKey)
                p.health = .init(state: .healthy, lastSuccess: date)
                var product = ProductMigration.product(p)
                product.id = account.productID; product.providerID = "codex"; product.account = p.account
                p.products = [product]
                return p
            }
            var claude = ProviderQuota(id: "claude-code", displayName: "Claude Code", planName: "Pro", limits: [
                .init(id: "5h", displayName: "5-hour", remainingPercentage: 63, resetAt: date.addingTimeInterval(7200), isPrimary: true),
                .init(id: "week", displayName: "Weekly", remainingPercentage: 72, resetAt: date.addingTimeInterval(345600))
            ], lastUpdated: date)
            claude.health = .init(state: .healthy, lastSuccess: date)
            var deepseek = ProviderQuota(id: "deepseek", displayName: "DeepSeek", planName: nil, limits: [], lastUpdated: date,
                balances: [.init(currency: "CNY", total: 5.30)], balanceAvailable: true)
            deepseek.health = .init(state: .healthy, lastSuccess: date)
            let providers = allAccounts ? [quota(accounts[0], index: 0), quota(accounts[1], index: 1), claude, deepseek] : [quota(accounts[current], index: current), claude, deepseek]
            var result = QuotaSnapshot(generatedAt: date, providers: providers)
            var platform = PlatformPreferences()
            platform.codexMultiAccount = true
            platform.enabledProducts = Set(accounts.map(\.productID) + ["claude-code.subscription", "deepseek.api"])
            platform.connectionOrder = providers.map(\.id)
            platform.providerDisplay = .init(autoHero: true, menuLimit: 3, saverLimit: 3, heroProviderID: "codex")
            result.platformPreferences = platform
            return result
        }
        func image<V: View>(_ view: V, name: String, scale: CGFloat = 1) throws {
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark)); renderer.scale = scale
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Native renderer failed") }
            try data.write(to: output.appendingPathComponent(name + ".png"))
        }
        for current in 0...1 {
            let name = current == 0 ? "alpha" : "beta", data = snapshot(current: current)
            let status = MenuBarStatusLabel(snapshot: data, language: .english, appearance: NSAppearance(named: .aqua)).statusImage
            try image(Image(nsImage: status).renderingMode(.original).frame(width: status.size.width, height: 18), name: "status-\(name)", scale: 3)
            for (shape, width, height) in [("landscape",1600.0,1000.0),("portrait",900.0,1300.0)] {
                try image(AmbientDisplay(snapshot: data, preferences: AmbientPreferences(), now: date, page: 0, preview: false, accelerated: false, allowsMotion: false)
                    .frame(width: width, height: height), name: "saver-\(shape)-\(name)")
            }
            try image(WidgetCardContent(provider: data.providers[0], family: .systemSmall, language: .english, renderingMode: .fullColor)
                .frame(width: 170, height: 170).background(WidgetCardBackground()).clipShape(RoundedRectangle(cornerRadius: 22)), name: "widget-\(name)", scale: 3)
            try image(WidgetCardContent(provider: data.providers[0], family: .systemLarge, language: .english, renderingMode: .fullColor)
                .frame(width: 360, height: 360).background(WidgetCardBackground()).clipShape(RoundedRectangle(cornerRadius: 22)), name: "widget-large-\(name)", scale: 2)
        }
        let desktop = snapshot(current: 0)
        try image(WidgetCardContent(provider: desktop.providers[1], family: .systemMedium, language: .english, renderingMode: .fullColor)
            .frame(width: 360, height: 170).background(WidgetCardBackground()).clipShape(RoundedRectangle(cornerRadius: 22)), name: "widget-medium-claude", scale: 2)
        try image(WidgetCardContent(provider: desktop.providers[2], family: .systemSmall, language: .english, renderingMode: .fullColor)
            .frame(width: 170, height: 170).background(WidgetCardBackground()).clipShape(RoundedRectangle(cornerRadius: 22)), name: "widget-small-deepseek", scale: 3)
        if CommandLine.arguments.contains("--export-only") { return }
        let model = SnapshotController(onboardingPreview: true)
        model.preferences.language = .english; model.preferences.appearance = .light
        model.preferences.selectSurfaceLanguage(.appLanguage); model.previewReduceMotion = true
        model.accounts = accounts; model.currentCodexIdentity = accounts[0].identityKey
        model.snapshot = snapshot(current: 0, allAccounts: true); model.platform = model.snapshot!.platformPreferences!
        let window = ArtworkWindow(contentRect: NSRect(x: 80, y: 80, width: 960, height: 700), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "QuotaClock"; window.appearance = NSAppearance(named: .aqua)
        func host<V: View>(_ view: V, width: CGFloat, height: CGFloat, dark: Bool = false) {
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let hosting = NSHostingView(rootView: view)
            hosting.sizingOptions = []
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
            window.contentView = hosting
            window.setContentSize(NSSize(width: width, height: height))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        do {
            let director = CaptureDirector()
            let menu = NSMenu()
            let item = NSMenuItem(); menu.addItem(item)
            let submenu = NSMenu(title: "Capture")
            let next = NSMenuItem(title: "Next native scene", action: #selector(CaptureDirector.next), keyEquivalent: "]")
            next.target = director; submenu.addItem(next)
            submenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            item.submenu = submenu; NSApp.mainMenu = menu
            var scene = -1
            director.advance = {
                scene += 1
                let settings = [("general","General"),("services","AI Services"),("menubar","Menu Bar"),("saver","Screen Saver")]
                if scene < 4 {
                    let (key, section) = settings[scene]
                    model.previewSettingsSection = section
                    window.styleMask = [.titled, .closable, .fullSizeContentView]
                    window.title = "QuotaClock — \(key)"
                    host(SettingsView(model: model).id(key), width: 960, height: 700)
                } else if scene < 7 {
                    let current = scene == 4 ? 0 : 1, success = scene == 6
                    window.styleMask = [.borderless]
                    window.title = scene == 4 ? "menu-alpha-idle" : success ? "menu-beta-success" : "menu-beta-idle"
                    window.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 1)
                    host(MenuCardsView(choosingAccount: .constant(false), snapshot: snapshot(current: current), language: .english, refreshing: false,
                        accountOptions: accounts.map { $0.switchOption(currentIdentity: accounts[current].identityKey) }, switchFeedback: success ? "Codex login switched." : nil,
                        refresh: {}, showSettings: {}, quit: {}, cardViewportHeight: 546, forceReducedMotion: true)
                        .frame(width: 372, height: success ? 648 : 600), width: 372, height: success ? 648 : 600, dark: true)
                } else if scene < 9 {
                    let current = scene == 7 ? 0 : 1
                    window.title = "chooser-\(current == 0 ? "alpha" : "beta")"
                    host(CodexAccountChooserView(language: .english, options: accounts.map { $0.switchOption(currentIdentity: accounts[current].identityKey) }, choose: {_ in}, dismiss: {})
                        .frame(width: 252, height: 186), width: 252, height: 186, dark: true)
                } else { NSApp.terminate(nil) }
            }
            director.advance()
            withExtendedLifetime((window, model, director)) { NSApp.run() }
            return
        }
    }
}
