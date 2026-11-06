import AppKit
import Foundation
import Observation
import DefectDashCore

@MainActor @Observable
final class AppModel {
    var items: [WorkItem] = []
    var otherWorktrees: [Worktree] = []
    var lastRefreshed: Date?
    var isRefreshing = false
    var banner: String?
    var needsSettings = false   // set on 401 or missing PAT
    var settingsRequests = 0    // bumped by the menu bar "Settings…" item; the window opens the sheet on change
    var me: AsanaUserRef?
    /// Wall-clock seconds per phase of the last refresh, for the `--once` diagnostic.
    var lastTimings: [(phase: String, seconds: TimeInterval)] = []

    let settings: Settings
    let keychain: KeychainStore
    private let git: GitRunning
    private var timer: Task<Void, Never>?

    init(settings: Settings = .shared, keychain: KeychainStore = KeychainStore(), git: GitRunning = ProcessGitRunner()) {
        self.settings = settings
        self.keychain = keychain
        self.git = git
    }

    var needsYouCount: Int { items.filter(\.needsYou).count }

    /// First refresh now, then one every `settings.refreshMinutes`. Calling it again restarts the timer.
    func start() {
        timer?.cancel()
        timer = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refresh()
                let minutes = self.settings.refreshMinutes
                try? await Task.sleep(for: .seconds(minutes * 60))
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        needsSettings = false   // re-raised below if the token or section is still missing/rejected
        defer { isRefreshing = false }

        let pat: String?
        do {
            pat = try keychain.load()
        } catch {
            banner = "Keychain: \(error)"
            needsSettings = true
            return
        }
        guard let pat, !pat.isEmpty else {
            banner = "No Asana token stored. Add one in Settings."
            needsSettings = true
            return
        }

        let sectionGid = settings.sectionGid
        guard !sectionGid.isEmpty else {
            banner = "No Asana section configured. Set the section gid in Settings."
            needsSettings = true
            return
        }
        let client = AsanaClient(pat: pat)
        let root = settings.worktreesRoot
        let systems = Set(settings.matchSystems)
        let board = settings.board
        let git = self.git

        var timings: [(phase: String, seconds: TimeInterval)] = []
        var mark = Date()
        func lap(_ phase: String) {
            timings.append((phase, Date().timeIntervalSince(mark)))
            mark = Date()
        }
        defer { lastTimings = timings }

        do {
            let me = try await client.me()
            self.me = me
            let tasks = try await client.openTasks(inSection: sectionGid)
            let defects = try await Concurrent.map(tasks, limit: 8) { task -> Defect in
                async let stories = client.stories(forTask: task.gid)
                var sourceTitle: String? = nil
                if let source = task.dependents?.first?.gid {
                    sourceTitle = try? await client.taskName(gid: source)
                }
                return Defect(task: task, stories: try await stories, sourceTitle: sourceTitle, myGid: me.gid,
                              board: board)
            }
            lap("asana")

            let scanner = WorktreeScanner(git: git, maxConcurrent: 8, bugPrefix: board.bugPrefix)
            let hosts = await scanner.scanHosts(root: root)
            lap("git hosts (\(hosts.count))")
            let worktrees = await scanner.enrich(hosts) { wt in
                (wt.bugNumber != nil && (systems.isEmpty || systems.contains(wt.system)))
                    || wt.host.dirty || (wt.host.ahead ?? 0) > 0
            }
            lap("git submodules (\(worktrees.filter { !$0.submodules.isEmpty }.count) worktrees)")

            let context = RankingContext(myGid: me.gid, matchSystems: systems, board: board)
            let ranked = Ranking.rank(defects: defects, worktrees: worktrees, context: context)
            let matched = Set(ranked.flatMap { $0.worktrees.map(\.id) })
            items = ranked
            otherWorktrees = Ranking.otherWorktrees(worktrees, matched: matched)
            lastRefreshed = Date()
            banner = nil
            needsSettings = false
        } catch AsanaError.unauthorized {
            needsSettings = true
            banner = "Asana rejected the token (401)"
        } catch let error as AsanaError {
            banner = Self.describe(error)
        } catch {
            banner = error.localizedDescription
        }
    }

    private static func describe(_ error: AsanaError) -> String {
        switch error {
        case .unauthorized: "Asana rejected the token (401)"
        case let .rateLimited(retryAfter): "Asana rate limit (429), retry after \(retryAfter)s"
        case let .http(status, message): "Asana error \(status): \(message)"
        case let .transport(message): "Network: \(message)"
        }
    }

    // MARK: - Worktree actions

    func openInFinder(_ wt: Worktree) {
        NSWorkspace.shared.activateFileViewerSelecting([wt.path])
    }

    func openInTerminal(_ wt: Worktree) {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([wt.path], withApplicationAt: terminal, configuration: configuration) { _, error in
            if let error {
                Task { @MainActor in self.banner = "Terminal: \(error.localizedDescription)" }
            }
        }
    }

    func copyPath(_ wt: Worktree) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(wt.path.path, forType: .string)
    }
}
