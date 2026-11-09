import Foundation
import DefectDashCore

/// Pure function from state and size to a Screen.
enum Render {
    static let minCols = 60
    static let minRows = 16

    static func frame(state: UIState, cols: Int, rows: Int, now: Date = Date()) -> Screen {
        let screen = Screen(cols: cols, rows: rows)
        guard cols >= minCols, rows >= minRows else {
            screen.put(x: 0, y: 0, "Terminal too small (need \(minCols)x\(minRows))", style: .bold)
            return screen
        }

        let leftWidth = min(64, max(36, cols * 38 / 100))
        let rightX = leftWidth + 1
        let rightWidth = cols - rightX
        let bodyTop = 2
        let bodyBottom = rows - 3   // exclusive; rows-3 = status, rows-2 = hints... plus separator at rows-3
        let bodyHeight = bodyBottom - bodyTop

        drawTitle(state, screen: screen, cols: cols, now: now)
        screen.put(x: 0, y: 1, String(repeating: "─", count: leftWidth) + "┬" + String(repeating: "─", count: rightWidth), style: .dimmed)
        for y in bodyTop..<bodyBottom { screen.put(x: leftWidth, y: y, "│", style: .dimmed) }
        screen.put(x: 0, y: bodyBottom, String(repeating: "─", count: leftWidth) + "┴" + String(repeating: "─", count: rightWidth), style: .dimmed)

        drawList(state, screen: screen, x: 0, y: bodyTop, width: leftWidth, height: bodyHeight, now: now)
        drawDetail(state, screen: screen, x: rightX, y: bodyTop, width: rightWidth, height: bodyHeight, now: now)
        drawStatus(state, screen: screen, y: rows - 2, cols: cols)
        drawHints(state, screen: screen, y: rows - 1, cols: cols)
        if state.focus == .help { drawHelp(screen: screen, cols: cols, rows: rows) }
        return screen
    }

    // MARK: Pieces

    private static func drawTitle(_ s: UIState, screen: Screen, cols: Int, now: Date) {
        var parts = ["DefectDash"]
        if let me = s.me?.name { parts.append(me) }
        if let at = s.lastRefreshed { parts.append("refreshed \(TUIFormat.shortAge(at, now: now)) ago") } else { parts.append("not refreshed yet") }
        parts.append("needs you \(s.items.filter(\.needsYou).count)")
        let left = " " + parts.joined(separator: " · ")
        let right = "every \(s.refreshMinutes)m "
        screen.fill(x: 0, y: 0, width: cols, height: 1, style: Style(reverse: true))
        screen.put(x: 0, y: 0, TextLayout.truncate(left, width: cols - right.count - 1), style: Style(bold: true, reverse: true))
        screen.put(x: cols - right.count, y: 0, right, style: Style(reverse: true))
    }

    private static func drawList(_ s: UIState, screen: Screen, x: Int, y: Int, width: Int, height: Int, now: Date) {
        let rows = s.rows
        guard height > 0 else { return }
        // Keep the selected row visible.
        var scroll = s.listScroll
        if let sel = s.selectedRowIndex {
            if sel < scroll { scroll = sel }
            if sel >= scroll + height { scroll = sel - height + 1 }
        }
        scroll = max(0, min(scroll, max(0, rows.count - height)))

        for (i, row) in rows.dropFirst(scroll).prefix(height).enumerated() {
            let yy = y + i
            switch row {
            case let .header(tier, count):
                let text = TextLayout.pad(" \(tier.rawValue) \(tier.title) (\(count))", width: width)
                screen.put(x: x, y: yy, text, style: Style(fg: TUIFormat.tierColor(tier), bold: true, dim: tier.isDimmed))
            case let .item(item):
                let selected = item.id == s.selectedItem?.id
                let markers = TextLayout.pad(TUIFormat.markers(item), width: 4)
                let branch = item.primaryWorktree?.branch ?? (item.worktrees.isEmpty ? "" : item.worktrees[0].relativePath)
                let bug = TextLayout.pad(TUIFormat.bug(item.defect.bugNumber), width: 8)
                let lead = "\(bug) \(markers) "
                let branchCol = TextLayout.pad(branch, width: min(16, max(0, width - lead.count - 12)))
                let rest = width - lead.count - branchCol.count - 2
                let title = TextLayout.truncate(item.defect.title, width: max(0, rest))
                let line = TextLayout.pad(lead + branchCol + " " + title, width: width - 1)
                var style = Style(dim: item.group.isDimmed)
                if selected { style.reverse = true; style.dim = false; style.bold = true }
                screen.put(x: x, y: yy, selected ? "▌" : " ", style: Style(fg: TUIFormat.tierColor(item.group), bold: true))
                screen.put(x: x + 1, y: yy, line, style: style)
            case let .otherHeader(count):
                let arrow = s.showOtherWorktrees ? "▾" : "▸"
                screen.put(x: x, y: yy, TextLayout.pad(" \(arrow) Other worktrees (\(count))  [O]", width: width), style: .fg(.gray, bold: true))
            case let .other(wt):
                let text = " \(wt.system)/\(wt.relativePath)  \(TUIFormat.repoSummary(wt.host, now: now))"
                screen.put(x: x, y: yy, TextLayout.pad(text, width: width), style: .dimmed)
            }
        }
        if rows.count <= 1, !s.isRefreshing {
            screen.put(x: x + 1, y: y + 1, TextLayout.truncate(s.banner == nil ? "No open defects." : "Nothing loaded yet.", width: width - 2), style: .dimmed)
        }
    }

