import Darwin
import Foundation
import DefectDashCore

// MARK: - Arguments

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    defectdash — ranked Asana defects × local worktrees, in the terminal

    usage: defectdash [--token-file <path>]

    Reads the same settings as the DefectDash app (defaults domain \(Settings.bundleIdentifier)) and the same
    Keychain token. Token lookup order: Keychain, $\(TokenSource.environmentKey), --token-file.
    Keys: j/k move · Enter detail · 1-6 group · / filter · d dimmed · O other worktrees · z zoom pane
          y copy detail · r refresh · o asana · f finder · t terminal · c copy path · ? help · q quit
    The last refresh is cached in ~/Library/Caches/\(Settings.bundleIdentifier)/ and shown at startup.
    """)
    exit(0)
}
var tokenFile: String? = nil
if let i = arguments.firstIndex(of: "--token-file") {
    guard i + 1 < arguments.count else { FileHandle.standardError.write(Data("--token-file needs a path\n".utf8)); exit(2) }
    tokenFile = arguments[i + 1]
}

let terminal = Terminal()
guard terminal.isTTY else {
    FileHandle.standardError.write(Data("defectdash needs an interactive terminal (stdin and stdout must be a tty)\n".utf8))
    exit(2)
}

let settings = Settings.sharedDomain
let token: String
do {
    guard let resolved = try TokenSource.resolve(keychain: { try KeychainStore().load() },
                                                 environment: ProcessInfo.processInfo.environment, tokenFile: tokenFile) else {
        FileHandle.standardError.write(Data("No Asana token: store one with the DefectDash app, set \(TokenSource.environmentKey), or pass --token-file.\n".utf8))
        exit(2)
    }
    token = resolved
} catch {
    FileHandle.standardError.write(Data("Token: \(error)\n".utf8))
    exit(2)
}
guard !settings.sectionGid.isEmpty else {
    FileHandle.standardError.write(Data("No Asana section configured. Set it in the DefectDash app's Settings (or `defaults write \(Settings.bundleIdentifier) dd.sectionGid <gid>`).\n".utf8))
    exit(2)
}

// MARK: - Actions

/// Runs a command's side effect. Reads the global `state` directly: taking it `inout` here while
/// `startRefresh()` also touches it was a Swift exclusivity violation that aborted the process on `r`.
@MainActor
func perform(_ command: Command) -> Bool {
    switch command {
    case .none: break
    case .quit: return false
    case .refresh: startRefresh()
    case .toggleDimmed: settings.hideDimmed = state.hideDimmed
    case .openAsana:
        if let url = state.selectedItem?.defect.permalink { Shell.run(["/usr/bin/open", url]) }
    case .finder:
        if let wt = state.selectedItem?.primaryWorktree { Shell.run(["/usr/bin/open", "-R", wt.path.path]) }
    case .terminal:
        if let wt = state.selectedItem?.primaryWorktree { Shell.run(["/usr/bin/open", "-b", settings.terminalBundleID, wt.path.path]) }
    case .copyPath:
        if let wt = state.selectedItem?.primaryWorktree { Shell.run(["/usr/bin/pbcopy"], stdin: wt.path.path) }
    case .copyDetail:
        if let item = state.selectedItem {
            let text = DetailText.lines(for: item, width: 100).map(\.text).joined(separator: "\n")
            Shell.run(["/usr/bin/pbcopy"], stdin: text + "\n")
        }
    }
    return true
}

// MARK: - Main loop

let pipeline = RefreshPipeline()
let palette = Palette.detect()
var state = UIState()
state.hideDimmed = settings.hideDimmed
state.refreshMinutes = settings.refreshMinutes
if let cached = RefreshCache.load() { state.applyCache(cached) }   // something on screen before the first refresh
var lastRefreshStarted: Date? = nil

@MainActor
func startRefresh() {
    guard !state.isRefreshing else { return }
    state.isRefreshing = true
    lastRefreshStarted = Date()
    let sectionGid = settings.sectionGid
    let root = settings.worktreesRoot
    let systems = Set(settings.matchSystems)
    let board = settings.board
    let cont = continuation
    Task.detached {
        do {
            let result = try await pipeline.run(token: token, sectionGid: sectionGid, worktreesRoot: root,
                                                matchSystems: systems, board: board)
            cont.yield(.refreshed(.success(result)))
        } catch {
            cont.yield(.refreshed(.failure(error)))
        }
    }
}

@MainActor
func draw() {
    let size = terminal.size
    terminal.write(Render.frame(state: state, cols: size.cols, rows: size.rows).render(palette: palette))
}

terminal.enterRawMode()
defer { terminal.restore() }
let (events, continuation) = EventSources.start()
startRefresh()
draw()

loop: for await event in events {
    switch event {
    case let .keys(keys):
        for key in keys {
            let command = state.apply(key)
            if !perform(command) { break loop }
        }
    case .resize:
        break
    case .tick:
        if let started = lastRefreshStarted, !state.isRefreshing,
           Date().timeIntervalSince(started) >= TimeInterval(settings.refreshMinutes * 60) {
            startRefresh()
        }
    case let .refreshed(result):
        state.isRefreshing = false
        switch result {
        case let .success(r):
            state.applyRefresh(r)
            try? RefreshCache.save(r)
        case .failure(AsanaError.unauthorized): state.banner = "Asana rejected the token (401)"
        case let .failure(e as AsanaError): state.banner = "\(e)"
        case let .failure(e): state.banner = e.localizedDescription
        }
    }
    draw()
}

terminal.restore()
exit(0)
