import Foundation
import XCTest
@testable import DefectDashCore

/// Canned Asana answers; records which task gids were asked for stories.
final class FakeAsana: AsanaAPI, @unchecked Sendable {
    let me = AsanaUserRef(gid: "100", name: "Dev One")
    let tasks: [AsanaTask]
    let stories: [String: [AsanaStory]]
    let titles: [String: String]
    let lock = NSLock()
    private(set) var storyRequests: [String] = []

    init(tasks: [AsanaTask], stories: [String: [AsanaStory]] = [:], titles: [String: String] = [:]) {
        self.tasks = tasks
        self.stories = stories
        self.titles = titles
    }

    func me() async throws -> AsanaUserRef { me }
    func openTasks(inSection section: String) async throws -> [AsanaTask] { tasks }
    func stories(forTask gid: String) async throws -> [AsanaStory] {
        lock.withLock { storyRequests.append(gid) }
        return stories[gid] ?? []
    }
    func taskName(gid: String) async throws -> String {
        guard let title = titles[gid] else { throw AsanaError.http(404, "no such task") }
        return title
    }
}

/// A git that answers every command with an empty repo-like response.
struct FakeGit: GitRunning {
    func run(_ args: [String], in dir: URL) async throws -> String {
        switch args.first {
        case "status": return "# branch.oid abc\n# branch.head main\n"
        case "log": return "1793700000\tdev@example.com\tinit\n"
        case "config": return "dev@example.com\n"
        default: return ""
        }
    }
}

final class RefreshPipelineTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "defectdash-pipeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Sys/fix/bug-101/.git"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func task(_ gid: String, _ name: String, awaiting: String? = "Vendor", dependents: [String] = []) -> AsanaTask {
        AsanaTask(gid: gid, name: name, notes: "", assignee: AsanaUserRef(gid: "100", name: "Dev One"), dueOn: nil,
                  modifiedAt: Date(), permalinkUrl: nil,
                  customFields: [AsanaCustomField(name: "Status", displayValue: "3 · In progress"),
                                 AsanaCustomField(name: "Awaiting", displayValue: awaiting)],
                  dependents: dependents.map(AsanaDependentRef.init))
    }

    func testRunJoinsDefectsAndWorktrees() async throws {
        let other = AsanaStory(gid: "s1", createdAt: Date(), createdBy: AsanaUserRef(gid: "200", name: "Manager"),
                               type: "comment", resourceSubtype: "comment_added", text: "please look")
        let asana = FakeAsana(tasks: [task("t1", "Follow up of BUG-101", dependents: ["src1"]), task("t2", "Follow up of BUG-9")],
                              stories: ["t1": [other]], titles: ["src1": "[BUG-101] Save drops an ingredient"])
        let pipeline = RefreshPipeline(api: { _ in asana }, git: FakeGit())
        let board = BoardConfig(awaitingLabels: AwaitingLabels(ours: "Vendor", theirs: "Client"))
        let result = try await pipeline.run(token: "tok", sectionGid: "S", worktreesRoot: root, matchSystems: ["Sys"], board: board)

        XCTAssertEqual(result.me.name, "Dev One")
        XCTAssertEqual(result.items.count, 2)
        let bug101 = try XCTUnwrap(result.items.first { $0.defect.bugNumber == 101 })
        XCTAssertEqual(bug101.defect.title, "[BUG-101] Save drops an ingredient")
        XCTAssertEqual(bug101.worktrees.map(\.relativePath), ["fix/bug-101"])
        XCTAssertEqual(bug101.group, .needsYou)
        let bug9 = try XCTUnwrap(result.items.first { $0.defect.bugNumber == 9 })
        XCTAssertTrue(bug9.worktrees.isEmpty)
        XCTAssertEqual(bug9.group, .yoursInHand)
        XCTAssertEqual(Set(asana.storyRequests), ["t1", "t2"])
        XCTAssertEqual(result.timings.map(\.phase).count, 3)
        XCTAssertTrue(result.otherWorktrees.isEmpty)
    }

    func testMissingSourceTitleFallsBackToTaskName() async throws {
        let asana = FakeAsana(tasks: [task("t1", "Follow up of BUG-1", dependents: ["missing"])])
        let pipeline = RefreshPipeline(api: { _ in asana }, git: FakeGit())
        let result = try await pipeline.run(token: "tok", sectionGid: "S", worktreesRoot: root, matchSystems: [], board: .default)
        XCTAssertEqual(result.items.first?.defect.title, "Follow up of BUG-1")
    }

    func testTokenSourceOrder() throws {
        let file = root.appending(path: "token.txt")
        try "  from-file \n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(try TokenSource.resolve(keychain: { "kc" }, environment: ["ASANA_PAT": "env"], tokenFile: file.path), "kc")
        XCTAssertEqual(try TokenSource.resolve(keychain: { nil }, environment: ["ASANA_PAT": " env "], tokenFile: file.path), "env")
        XCTAssertEqual(try TokenSource.resolve(keychain: { "" }, environment: [:], tokenFile: file.path), "from-file")
        XCTAssertNil(try TokenSource.resolve(keychain: { nil }, environment: [:], tokenFile: nil))
    }

    func testTokenSourceKeychainErrorFallsThrough() throws {
        struct Boom: Error {}
        XCTAssertEqual(try TokenSource.resolve(keychain: { throw Boom() }, environment: ["ASANA_PAT": "env"], tokenFile: nil), "env")
        XCTAssertThrowsError(try TokenSource.resolve(keychain: { nil }, environment: [:], tokenFile: "/nonexistent/token"))
    }
}