    private static func drawDetail(_ s: UIState, screen: Screen, x: Int, y: Int, width: Int, height: Int, now: Date) {
        guard let item = s.selectedItem else {
            screen.put(x: x + 1, y: y + 1, "Select a defect with j/k; Enter focuses this pane.", style: .dimmed)
            return
        }
        let lines = DetailText.lines(for: item, width: width - 2, now: now)
        let maxScroll = max(0, lines.count - height)
        let scroll = min(s.detailScroll, maxScroll)
        for (i, line) in lines.dropFirst(scroll).prefix(height).enumerated() {
            screen.put(x: x + 1, y: y + i, line.text, style: line.style)
        }
        if lines.count > height {
            let pct = maxScroll == 0 ? 100 : scroll * 100 / maxScroll
            let marker = " \(pct)% "
            screen.put(x: x + width - marker.count - 1, y: y + height - 1, marker, style: .dimmed)
        }
        if s.focus == .detail {
            screen.put(x: x, y: y, "▎", style: .fg(.cyan, bold: true))
        }
    }

    private static func drawStatus(_ s: UIState, screen: Screen, y: Int, cols: Int) {
        var text: String
        var style: Style = .dimmed
        if s.focus == .filter {
            text = " filter: \(s.filter)▏"
            style = .bold
        } else if let banner = s.banner {
            text = " ⚠ \(banner)"
            style = .fg(.red, bold: true)
        } else if s.isRefreshing {
            text = " ⟳ refreshing…"
        } else if !s.filter.isEmpty {
            text = " filter: \(s.filter)  (Esc clears)"
        } else {
            text = " \(s.visibleItems.count) defects shown\(s.hideDimmed ? ", dimmed groups hidden" : "")"
        }
        screen.put(x: 0, y: y, TextLayout.pad(text, width: cols), style: style)
    }

    private static func drawHints(_ s: UIState, screen: Screen, y: Int, cols: Int) {
        let candidates = [
            " j/k move  Enter detail  1-6 group  / filter  d dimmed  O other  r refresh  o asana  f finder  t term  c copy  ? help  q quit",
            " j/k move  Enter detail  / filter  d dimmed  r refresh  o asana  t term  ? help  q quit",
            " j/k  Enter  / filter  r refresh  ? help  q quit",
        ]
        let hints = candidates.first { $0.count <= cols } ?? candidates[candidates.count - 1]
        screen.put(x: 0, y: y, TextLayout.pad(hints, width: cols), style: .dimmed)
    }

    private static func drawHelp(screen: Screen, cols: Int, rows: Int) {
        let lines = [
            " DefectDash keys ",
            "",
            " j / k, ↓ / ↑      move selection          1–6          jump to group",
            " g / G             first / last            Enter, l, →  focus detail pane",
            " J / K, PgDn/PgUp  scroll detail           h, ←, Esc    back to list",
            " /                 filter by bug or title  d            toggle dimmed groups",
            " O                 toggle other worktrees  r            refresh now",
            " o                 open in Asana           f            reveal in Finder",
            " t                 open in terminal        c            copy worktree path",
            " ?                 this help               q, Ctrl-C    quit",
            "",
            " Esc or ? closes this overlay. ",
        ]
        let w = min(cols - 4, lines.map(\.count).max()! + 2)
        let h = lines.count + 2
        let x0 = (cols - w) / 2, y0 = (rows - h) / 2
        screen.fill(x: x0, y: y0, width: w, height: h, style: Style(reverse: true))
        for (i, line) in lines.enumerated() {
            screen.put(x: x0 + 1, y: y0 + 1 + i, TextLayout.pad(line, width: w - 2), style: Style(bold: i == 0, reverse: true))
        }
    }
}
