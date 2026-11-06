# DefectDash

A small native macOS window that joins the open defects in one Asana section
with the git worktrees on your disk, ranks them by urgency, and flags the
ones where the other side has replied since you last acted.

Asana is read-only: the app only ever sends `GET` requests. Git is read with
`rev-parse`, `log`, `status`, `rev-list`, `config` and `submodule foreach`.
Nothing is written to either.

## What it expects

- An Asana section whose open tasks are the defects, named like
  `Follow up of BUG-184` (the number is extracted with `BUG-0*(\d+)`).
- Optional custom fields on those tasks:
  - `Defect Status` with options that start with a number
    (`1 · Submitted` … `4 · Verify / UAT retest`, `5 · Closed`, …).
  - `Awaiting` with one option for your side and one for the other side.
    You tell the app which label is which in Settings.
  - `Classification` (for example `Expected Behaviour`).
  - any field whose name ends in `SPRINT`.
- Task notes in the common "Defect Report" form layout (`Expected result::`,
  `Actual result::`, `Steps to reproduce::`, …). Anything else is shown raw.
- A worktrees root (default `~/src/wtrees`) laid out as
  `<root>/<System>/<anything>/...`, where a directory containing `.git` is a
  worktree. Worktrees are matched to defects by `bug-NNN` in the directory
  path or branch name (`fix/bug-184`, `bug-013/foo`, `fix-bug-004`, …).

## Requirements

- macOS 15 or later, Xcode 27 command-line toolchain (Swift 6.4).
- No third-party packages.

## Build and run

```sh
make test        # unit tests for DefectDashCore
make app         # release build, assembles and signs build/DefectDash.app
make run         # make app, then open the bundle
```

## One-time setup

### 1. Code-signing certificate (recommended)

Ad-hoc signatures change on every build, so the Keychain would ask for
permission to read the Asana token after each rebuild. A self-signed
certificate gives the app a stable identity:

1. Open **Keychain Access** → menu **Keychain Access → Certificate Assistant →
   Create a Certificate…**
2. Name: `DefectDash Dev`. Identity Type: **Self Signed Root**.
   Certificate Type: **Code Signing**. Create.
3. In Keychain Access, find the certificate under *login → My Certificates*,
   open it, expand **Trust**, and set **Code Signing** to **Always Trust**.

`make app` picks the identity up automatically (override with
`SIGN_IDENTITY=... make app`). Without it the build still works, ad-hoc
signed, with a warning.

### 2. Asana personal access token

Either paste the token into **Settings** inside the app (it opens on first
launch), or put it in a file and let the app import it:

```sh
make app
make import-pat PAT_FILE=~/asana-token.txt
```

The binary reads the file itself and stores the token in the login Keychain
(service `io.github.arawn-davies.defectdash`, account `asana-pat`). The token
is never printed, logged or written anywhere else, and it is not part of
this repository.

### 3. Settings

Gear icon in the toolbar (or the menu-bar item):

- Asana token (**Test** calls `/users/me` and shows your name).
- Section gid of the defects list, and optionally the project gid.
- The two `Awaiting` labels: yours and the other side's.
- Worktrees root and, optionally, which systems may match defects
  (empty = all).
- Refresh interval in minutes (1–30, default 5).

## Groups

1. **Needs you** — awaiting your side and the other side has acted since
   your last Asana action or last commit on the matched worktree.
2. **Yours, in hand** — assigned to you, nothing new from the other side.
3. **Unassigned, on our side**
4. **Someone else's** (dimmed)
5. **With the other side** (dimmed)
6. **Closed on the board, still open in Asana** (dimmed)

Tags: `RETEST`, `EXPECTED BEHAVIOUR`, `OVERDUE`, `BOUNCED`, `NO WORKTREE`,
`NEEDS YOU`. Below the groups, "Other worktrees" lists dirty or unpushed
worktrees that matched no defect.

## Diagnostics

`build/DefectDash.app/Contents/MacOS/DefectDash --once` runs one refresh
headlessly and prints the groups, matches, tags and per-phase timings.
