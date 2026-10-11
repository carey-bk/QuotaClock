import AppKit
import Sparkle

/// Run in a disposable .app with test feed/build metadata. No downloads or installs.
final class Probe: NSObject, SPUUpdaterDelegate {
    let comparison = ReleaseVersionComparison()
    func versionComparator(for updater: SPUUpdater) -> (any SUVersionComparison)? { comparison }
    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) { comparison.load(appcast.items) }
    func bestValidUpdate(in appcast: SUAppcast, for updater: SPUUpdater) -> SUAppcastItem? { comparison.best(in: appcast) }
    var controller: SPUStandardUpdaterController!
    func run() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        controller.startUpdater()
        controller.updater.checkForUpdateInformation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { print("TIMEOUT"); exit(2) }
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        print("UPDATE \(item.versionString)"); exit(0)
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        print("CURRENT"); exit(0)
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        print("ERROR \((error as NSError).code)"); exit(1)
    }
}
@main struct Main {
    static func main() {
        let application = NSApplication.shared
        let probe = Probe()
        probe.run()
        withExtendedLifetime(probe) { application.run() }
    }
}
