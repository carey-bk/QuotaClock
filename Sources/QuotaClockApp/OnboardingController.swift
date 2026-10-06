import SwiftUI
import QuotaCore

@MainActor final class OnboardingController: ObservableObject {
    @Published private(set) var progress: OnboardingProgress
    @Published var isPresented: Bool
    @Published private(set) var transitioning = false
    @Published private(set) var movingForward = true
    private let persists: Bool
    init(persists: Bool = true, startingStep: OnboardingStep = .welcome) {
        self.persists = persists
        var saved = persists ? OnboardingProgress.load() : .init()
        if !persists { saved.move(to: startingStep) }
        progress = saved; isPresented = saved.shouldPresentAutomatically
    }
    func move(_ offset: Int, reducedMotion: Bool) {
        guard !transitioning, let next = progress.step.offset(by: offset) else { return }
        transitioning = true; movingForward = offset > 0
        withAnimation(reducedMotion ? nil : .easeInOut(duration: 0.38)) { progress.move(to: next) }
        persist()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reducedMotion ? 120 : 400))
            transitioning = false
        }
    }
    func reopen() {
        if progress.completedAt != nil { progress.move(to: .welcome) }
        isPresented = true
    }
    func finish() { progress.finish(); persist(); isPresented = false }
    func deferSetup() { progress.deferSetup(); persist(); isPresented = false }
    private func persist() { if persists { try? progress.save() } }
}

/// The tour and the main workspace share the existing settings window identity.
struct QuotaClockRootView: View {
    @ObservedObject var model: SnapshotController
    @StateObject private var onboarding: OnboardingController
    @Environment(\.openWindow) private var openWindow
    init(model: SnapshotController, flow: OnboardingController? = nil) {
        self.model = model
        _onboarding = StateObject(wrappedValue: flow ?? OnboardingController(persists: !model.onboardingPreview))
    }
    var body: some View {
        Group {
            if onboarding.isPresented {
                OnboardingView(model: model, flow: onboarding)
            } else {
                SettingsView(model: model, reopenOnboarding: onboarding.reopen,
                    startWithProviders: onboarding.progress.disposition != .inProgress)

            }
        }
        .background(OnboardingWindowChrome(immersive: onboarding.isPresented))
        .onAppear { model.openSettings = { openWindow(id: "settings") } }
    }
}

/// Configure chrome once per mode, never resize the window on a page change.
struct OnboardingWindowChrome: NSViewRepresentable {
    let immersive: Bool
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context: Context) { view.immersive = immersive; view.configure() }
    final class ChromeView: NSView {
        var immersive = false
        private var applied: Bool?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
        func configure() {
            guard let window, applied != immersive else { return }
            applied = immersive
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                window.styleMask.insert(.fullSizeContentView)
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.titlebarSeparatorStyle = .none
                if self.immersive {
                    window.title = ""
                    window.toolbar = nil
                }
                window.isMovableByWindowBackground = self.immersive
                let available = window.screen?.visibleFrame.size ?? NSSize(width: 1100, height: 750)
                if self.immersive {
                    window.minSize = NSSize(width: 820, height: 600)
                    window.maxSize = NSSize(width: 1600, height: 1200)
                    var frame = window.frame
                    frame.size = NSSize(width: min(820, available.width - 40), height: min(600, available.height - 40))
                    window.setFrame(frame, display: true)
                } else {
                    window.contentMinSize = NSSize(width: 700, height: 600)
                    window.contentMaxSize = NSSize(width: 1200, height: 1200)
                    window.setContentSize(NSSize(width: 740, height: min(680, available.height - 50)))
                }
                if self.immersive { window.center() }
            }
        }
    }
}
