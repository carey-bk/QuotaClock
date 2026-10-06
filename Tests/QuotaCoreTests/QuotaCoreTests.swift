import XCTest
@testable import QuotaCore
final class QuotaCoreTests: XCTestCase {
    func testTerminologyAndMultipleWindowsRoundTrip() throws {
        var value = MockProvider.snapshot()
        value.providers[0].limits.append(LimitWindow(id: "spark-weekly", displayName: "Spark Weekly", remainingPercentage: 22))
        let decoded = try JSONDecoder().decode(QuotaSnapshot.self, from: SnapshotStore.encode(value))
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.providers[1].limits[0].displayName, "Session")
        XCTAssertEqual(decoded.providers[0].limits[1].displayName, "Spark Weekly")
    }
    func testPublishLogicalRevisionAndRepair() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let publisher = SnapshotPublisher(shared: SnapshotStore(url: directory.appendingPathComponent("group/snapshot.json")), display: SnapshotStore(url: directory.appendingPathComponent("display/snapshot.json")))
        var snapshot = MockProvider.snapshot()
        try publisher.publish(snapshot)
        try snapshot.setRemaining(providerID: "codex", limitID: "weekly", value: 61)
        try publisher.publish(snapshot)
        XCTAssertEqual(try publisher.shared.read().displayProjection(), try publisher.display.read())
        XCTAssertEqual(try publisher.shared.read().revision, try publisher.display.read().revision)
        try Data("broken".utf8).write(to: publisher.display.url)
        XCTAssertThrowsError(try publisher.display.read())
        try publisher.repairDisplay()
        XCTAssertEqual(try publisher.display.read().revision, snapshot.revision)
    }
    func testInvalidAndFutureDataRejected() throws {
        var value = MockProvider.snapshot()
        XCTAssertThrowsError(try value.setRemaining(providerID: "codex", limitID: "weekly", value: 101))
        value.providers[0].limits[0].remainingPercentage = -1
        XCTAssertThrowsError(try SnapshotStore.encode(value))
        value = MockProvider.snapshot(); value.schemaVersion = 2
        XCTAssertThrowsError(try value.validated())
    }
    func testHeroChangesOnlyOnQuotaChangeAndPinnedWins() throws {
        let initial = Date(timeIntervalSince1970: 10)
        var value = MockProvider.snapshot(at: initial)
        XCTAssertEqual(value.hero?.id, "codex")
        try value.setRemaining(providerID: "claude-code", limitID: "weekly", value: 60, now: initial.addingTimeInterval(10))
        XCTAssertEqual(value.hero?.id, "claude-code")
        try value.setRemaining(providerID: "codex", limitID: "weekly", value: 85, now: initial.addingTimeInterval(20))
        XCTAssertEqual(value.hero?.id, "claude-code")
        value.heroSelection = .pinned(providerID: "codex")
        XCTAssertEqual(value.hero?.id, "codex")
    }
    func testFailedExportKeepsCanonicalCommitAndCanBeRepaired() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blockedParent = directory.appendingPathComponent("blocked")
        try Data("not a directory".utf8).write(to: blockedParent)
        let publisher = SnapshotPublisher(shared: SnapshotStore(url: directory.appendingPathComponent("group/snapshot.json")), display: SnapshotStore(url: blockedParent.appendingPathComponent("snapshot.json")))
        var value = MockProvider.snapshot()
        try value.setRemaining(providerID: "codex", limitID: "weekly", value: 61)
        XCTAssertThrowsError(try publisher.publish(value))
        XCTAssertEqual(try publisher.shared.read(), value)
        try FileManager.default.removeItem(at: blockedParent)
        try publisher.repairDisplay()
        XCTAssertEqual(try publisher.display.read(), value.displayProjection())
    }
    func testConcurrentReadersNeverSeePartialJSON() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(url: directory.appendingPathComponent("snapshot.json"))
        try store.write(MockProvider.snapshot())
        let finished = expectation(description: "Atomic writer")
        DispatchQueue.global().async {
            defer { finished.fulfill() }
            do {
                var value = MockProvider.snapshot()
                for index in 0..<100 {
                    try value.setRemaining(providerID: "codex", limitID: "weekly", value: Double(index))
                    try store.write(value)
                }
            } catch { XCTFail("Writer failed: \(error)") }
        }
        for _ in 0..<200 { XCTAssertNoThrow(try store.read()) }
        wait(for: [finished], timeout: 10)
    }

}
