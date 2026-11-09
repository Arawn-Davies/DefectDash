# DefectDash terminal UI — design

Status: approved in conversation, 2026-11-09.

## Intent

A second front end, `defectdash`, that shows the same ranked defects as the
macOS app inside any terminal: kitty, iTerm2, Terminal.app, or an SSH
session. No GPU, no AppKit, no third-party packages. It shares every piece
of logic with the app through `DefectDashCore`; only presentation differs.

Why: the app's list crashed inside QuartzCore on macOS 26.6, and the author
works in a terminal multiplexer most of the day. A text UI is immune to GPU
driver state and works on a remote machine.

## Goals

- Same groups, tags, worktree matches, report sections and activity as the
  app, from the same settings (UserDefaults domain
  `io.github.arawn-davies.defectdash`) and the same Keychain token.
- Layout modelled on herdr: left column of grouped items, wide right pane
  for the selected item, status strip and key hints at the bottom.
- Keyboard only. Vim-style and arrow keys both work.
- Refresh in the background on the configured interval; the UI never blocks.
- Works over SSH: token can come from the environment or a file when the
  login keychain is locked.

## Non-goals

- Editing settings in the terminal (use the app's Settings sheet or
  `defaults write`); the TUI only reads them.
- Mouse support.
- Writing to Asana.

## Shape

- Executable target `DefectDashTUI`, product `defectdash`, in the same
  package. Pure Swift + Foundation + Darwin (termios, ioctl, signals).
- A `RefreshPipeline` in `DefectDashCore` performs one refresh (token →
  `me` → tasks → stories/titles → defects → worktrees → ranking) and returns
  a `RefreshResult`. Both the app's `AppModel` and the TUI call it.
- `TokenSource` in `DefectDashCore` resolves the token: Keychain, then
  `ASANA_PAT`, then `--token-file <path>`.

## Screen

```
 DefectDash · Arawn Davies · refreshed 2m ago · needs you 7           every 5m
─────────────────────────────────────────┬──────────────────────────────────────
 1 Needs you (7)                         │ BUG-101  Save drops the last ingredient
▌BUG-101 !O   fix/bug-101     Save dr…   │ Status 4 · Retest   Awaiting Vendor
 BUG-102 !ROB fix/bug-102     Upload…   │ Assignee Dev One    Due 26 Oct
 …                                       │
 2 Yours, in hand (0)                    │ Worktrees
 3 Unassigned, on our side (7)           │  fix/bug-101  main ● +1/-0 3d
 …                                       │   engines/core  …
 5 With the other side (9)   [dim]       │
 …                                       │ Report
 ▸ Other worktrees (111)                 │  Expected result …
                                         │ Activity
                                         │  Tester A (relayed) 28 Oct 15:01 …
─────────────────────────────────────────┴──────────────────────────────────────
 ⟳ refreshing…  |  banner text when something failed
 j/k move  Enter detail  1-6 group  / filter  d dimmed  r refresh  o f t c  q quit
```

- Left column width: 38% of columns, clamped to 36…64.
- Tag markers: `!` needs you, `R` retest, `E` expected behaviour, `O`
  overdue, `B` bounced, `W` no worktree. Coloured when the terminal supports
  colour; dimmed groups (4–6) are drawn dim and hidden by `d`.
- The selected row has a `▌` bar in the group colour and reverse video.
- Right pane: wrapped text, scrollable; sections Header, Worktrees (host +
  submodules), Report (parsed sections or raw), Activity (newest first,
  relayed author shown, own comments marked `›`).
- Bottom: a status line (refresh state or the error banner) and a key-hint
  line.

## Keys

| Key | Action |
|-----|--------|
| `j` `k` `↓` `↑` | move selection |
| `g` `G` | first / last row |
| `1`–`6` | jump to group |
| `Enter` `l` `→` | focus the detail pane |
| `h` `←` `Esc` | back to the list (Esc also clears the filter) |
| `J` `K` `PgDn` `PgUp` `Space` | scroll detail |
| `/` | type a filter (bug number or title); `Enter` keeps it, `Esc` clears |
| `d` | toggle dimmed groups (persists to settings) |
| `r` | refresh now |
| `o` | open the task in Asana (`open <url>`) |
| `f` | reveal the primary worktree in Finder (`open -R`) |
| `t` | open the primary worktree in the configured terminal (`open -b <bundle id>`) |
| `c` | copy the primary worktree path (`pbcopy`) |
| `?` | toggle the help overlay |
| `q` `Ctrl-C` | quit |

`o`, `f`, `t`, `c` run on the machine the TUI runs on; over SSH that is the
remote Mac.

## Terminal handling

- Raw mode via `tcsetattr` (restore on exit, including on SIGINT/SIGTERM),
  alternate screen (`\e[?1049h`), hidden cursor, size from `TIOCGWINSZ`,
  redraw on `SIGWINCH`.
- Colour: truecolor when `COLORTERM` is `truecolor`/`24bit`, else 16-colour
  ANSI; `NO_COLOR` disables colour.
- Each frame is rendered into a cell buffer and written in one `write(2)`.
- Minimum size 60×16; below that a one-line message is shown.

## Concurrency

One `@MainActor` loop consumes an `AsyncStream<Event>`: key presses (read
on a dedicated thread), resize, refresh finished, timer tick. Refresh runs
as a detached task using `RefreshPipeline`.

## Left to the builder

Exact colours, wrapping of very long words, how the help overlay looks.
