import Foundation
import XCTest
@testable import DefectDashCore

final class SettingsTests: XCTestCase {
    var suite: String!
    var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testDefaults() {
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.projectGid, "")
        XCTAssertEqual(settings.sectionGid, "")
        XCTAssertEqual(settings.worktreesRoot, URL(fileURLWithPath: NSHomeDirectory()).appending(path: "src/wtrees", directoryHint: .isDirectory))
        XCTAssertEqual(settings.matchSystems, [])
        XCTAssertEqual(settings.refreshMinutes, 5)
        XCTAssertFalse(settings.hideDimmed)
        XCTAssertEqual(settings.ourSideLabel, "")
        XCTAssertEqual(settings.theirSideLabel, "")
        XCTAssertEqual(settings.awaitingLabels, .none)
        XCTAssertEqual(settings.terminalBundleID, "com.apple.Terminal")
        settings.terminalBundleID = "net.kovidgoyal.kitty"
        XCTAssertEqual(Settings(defaults: defaults).terminalBundleID, "net.kovidgoyal.kitty")
    }

    func testRefreshClamped() {
        let settings = Settings(defaults: defaults)
        settings.refreshMinutes = 99
        XCTAssertEqual(settings.refreshMinutes, 30)
        settings.refreshMinutes = 0
        XCTAssertEqual(settings.refreshMinutes, 1)
        settings.refreshMinutes = 7
        XCTAssertEqual(Settings(defaults: defaults).refreshMinutes, 7)
        XCTAssertEqual(defaults.integer(forKey: "dd.refreshMinutes"), 7)
    }

    func testBoardConfigRoundTrip() {
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.board, .default)
        let custom = BoardConfig(bugPrefix: "TKT", statusField: "Stage", awaitingField: "Ball with",
                                 classificationField: "Kind", sprintField: "Iteration",
                                 awaitingLabels: AwaitingLabels(ours: "Us", theirs: "Them"),
                                 closedFromStatus: 7, retestStatus: 5, relayPattern: "^X (.+?)\n")
        settings.board = custom
        XCTAssertEqual(Settings(defaults: defaults).board, custom)
        XCTAssertEqual(Settings(defaults: defaults).ourSideLabel, "Us")
    }

    func testRoundTripAndTrimming() {
        let settings = Settings(defaults: defaults)
        settings.sectionGid = " 42 "
        settings.matchSystems = [" Alpha ", "", "Beta"]
        settings.ourSideLabel = " Vendor "
        settings.theirSideLabel = "Client"
        settings.worktreesRoot = URL(fileURLWithPath: "/tmp/wt", isDirectory: true)
        let again = Settings(defaults: defaults)
        XCTAssertEqual(again.sectionGid, "42")
        XCTAssertEqual(again.matchSystems, ["Alpha", "Beta"])
        XCTAssertEqual(again.awaitingLabels, AwaitingLabels(ours: "Vendor", theirs: "Client"))
        XCTAssertEqual(again.worktreesRoot.path, "/tmp/wt")
    }
}
