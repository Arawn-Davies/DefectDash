# Terminal UI implementation plan

**Goal:** a `defectdash` terminal front end sharing all logic with the macOS app.

**Spec:** `docs/2026-11-09-terminal-ui-design.md`

**Constraints:** Swift 6 language mode, no third-party packages, Asana GET-only,
token never printed. Tests via `swift test`.

## Tasks

### Task 1: RefreshPipeline and TokenSource in Core
- `Sources/DefectDashCore/TokenSource.swift`: `public enum TokenSource { public static func resolve(keychain: () throws -> String?, environment: [String: String], tokenFile: String?) throws -> String? }` order: keychain → `ASANA_PAT` → file (trimmed).
- `Sources/DefectDashCore/RefreshPipeline.swift`:
  ```swift
  public struct RefreshResult: Sendable { items, otherWorktrees, me, timings: [(phase: String, seconds: TimeInterval)] }
  public enum RefreshError: Error { case noToken, noSection }
  public struct RefreshPipeline: Sendable {
      public init(api: @Sendable (String) -> any AsanaAPI = { AsanaClient(pat: $0) }, git: GitRunning = ProcessGitRunner(), calendar: Calendar = .current)
      public func run(token: String, sectionGid: String, worktreesRoot: URL, matchSystems: Set<String>, board: BoardConfig) async throws -> RefreshResult
  }
  ```
- Tests (`RefreshPipelineTests`): fake `AsanaAPI` + fake `GitRunning` → items grouped, `me` set, timings has 3 phases; `TokenSource` order and trimming (4 tests).
- `AppModel.refresh()` and `--once` call the pipeline; behaviour unchanged (62 existing tests stay green).

### Task 2: Terminal and key parsing
- `Sources/DefectDashTUI/Terminal.swift`: raw mode, alt screen, size, write, restore; `Sources/DefectDashTUI/Keys.swift`: `enum Key { char(Character), up, down, left, right, pageUp, pageDown, home, end, enter, escape, backspace, ctrlC, unknown }`, `KeyParser.parse(_ bytes: [UInt8]) -> [Key]` (CSI arrows, `\e[5~`, `\e[6~`, `\e[H`/`\e[F`/`\e[1~`/`\e[4~`, lone ESC, UTF-8 chars).
- Tests (`KeyParserTests`): arrows, page keys, lone escape vs escape sequence, utf-8 multibyte, ctrl-c (5 tests).

### Task 3: Screen buffer and text utilities
- `Screen.swift`: `struct Cell`, `final class Screen { init(cols:rows:); put(x:y:text:style:); fill; render() -> String }` (clipping, styles → SGR, minimal runs).
- `TextLayout.swift`: `truncate(_:width:)` with `…`, `wrap(_:width:) -> [String]` word-wrap with hard break, display width via `Character` count (ASCII/BMP; wide glyphs left to builder).
- Tests (`TextLayoutTests`, `ScreenTests`): truncate exact/short/long, wrap paragraph, clipping at edges, render contains text (6 tests).

### Task 4: UI state and renderers
- `UIState.swift`: `struct UIState { items, otherWorktrees, me, lastRefreshed, isRefreshing, banner, selectedIndex, focus(.list/.detail/.filter/.help), detailScroll, listScroll, filter, hideDimmed, showOtherWorktrees }`, `visibleRows: [Row]` (`.header(Tier,count)`, `.item(WorkItem)`, `.other(Worktree)`, `.otherHeader(count)`), `moveSelection(by:)`, `jump(to tier:)`, `apply(key:) -> Command?` (Command: refresh, openAsana, finder, terminal, copy, quit, toggleDimmed, none).
- `Render.swift`: `Render.frame(state:cols:rows:palette:) -> Screen` (title, list, detail via `DetailText.lines(for: WorkItem, width:) -> [StyledLine]`, status, hints, help overlay, too-small message).
- Tests (`UIStateTests`, `RenderTests`): selection skips headers; filter narrows; hideDimmed hides tiers 4–6; `1`–`6` jumps; frame at 80×24 contains group header and selected bug; detail lines include Expected/Actual (8 tests).

### Task 5: Main loop, actions, packaging
- `main.swift`: args (`--token-file`, `--help`), settings, token via `TokenSource`, `Terminal` setup, `AsyncStream<Event>` (keys thread, SIGWINCH via `DispatchSource`, timer, refresh completion), loop: apply key → command → run (`open`, `open -R`, `open -b`, `pbcopy` via `Process`), redraw.
- Makefile: `tui` (release build), `install-tui` (copy to `/usr/local/bin/defectdash` or `~/bin`), `run-tui`.
- `scripts/build-app.sh`: also copy the `defectdash` binary into `build/` for the release zip.
- README: "Terminal UI" section (keys, SSH token options).
- Verify: `swift test` all green; run `defectdash` in kitty and in Terminal.app; resize; `d`, `/`, `1`–`6`, `o`, `t`.
