import AppKit
import ScreenSaver
import SwiftUI
import QuotaCore
import OSLog

@objc(QuotaClockSaverView)
final class QuotaClockSaverView: ScreenSaverView {
    private var snapshot: QuotaSnapshot?
    private var preferences = AmbientPreferences.read()
    private var lastRead = Date.distantPast
    private var lastMinute = -1
    private var lastPage = -1
    private var lastDrift = -1
    private var host: NSHostingView<AmbientDisplay>?
    private let logger = Logger(subsystem: "com.quotaclock", category: "saver")

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    private func setup() {
        animationTimeInterval = 2
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        let view = NSHostingView(rootView: AmbientDisplay(snapshot: nil, preferences: preferences,
            now: .now, page: 0, preview: isPreview, accelerated: false))
        view.appearance = NSAppearance(named: .darkAqua)
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        host = view
        logger.notice("Host=\(ProcessInfo.processInfo.processName, privacy: .public) pid=\(ProcessInfo.processInfo.processIdentifier) preview=\(self.isPreview)")
        refresh(force: true)
    }
    override func startAnimation() { super.startAnimation(); refresh(force: true) }
    override func animateOneFrame() { refresh(force: false) }
    private func refresh(force: Bool) {
        let now = Date()
        var changed = force
        if force || now.timeIntervalSince(lastRead) >= 2 {
            lastRead = now
            if let next = try? SnapshotStore(url: SnapshotLocations.saverExport()).read(), snapshot?.revision != next.revision {
                snapshot = next
                logger.notice("Export read revision=\(next.revision.uuidString, privacy: .public)")
                changed = true
            }
            let nextPrefs = AmbientPreferences.read()
            if nextPrefs != preferences { preferences = nextPrefs; changed = true }
        }
        let minute = Int(now.timeIntervalSince1970 / 60)
        let page = Int(now.timeIntervalSince1970 / Double(max(15, min(30, preferences.pageDuration))))
        let drift = Int(now.timeIntervalSince1970 / 240)
        if minute != lastMinute || page != lastPage || drift != lastDrift { changed = true }
        guard changed else { return }
        lastMinute = minute; lastPage = page; lastDrift = drift
        host?.rootView = AmbientDisplay(snapshot: snapshot, preferences: preferences, now: now,
            page: page, preview: isPreview, accelerated: false)
    }
}
