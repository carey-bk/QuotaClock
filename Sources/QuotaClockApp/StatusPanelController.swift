import AppKit
import SwiftUI
import Combine
import QuotaCore
import QuartzCore

private final class StatusGlassPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var capturesMenuScroll = false
    override func sendEvent(_ event: NSEvent) {
        // A transparent gap or footer still belongs to the menu. Route wheel
        // and momentum events to the cards once, independent of the hit view.
        if capturesMenuScroll, event.type == .scrollWheel, let contentView,
           contentView.bounds.contains(contentView.convert(event.locationInWindow, from: nil)) {
            func scrollView(in view: NSView) -> NSScrollView? {
                if let scroll = view as? NSScrollView { return scroll }
                return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
            }
            scrollView(in: contentView)?.scrollWheel(with: event)
            return
        }
        super.sendEvent(event)
    }
}

/// Keep the full transparent rectangle in AppKit's input region without
/// introducing a visible background behind the individual glass cards.
private final class MenuPanelHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point) ?? self
    }
}

@MainActor final class StatusPanelController: NSObject {
    private weak var model: SnapshotController?
    private var item: NSStatusItem?
    private var panel: NSPanel?
    private var chooserPanel: NSPanel?
    private var targetFrame: NSRect?
    private var chooserGeneration = 0
    private var chooserClosing = false
    private var observation: AnyCancellable?
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var menuTracking = false
    private var menuObservations: [AnyCancellable] = []
    private var reducedMotion: Bool { model?.previewReduceMotion == true || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    #if ONBOARDING_PREVIEW
    var previewSwitchAccount: ((UUID) -> Void)?
    var previewAnchor: NSRect?
    var previewScreen: NSRect?
    #endif
    init(model: SnapshotController) {
        self.model = model
        super.init()
        observation = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.update() }
        }
        menuObservations = [
            NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification).sink { [weak self] _ in self?.menuTracking = true },
            NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification).sink { [weak self] _ in self?.menuTracking = false }
        ]
        update()
    }
    private func update() {
        guard let model else { return }
        if !model.platform.showMenuBar {
            close()
            if let item { NSStatusBar.system.removeStatusItem(item); self.item = nil }
            return
        }
        if item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.setAccessibilityLabel("QuotaClock")
            item.button?.target = self; item.button?.action = #selector(toggle)
            self.item = item
        }
        let unconfigured = model.connectedSources.isEmpty
        let emptyLabel = AppText.value("No providers configured", model.preferences.effectiveMenuLanguage)
        item?.button?.title = ""
        item?.button?.toolTip = unconfigured ? emptyLabel : "QuotaClock"
        item?.button?.image = MenuBarStatusLabel(snapshot: unconfigured ? nil : model.snapshot, language: model.preferences.effectiveMenuLanguage, iconStyle: model.platform.effectiveMenuBarIconStyle(hasConfiguredProviders: !unconfigured), showValue: model.platform.menuBarShowValue, gaugeColor: model.platform.menuBarGaugeColor).statusImage
        item?.button?.setAccessibilityLabel(unconfigured ? "QuotaClock — \(emptyLabel)" : "QuotaClock")
        if panel?.isVisible == true { position() }
    }
    private func makePanel() -> NSPanel {
        let panel = StatusGlassPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        // WindowServer excludes fully transparent pixels from pointer targeting.
        // hitTest/sendEvent alone cannot help when the event goes to another app.
        // A single alpha step retains the entire input rectangle, with no visible
        // panel chrome; actual cards keep their existing glass materials.
        panel.backgroundColor = NSColor.black.withAlphaComponent(1.0 / 255.0)
        panel.ignoresMouseEvents = false
        panel.hasShadow = false
        panel.level = .popUpMenu; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
    @objc private func toggle() {
        guard let model else { return }
        if panel?.isVisible == true { close(); return }
        if panel == nil {
            let panel = makePanel()
            (panel as? StatusGlassPanel)?.capturesMenuScroll = true
            panel.contentView = MenuPanelHostingView(rootView: MenuSnapshotView(model: model, showSettings: { [weak self] in
                self?.close()
                NSApp.activate(ignoringOtherApps: true)
                self?.model?.openSettings?()
            }))
            self.panel = panel
        }
        model.menuPresentationID += 1
        position(); panel?.makeKeyAndOrderFront(nil)
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in if self?.menuTracking != true { self?.close() } }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, !self.menuTracking else { return event }
            if event.type == .keyDown && event.keyCode == 53 {
                if self.model?.menuAccountChooserOpen == true { self.model?.menuAccountChooserOpen = false }
                else { self.close() }
                return nil
            }
            if event.type != .keyDown && event.window != self.panel && event.window != self.chooserPanel && event.window != self.item?.button?.window { self.close() }
            return event
        }
    }
    private func animate(_ changes: () -> Void, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reducedMotion ? 0 : 0.32
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.25, 1)
            changes()
        } completionHandler: { completion?() }
    }
    private func position() {
        guard let button = item?.button, let window = button.window, let panel, let model else { return }
        var anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        var screen = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        #if ONBOARDING_PREVIEW
        anchor = previewAnchor ?? anchor; screen = previewScreen ?? screen
        #endif
        let layout = MenuPanelLayout(anchor: anchor, screen: screen, alignment: model.platform.menuBarAlignment,
            cards: model.snapshot?.forSurface(.menuBar).providers.count ?? 0,
            accounts: model.accounts.filter { $0.providerID == "codex" }.count,
            feedback: model.accountSwitchStage != nil || model.accountSwitchFeedback != nil,
            choosingAccount: model.menuAccountChooserOpen,
            largeHero: model.platform.menuBarHeroLarge && model.snapshot?.forSurface(.menuBar).providers.prefix(8).contains { $0.id == model.snapshot?.hero?.id } == true)
        if model.menuCardViewportHeight != layout.cardHeight { model.menuCardViewportHeight = layout.cardHeight }
        if targetFrame != layout.main {
            targetFrame = layout.main
            if panel.isVisible && !reducedMotion {
                animate { panel.animator().setFrame(layout.main, display: true) }
            } else { panel.setFrame(layout.main, display: true) }
        }
        if let frame = layout.chooser { showChooser(at: frame) }
        else { hideChooser() }
    }
    private func showChooser(at frame: NSRect) {
        guard let model, let panel else { return }
        if chooserPanel == nil {
            let child = makePanel()
            child.setAccessibilityLabel(AppText.value("Switch Codex Account", model.preferences.effectiveMenuLanguage))
            child.contentView = NSHostingView(rootView: AccountChooserSnapshotView(model: model, choose: { [weak self] id in
                guard let self else { return }
                model.menuAccountChooserOpen = false
                #if ONBOARDING_PREVIEW
                if let previewSwitchAccount = self.previewSwitchAccount { previewSwitchAccount(id); return }
                #endif
                if let account = model.accounts.first(where: { $0.id == id }) { model.switchCodexAccount(account) }
            }))
            chooserPanel = child
        }
        guard let child = chooserPanel else { return }
        let opening = !child.isVisible || chooserClosing
        if opening {
            chooserGeneration += 1; chooserClosing = false
            child.setFrame(frame.offsetBy(dx: reducedMotion ? 0 : 8, dy: 0), display: true)
            child.alphaValue = reducedMotion ? 1 : 0
            panel.addChildWindow(child, ordered: .above)
            child.makeKeyAndOrderFront(nil)
            if reducedMotion { child.alphaValue = 1; child.setFrame(frame, display: true) }
            else { animate { child.animator().alphaValue = 1; child.animator().setFrame(frame, display: true) } }
        } else if child.frame != frame {
            if reducedMotion { child.setFrame(frame, display: true) }
            else { animate { child.animator().setFrame(frame, display: true) } }
        }
    }
    private func hideChooser() {
        guard let child = chooserPanel, child.isVisible, !chooserClosing else { return }
        if reducedMotion {
            chooserGeneration += 1; chooserClosing = false
            panel?.removeChildWindow(child); child.orderOut(nil)
            return
        }
        chooserClosing = true; chooserGeneration += 1
        let generation = chooserGeneration
        animate { child.animator().alphaValue = 0 } completion: { [weak self] in
            guard let self, self.chooserGeneration == generation else { return }
            self.panel?.removeChildWindow(child); child.orderOut(nil); self.chooserClosing = false
        }
    }
    #if ONBOARDING_PREVIEW
    func previewWindowTargetAtGap() -> Bool {
        guard let panel else { return false }
        let point = NSPoint(x: panel.frame.midX, y: panel.frame.maxY - 372)
        let target = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        print("WindowServer gap target=\(target), menu=\(panel.windowNumber), point=\(point)")
        return target == panel.windowNumber
    }
    func previewUseTransparentBackground() { panel?.backgroundColor = .clear }
    var previewFrame: NSRect? { panel?.frame }
    var previewChooserFrame: NSRect? { chooserPanel?.isVisible == true ? chooserPanel?.frame : nil }
    func showPreview() { if panel?.isVisible != true { toggle() } }
    func hidePreview() { close() }
    func exportPreview(to directory: URL, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (suffix, window) in [("cards", panel), ("accounts", chooserPanel)] {
            guard let window, window.isVisible, let view = window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.layoutSubtreeIfNeeded(); view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }

    #endif
    private func close() {
        chooserGeneration += 1; chooserClosing = false
        if let chooserPanel { panel?.removeChildWindow(chooserPanel); chooserPanel.orderOut(nil) }
        panel?.orderOut(nil)
        model?.menuAccountChooserOpen = false
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor); self.outsideMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
    }
}

private struct AccountChooserSnapshotView: View {
    @ObservedObject var model: SnapshotController
    let choose: (UUID) -> Void
    var body: some View {
        CodexAccountChooserView(language: model.preferences.effectiveMenuLanguage,
            options: model.accounts.filter { $0.providerID == "codex" }.map { $0.switchOption(currentIdentity: model.currentCodexIdentity) },
            disabled: model.signingIn || model.switchingAccountID != nil, choose: choose,
            dismiss: { model.menuAccountChooserOpen = false })
    }
}
