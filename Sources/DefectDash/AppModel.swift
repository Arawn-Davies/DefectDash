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
    private let pipeline: RefreshPipeline
    private var timer: Task<Void, Never>?

    init(settings: Settings = .shared, keychain: KeychainStore = KeychainStore(), git: GitRunning = ProcessGitRunner()) {
        self.settings = settings
        self.keychain = keychain
        self.pipeline = RefreshPipeline(git: git)
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

        let token: String?
        do {
            token = try keychain.load()
        } catch {
            banner = "Keychain: \(error)"
            needsSettings = true
            return
        }
        guard let token, !token.isEmpty else {
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

        do {
            let result = try await pipeline.run(token: token, sectionGid: sectionGid, worktreesRoot: settings.worktreesRoot,
                                                matchSystems: Set(settings.matchSystems), board: settings.board)
            me = result.me
            items = result.items
            otherWorktrees = result.otherWorktrees
            lastTimings = result.timings
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

    static func describe(_ error: AsanaError) -> String {
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
        let terminal = TerminalApp.resolve(bundleID: settings.terminalBundleID)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
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
