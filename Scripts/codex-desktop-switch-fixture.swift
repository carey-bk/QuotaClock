import AppKit

/// Disposable native app for lifecycle tests; never reads the user's Codex home.
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateCancel }
}
@main struct Fixture {
    static func main() throws {
        let home = URL(fileURLWithPath: CommandLine.arguments[1])
        precondition(home.lastPathComponent == "fixture-home")
        let auth = try JSONSerialization.jsonObject(with: Data(contentsOf: home.appendingPathComponent("auth.json"))) as! [String: Any]
        let id = (auth["tokens"] as! [String: Any])["account_id"] as! String
        try Data(id.utf8).write(to: home.appendingPathComponent("desktop-observed-account"), options: .atomic)
        let app = NSApplication.shared, delegate = FixtureDelegate()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
