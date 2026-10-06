import AppKit
import SwiftUI
import QuotaCore

/// Uses production panels and views. Credentials, network, app restarts and preferences are isolated.
@main struct MenuSwitchPreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.regular)
        let model = SnapshotController(onboardingPreview: true)
        model.preferences.language = CommandLine.arguments.contains("--english") ? .english : .chinese
        model.preferences.selectSurfaceLanguage(.appLanguage)
        model.previewReduceMotion = CommandLine.arguments.contains("--reduce-motion")
        model.accounts = ["Alpha", "Beta", "Linked"].enumerated().map { index, name in
            ProviderAccount(signature: name, identityKey: "fixture-\(name)", connection: index == 2 ? .currentSession : .independent)
        }
        model.currentCodexIdentity = model.accounts[0].identityKey
        model.platform.enabledProducts = Set(model.accounts.map(\.productID))
        model.platform.menuBarHeroLarge = CommandLine.arguments.contains("--large-hero")
        model.platform.providerDisplay = .init(heroProviderID: "codex")
        model.platform.connectionOrder = model.accounts.map(\.sourceID)
        let cards = model.accounts.enumerated().map { index, account in
            var p = ProviderQuota(id: account.sourceID, displayName: "Codex", planName: "Plus",
                limits: [.init(id: "5h", displayName: "5h", remainingPercentage: [69,42,0][index], resetAt: .now.addingTimeInterval(18000), isPrimary: true),
                         .init(id: "week", displayName: "Weekly", remainingPercentage: 76)], lastUpdated: .now, bankResetCount: 2,
                usage: .init(totalTokens: 412_800_000, peakDailyTokens: 82_000_000, lastDailyTokens: 18_800_000,
                    dailyHistory: [29,34,21,58,82,47,18].enumerated().map { offset, value in
                        UsageDay(date: .now.addingTimeInterval(Double(offset - 6) * 86400), tokens: Int64(value) * 1_000_000)
                    }))
            p.account = account.presentation(currentIdentity: model.currentCodexIdentity)
            var product = ProductMigration.product(p)
            product.id = account.productID; product.providerID = account.providerID; product.account = p.account
            p.products = [product]
            return p
        }
        model.snapshot = QuotaSnapshot(generatedAt: .now, providers: cards)
        model.snapshot?.platformPreferences = model.platform
        _ = try model.snapshot!.validated()
        let controller = StatusPanelController(model: model)
        let screen = NSScreen.main!.visibleFrame
        controller.previewAnchor = NSRect(x: screen.midX + 220, y: screen.maxY, width: 32, height: 22)
        controller.previewScreen = screen
        controller.previewSwitchAccount = { id in
            model.switchingAccountID = id; model.accountSwitchStage = "Closing Codex…"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                model.currentCodexIdentity = model.accounts.first { $0.id == id }?.identityKey
                if var snapshot = model.snapshot {
                    for index in snapshot.providers.indices {
                        let current = snapshot.providers[index].account?.id == id
                        snapshot.providers[index].account?.isCurrent = current
                        snapshot.providers[index].products?[0].account?.isCurrent = current
                    }
                    snapshot.platformPreferences = model.platform
                    snapshot.generatedAt = .now
                    model.snapshot = snapshot
                    precondition(snapshot.hero?.account?.id == id)
                }
                model.switchingAccountID = nil; model.accountSwitchStage = nil
                model.accountSwitchFeedback = "Codex login switched."
                print("Fixture switch callback succeeded; no real account changed.")
            }
        }
        var scrollProbeWindow: NSWindow?
        var scrollProbeMonitor: Any?
        if CommandLine.arguments.contains("--scroll-probe") {
            let w = NSWindow(contentRect: screen.insetBy(dx: 80, dy: 30), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Scroll destination probe (no real data)"
            let scroll = NSScrollView(frame: w.contentLayoutRect)
            scroll.hasVerticalScroller = true
            let text = NSTextView(frame: NSRect(x: 0, y: 0, width: scroll.bounds.width, height: 4000))
            text.string = (0..<100).map { "Background row \($0) — scrolling here must not move while the pointer is inside the menu." }.joined(separator: "\n\n")
            scroll.documentView = text; w.contentView = scroll
            w.makeKeyAndOrderFront(nil); scrollProbeWindow = w
            scrollProbeMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                print("SCROLL destination=\(event.window === w ? "BACKGROUND" : "MENU") point=\(event.locationInWindow)")
                fflush(stdout)
                return event
            }
        }
        controller.showPreview(); NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--transparent-baseline") { controller.previewUseTransparentBackground() }

        if CommandLine.arguments.contains("--scroll-probe") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let captures = controller.previewWindowTargetAtGap()
                print("Gap target is menu: \(captures)"); fflush(stdout)
            }
        }
        if CommandLine.arguments.contains("--check-hero-follow") {
            _ = Task { @MainActor in
                try await Task.sleep(for: .milliseconds(550))
                let initialFrame = controller.previewFrame!
                let initialViewport = model.menuCardViewportHeight
                let target = model.accounts[1]
                controller.previewSwitchAccount?(target.id)
                try await Task.sleep(for: .milliseconds(1200))
                let snapshot = try model.snapshot!.validated()
                precondition(snapshot.hero?.account?.id == target.id)
                precondition(snapshot.forSurface(.menuBar).providers.first?.account?.id == target.id)
                precondition(snapshot.forSurface(.menuBar).providers.dropFirst().first?.account?.id == model.accounts[0].id)
                precondition(model.menuCardViewportHeight == initialViewport)
                precondition(controller.previewFrame!.maxY == initialFrame.maxY)
                print("PASS: simulated login moves Beta into the square Hero position, retains Alpha/Linked as regular cards, preserves viewport and top anchor; no real login or restart.")
                if !CommandLine.arguments.contains("--keep-open") { NSApp.terminate(nil) }
            }
        }
        if CommandLine.arguments.contains("--check-large-hero") {
            _ = Task { @MainActor in
                try await Task.sleep(for: .milliseconds(550))
                let baseline = controller.previewFrame!
                let baselineViewport = model.menuCardViewportHeight
                var preference = model.platform; preference.menuBarHeroLarge = true
                model.savePlatform(preference)
                try await Task.sleep(for: .milliseconds(550))
                let expanded = controller.previewFrame!
                precondition(expanded.width == baseline.width && expanded.maxY == baseline.maxY)
                precondition(model.menuCardViewportHeight > baselineViewport)
                precondition(expanded.height - baseline.height <= 190)
                model.menuAccountChooserOpen = true
                try await Task.sleep(for: .milliseconds(500))
                precondition(controller.previewFrame == expanded)
                precondition(controller.previewChooserFrame!.maxX < expanded.minX)
                preference.menuBarHeroLarge = false; model.savePlatform(preference)
                try await Task.sleep(for: .milliseconds(550))
                precondition(controller.previewFrame == baseline, "Turning off large Hero changed \(baseline) to \(String(describing: controller.previewFrame))")
                precondition(model.menuCardViewportHeight == baselineViewport)
                print("PASS: live large-Hero toggle expands \(baseline) to \(expanded), preserves top/width and separate chooser, and restores original frame without reopening.")
                NSApp.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--render") {
            _ = Task { @MainActor in
                try await Task.sleep(for: .milliseconds(600))
                model.menuAccountChooserOpen = true
                try await Task.sleep(for: .milliseconds(600))
                let output = URL(fileURLWithPath: CommandLine.arguments.last!, isDirectory: true)
                try controller.exportPreview(to: output, name: model.preferences.language == .english ? "menu-en" : "menu-zh")
                model.menuAccountChooserOpen = false; model.accountSwitchFeedback = "Codex login switched."
                try await Task.sleep(for: .milliseconds(600))
                try controller.exportPreview(to: output, name: "notification")
                NSApp.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--check-notifications") {
            _ = Task { @MainActor in
                try await Task.sleep(for: .milliseconds(550))
                let baseline = controller.previewFrame!
                model.menuAccountChooserOpen = true
                try await Task.sleep(for: .milliseconds(500))
                precondition(controller.previewFrame == baseline, "Chooser changed \(baseline) to \(String(describing: controller.previewFrame))")
                precondition(controller.previewChooserFrame!.maxX < baseline.minX)
                model.menuAccountChooserOpen = false
                model.accountSwitchFeedback = "Could not reopen Codex. Open it manually."
                var heights: [CGFloat] = []
                for _ in 0..<8 {
                    try await Task.sleep(for: .milliseconds(45)); heights.append(controller.previewFrame!.height)
                }
                try await Task.sleep(for: .milliseconds(200))
                precondition(controller.previewFrame!.height == baseline.height + 48)
                if !model.previewReduceMotion { precondition(heights.contains { $0 > baseline.height && $0 < baseline.height + 48 }) }
                precondition(controller.previewFrame!.maxY == baseline.maxY)
                try await Task.sleep(for: .seconds(2))
                model.accountSwitchFeedback = "Codex login switched."
                try await Task.sleep(for: .seconds(3))
                precondition(model.accountSwitchFeedback != nil)
                try await Task.sleep(for: .milliseconds(2500))
                precondition(model.accountSwitchFeedback == nil)
                // Published state and the queued native-window update can arrive on adjacent run-loop turns.
                for _ in 0..<10 {
                    if controller.previewFrame == baseline { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                precondition(controller.previewFrame == baseline, "After dismissal: baseline \(baseline); actual \(String(describing: controller.previewFrame)); viewport \(model.menuCardViewportHeight)")
                precondition(controller.previewChooserFrame == nil)
                controller.hidePreview(); controller.showPreview()
                precondition(model.menuPresentationID == 2)
                print("PASS: separate left chooser preserves main frame; notification animation has intermediate heights \(heights); latest message expires after 5s; top anchor stable; footer returns; reopen restarts reveal.")
                NSApp.terminate(nil)
            }
        }
        withExtendedLifetime((controller, model, scrollProbeWindow, scrollProbeMonitor)) { NSApp.run() }
    }
}
