import AppKit

/// Tests the real launcher with injected discovery/opening. No app is launched
/// or stopped; no credentials are read. Run separately from the live preflight.
@main struct CheckCodexSwitchLaunch {
    @MainActor static func main() async throws {
        var opened: [URL] = []
        let missing = CodexDesktopSwitch(locateApplication: { _ in nil }, openApplication: { opened.append($0) })
        do {
            try await missing.reopen(launchIfClosed: true)
            fatalError("A missing Desktop must not report successful launch")
        } catch CodexDesktopSwitchError.launchFailed { }
        precondition(opened.isEmpty)
        try await missing.reopen(launchIfClosed: false)
        precondition(opened.isEmpty)

        let desktopURL = URL(fileURLWithPath: "/fixture/ChatGPT.app")
        let installed = CodexDesktopSwitch(locateApplication: { id in
            precondition(id == "com.openai.codex"); return desktopURL
        }, openApplication: { opened.append($0) })
        try await installed.reopen(launchIfClosed: true)
        precondition(opened == [desktopURL])

        let failing = CodexDesktopSwitch(locateApplication: { _ in desktopURL }, openApplication: { _ in
            throw CocoaError(.fileReadNoSuchFile)
        })
        do {
            try await failing.reopen(launchIfClosed: true)
            fatalError("An opening error must be reported")
        } catch CodexDesktopSwitchError.launchFailed { }
        print("Desktop launcher checks passed: missing app, failure, success, and no launch after an aborted switch. Injected fixture operations only.")
    }
}
