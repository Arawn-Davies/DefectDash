import Foundation

public struct RefreshResult: Sendable {
    public let items: [WorkItem]
    public let otherWorktrees: [Worktree]
    public let me: AsanaUserRef
    public let timings: [(phase: String, seconds: TimeInterval)]

    public init(items: [WorkItem], otherWorktrees: [Worktree], me: AsanaUserRef,
                timings: [(phase: String, seconds: TimeInterval)]) {
        self.items = items
        self.otherWorktrees = otherWorktrees
        self.me = me
        self.timings = timings
    }
}

/// One full refresh: Asana → defects → worktrees → ranking. Shared by the macOS app and the terminal UI.
public struct RefreshPipeline: Sendable {
    public typealias APIFactory = @Sendable (_ token: String) -> any AsanaAPI

    private let api: APIFactory
    private let git: GitRunning
    private let calendar: Calendar
    private let maxConcurrent: Int

    public init(api: @escaping APIFactory = { AsanaClient(pat: $0) }, git: GitRunning = ProcessGitRunner(),
                calendar: Calendar = .current, maxConcurrent: Int = 8) {
        self.api = api
        self.git = git
        self.calendar = calendar
        self.maxConcurrent = maxConcurrent
    }

    public func run(token: String, sectionGid: String, worktreesRoot: URL, matchSystems: Set<String>,
                    board: BoardConfig) async throws -> RefreshResult {
        var timings: [(phase: String, seconds: TimeInterval)] = []
        var mark = Date()
        func lap(_ phase: String) {
            timings.append((phase, Date().timeIntervalSince(mark)))
            mark = Date()
        }

        let client = api(token)
        let me = try await client.me()
        let tasks = try await client.openTasks(inSection: sectionGid)
        let calendar = self.calendar
        let defects = try await Concurrent.map(tasks, limit: maxConcurrent) { task -> Defect in
            async let stories = client.stories(forTask: task.gid)
            var sourceTitle: String? = nil
            if let source = task.dependents?.first?.gid {
                sourceTitle = try? await client.taskName(gid: source)
            }
            return Defect(task: task, stories: try await stories, sourceTitle: sourceTitle, myGid: me.gid,
                          board: board, calendar: calendar)
        }
        lap("asana")

        let scanner = WorktreeScanner(git: git, maxConcurrent: maxConcurrent, bugPrefix: board.bugPrefix)
        let hosts = await scanner.scanHosts(root: worktreesRoot)
        lap("git hosts (\(hosts.count))")
        let worktrees = await scanner.enrich(hosts) { wt in
            (wt.bugNumber != nil && (matchSystems.isEmpty || matchSystems.contains(wt.system)))
                || wt.host.dirty || (wt.host.ahead ?? 0) > 0
        }
        lap("git submodules (\(worktrees.filter { !$0.submodules.isEmpty }.count) worktrees)")

        let context = RankingContext(myGid: me.gid, matchSystems: matchSystems, board: board, calendar: calendar)
        let ranked = Ranking.rank(defects: defects, worktrees: worktrees, context: context)
        let matched = Set(ranked.flatMap { $0.worktrees.map(\.id) })
        return RefreshResult(items: ranked, otherWorktrees: Ranking.otherWorktrees(worktrees, matched: matched),
                             me: me, timings: timings)
    }
}
