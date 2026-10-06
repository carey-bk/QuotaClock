import AppKit
import SwiftUI
import QuotaCore

/// Isolated UI harness. It never starts the live SnapshotController services.
@main struct OnboardingPreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let args = CommandLine.arguments
        func argument(_ name: String, fallback: String) -> String {
            guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return fallback }
            return args[index + 1]
        }
        let model = SnapshotController(onboardingPreview: true)
        model.preferences.language = AppLanguage(rawValue: argument("--language", fallback: "english")) ?? .english
        model.previewReduceMotion = args.contains("--reduce-motion")
        model.previewSettingsSection = argument("--settings-section", fallback: "AI Services")
        model.previewShowDiagnostics = args.contains("--diagnostics")
        model.refreshing = args.contains("--refreshing")
        model.signingIn = args.contains("--connecting")
        let step = OnboardingStep(rawValue: Int(argument("--step", fallback: "0")) ?? 0) ?? .welcome
        let flow = OnboardingController(persists: false, startingStep: step)
        if args.contains("--settings") { flow.finish() }
        if args.contains("--check-flow") {
            let lock = OnboardingController(persists: false)
            lock.move(1, reducedMotion: false); lock.move(1, reducedMotion: false)
            precondition(lock.progress.step == .appearance && lock.transitioning)
            let skipped = OnboardingController(persists: false, startingStep: .display)
            skipped.deferSetup()
            precondition(!skipped.isPresented && skipped.progress.disposition == .deferred)
            skipped.reopen()
            precondition(skipped.isPresented && skipped.progress.step == .display)
            skipped.finish(); let firstCompletion = skipped.progress.completedAt
            skipped.reopen(); skipped.deferSetup()
            precondition(skipped.progress.completedAt == firstCompletion && skipped.progress.disposition == .completed)
            var choices = model.preferences; choices.showClock = false
            model.savePreferences(choices)
            precondition(!model.preferences.showClock)
            print("Onboarding controller checks passed: rapid navigation lock, defer/resume, completion/revisit, shared preference binding.")
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 160, y: 120, width: 820, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.setFrame(NSRect(x: 160, y: 120, width: 820, height: 600), display: false)
        window.isReleasedWhenClosed = false
        window.title = "QuotaClock — Isolated Onboarding Preview"
        window.appearance = NSAppearance(named: args.contains("--dark") ? .darkAqua : .aqua)
        if args.contains("--failure") { model.accountFeedback = "No Codex login found. Open Codex, sign in, then retry." }
        if args.contains("--saved") {
            let account = ProviderAccount(signature: "Preview", identityKey: "synthetic-preview-only", connection: .currentSession)
            model.accounts = [account]
            model.platform.enabledProducts = [account.productID]
            var provider = ProviderQuota(id: account.sourceID, displayName: "Codex", planName: "Demo",
                limits: [.init(id: "5h", displayName: "5-hour", remainingPercentage: 62, isPrimary: true),
                         .init(id: "week", displayName: "Weekly", remainingPercentage: 81)], lastUpdated: Date())
            provider.account = .init(id: account.id, signature: "Preview")
            provider.health = .init(state: args.contains("--stale") ? .stale : .healthy)
            model.snapshot = QuotaSnapshot(generatedAt: Date(), providers: [provider])
        }
        if args.contains("--hero-fixture") {
            // Multiple saved accounts must yield one entry per provider family.
            let fixtures = [("codex", "Alpha"), ("codex", "Beta"), ("claude-code", "Work"), ("claude-code", "Personal")]
            model.accounts = fixtures.map { family, name in
                ProviderAccount(providerID: family, signature: name, identityKey: "fixture-\(name)", connection: .independent)
            }
            model.currentCodexIdentity = model.accounts.first?.identityKey
            model.platform.enabledProducts = Set(model.accounts.map(\.productID))
            model.platform.providerDisplay = .init(heroProviderID: "codex")
            precondition(model.heroProviderIDs == ["codex", "claude-code"])
            model.platform.providerDisplay?.menuLimit = 4
            model.platform.menuBarHeroLarge = args.contains("--large-hero")
            let count = Int(argument("--provider-count", fallback: "4")) ?? 4
            let providers = model.accounts.prefix(count).enumerated().map { index, account in
                var p = ProviderQuota(id: account.sourceID, displayName: account.providerID == "codex" ? "Codex" : "Claude Code", planName: "Demo", limits: [.init(id: "5h", displayName: "5-hour", remainingPercentage: Double(75 - index * 15), isPrimary: true), .init(id: "week", displayName: "Weekly", remainingPercentage: 52)], lastUpdated: .now)
                p.account = .init(id: account.id, signature: account.signature, isCurrent: index == 0)
                p.health = .init(state: .healthy)
                var product = ProductMigration.product(p)
                product.id = account.productID; product.providerID = account.providerID; product.account = p.account
                p.products = [product]
                return p
            }
            model.snapshot = QuotaSnapshot(generatedAt: .now, providers: providers)
            model.snapshot?.platformPreferences = model.platform
        }
        let host = NSHostingView(rootView: args.contains("--full-menu") ? AnyView(FullMenuBarPreview(model: model)) : AnyView(QuotaClockRootView(model: model, flow: flow)))
        if args.contains("--full-menu") {
            let count = model.snapshot?.forSurface(.menuBar).providers.count ?? 0
            let height = max(280, min(626, MenuCardLayout.contentHeight(cards: count, largeHero: model.platform.menuBarHeroLarge) + 54))
            window.setContentSize(NSSize(width: 780, height: height + 44))
        }
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if args.contains("--render") {
            let count = max(1, Int(argument("--render-count", fallback: "1")) ?? 1)
            let interval = max(0.1, Double(argument("--render-interval", fallback: "2")) ?? 2)
            let initialPreferences = model.preferences
            let started = Date()
            for index in 0..<count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(index) * interval) {
                    host.layoutSubtreeIfNeeded()
                    // Audit the in-process accessibility layout, independently of bitmap compositing.
                    func audit(_ object: Any, depth: Int = 0) -> [[String: Any]] {
                        guard depth < 30, let node = object as? NSAccessibilityProtocol else { return [] }
                        let label = node.accessibilityLabel() ?? ""
                        let value = node.accessibilityValue() as? String ?? ""
                        let frame = node.accessibilityFrame()
                        var rows: [[String: Any]] = []
                        if !label.isEmpty || !value.isEmpty {
                            rows.append(["label": label, "value": value, "frame": NSStringFromRect(frame)])
                        }
                        for child in node.accessibilityChildren() ?? [] { rows += audit(child, depth: depth + 1) }
                        return rows
                    }
                    let captureView = window.attachedSheet?.contentView ?? host
                    let accessibility = audit(captureView)
                    let auditURL = URL(fileURLWithPath: argument("--output", fallback: "/tmp/onboarding.png")).deletingPathExtension().appendingPathExtension("json")
                    if let data = try? JSONSerialization.data(withJSONObject: accessibility, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: auditURL) }

                    let base = URL(fileURLWithPath: argument("--output", fallback: "/tmp/onboarding.png"))
                    let url = count == 1 ? base : base.deletingPathExtension().appendingPathExtension("\(index).png")
                    guard let rep = captureView.bitmapImageRepForCachingDisplay(in: captureView.bounds) else { fatalError("No bitmap") }
                    captureView.cacheDisplay(in: captureView.bounds, to: rep)
                    try! rep.representation(using: .png, properties: [:])!.write(to: url)
                    precondition(model.preferences.language == initialPreferences.language)
                    precondition(model.preferences.effectiveWidgetLanguage == initialPreferences.effectiveWidgetLanguage)
                    print("Rendered \(Int(host.bounds.width)) × \(Int(host.bounds.height)) at \(String(format: "%.2f", Date().timeIntervalSince(started)))s: \(url.lastPathComponent); language preferences unchanged")
                    if index == count - 1 {
                        if let sheet = window.attachedSheet { window.endSheet(sheet); sheet.orderOut(nil) }
                        // Stop this harness directly: termination can be deferred by an active sheet.
                        NSApp.stop(nil)
                        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                            timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                            NSApp.postEvent(event, atStart: false)
                        }
                    }
                }
            }
        }
        withExtendedLifetime((window, model, flow)) { NSApp.run() }
    }
}
