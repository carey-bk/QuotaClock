import AppKit

@main struct CheckCodexSwitchRuntime {
    @MainActor static func main() {
        do {
            let running = try CodexDesktopSwitch().preflight()
            print("Read-only switch preflight passed. Codex Desktop running: \(running). No app was stopped; no login was read or changed.")
        } catch CodexDesktopSwitchError.externalSession {
            print("Read-only switch preflight correctly blocks while a separate Codex CLI/IDE session is running. No app was stopped; no login was read or changed.")
        } catch {
            print("Read-only preflight failed: \(error.localizedDescription)")
            exit(1)
        }
    }
}
