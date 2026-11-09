import Foundation
import DefectDashCore

struct StyledLine {
    var text: String
    var style: Style = .plain
}

/// Builds the right-hand pane as wrapped, styled lines.
enum DetailText {
    static func lines(for item: WorkItem, width: Int, now: Date = Date()) -> [StyledLine] {
        let d = item.defect
        let w = max(10, width)
        var out: [StyledLine] = []

        func wrapped(_ text: String, style: Style = .plain, indent: Int = 0) {
            let pad = String(repeating: " ", count: indent)
            for line in TextLayout.wrap(text, width: w - indent) {
                out.append(StyledLine(text: pad + line, style: style))
            }
        }
        func section(_ title: String) {
            if !out.isEmpty { out.append(StyledLine(text: "")) }
            out.append(StyledLine(text: title, style: .fg(.cyan, bold: true)))
        }

        // Header
        out.append(StyledLine(text: TextLayout.truncate("\(TUIFormat.bug(d.bugNumber))  \(d.title)", width: w), style: .bold))
        let tags = item.flags.labels + (item.needsYou ? ["NEEDS YOU"] : [])
        if !tags.isEmpty { wrapped(tags.joined(separator: "  "), style: .fg(.red, bold: true)) }
        var fields: [String] = []
        if let s = d.statusLabel { fields.append("Status \(s)") }
        fields.append("Awaiting \(d.awaitingLabel ?? "unset")")
        fields.append("Assignee \(d.assignee?.name ?? "unassigned")")
        if let due = d.dueOn { fields.append("Due \(TUIFormat.day(due))") }
        if let c = d.classification { fields.append("Classification \(c)") }
        if let s = d.sprint { fields.append("Sprint \(s)") }
        if let p = d.notes.priority { fields.append("Priority \(p)") }
        fields.append("Group \(item.group.rawValue). \(item.group.title)")
        wrapped(fields.joined(separator: "   "), style: .dimmed)
        if let link = d.permalink { wrapped(link, style: .fg(.blue)) }

        // Worktrees
        section(item.worktrees.isEmpty ? "Worktrees: none matched" : "Worktrees")
        for wt in item.worktrees {
            let primary = wt.id == item.primaryWorktree?.id ? "  (primary)" : ""
            wrapped(TextLayout.truncate(wt.path.path, width: w) + primary, style: .fg(.yellow))
            for repo in [wt.host] + wt.submodules {
                let commit = repo.lastCommitSubject.map { " · \($0)" } ?? ""
                let when = repo.lastCommitAt.map { " \(TUIFormat.dateTime($0))" } ?? ""
                wrapped("\(repo.label)  \(repo.branch ?? "detached")  \(TUIFormat.repoSummary(repo, now: now))\(when)\(commit)",
                        style: repo.error == nil ? .plain : .fg(.red), indent: 2)
            }
        }

        // Report
        section("Report")
        let n = d.notes
        let parsed: [(String, String?)] = [
            ("Expected result", n.expected), ("Actual result", n.actual), ("Steps to reproduce", n.steps),
            ("Environment", n.environment), ("Browser / device", n.browser), ("Raised by", n.raisedBy),
        ]
        if parsed.allSatisfy({ $0.1 == nil }) {
            if n.raw.isEmpty { wrapped("No description.", style: .dimmed) } else { wrapped(n.raw) }
        } else {
            for (label, value) in parsed {
                guard let value else { continue }
                out.append(StyledLine(text: label, style: .fg(.gray, bold: true)))
                wrapped(value, indent: 2)
            }
        }

        // Activity
        section(d.events.isEmpty ? "Activity: none" : "Activity")
        for event in d.events {
            let stamp = TUIFormat.dateTime(event.at)
            switch event.kind {
            case let .comment(author, text, viaRelay):
                let who = viaRelay ? "\(author) (relayed by \(event.byName ?? "?"))" : author
                out.append(StyledLine(text: TextLayout.truncate("\(event.isMine ? "› " : "")\(who)  \(stamp)", width: w),
                                      style: event.isMine ? .fg(.green, bold: true) : .bold))
                wrapped(text, indent: 2)
                out.append(StyledLine(text: ""))
            default:
                wrapped("\(stamp)  \(event.byName ?? "Asana")  \(TUIFormat.describe(event.kind))", style: .dimmed)
            }
        }
        return out
    }
}

enum TUIFormat {
    static func bug(_ n: Int?) -> String { n.map { "BUG-\($0)" } ?? "—" }

    static func shortAge(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        case ..<(14 * 86_400): return "\(Int(seconds / 86_400))d"
        default: return "\(Int(seconds / (7 * 86_400)))w"
        }
    }

    static func day(_ date: Date) -> String { date.formatted(.dateTime.day().month(.abbreviated)) }
    static func dateTime(_ date: Date) -> String { date.formatted(.dateTime.day().month(.abbreviated).hour().minute()) }

    static func repoSummary(_ repo: RepoState, now: Date = Date()) -> String {
        var parts: [String] = []
        if repo.dirty { parts.append("●") }
        if let a = repo.ahead, let b = repo.behind { parts.append("+\(a)/-\(b)") } else { parts.append("no upstream") }
        if let at = repo.lastCommitAt { parts.append(shortAge(at, now: now)) }
        if repo.error != nil { parts.append("git error") }
        return parts.joined(separator: " ")
    }

    static func describe(_ kind: ActivityKind) -> String {
        switch kind {
        case let .comment(author, text, viaRelay): "\(author)\(viaRelay ? " (relayed)" : ""): \(text)"
        case let .awaitingChanged(from, to): "Awaiting: \(from ?? "unset") → \(to ?? "unset")"
        case let .defectStatusChanged(from, to): "Status: \(from.map(String.init) ?? "unset") → \(to.map(String.init) ?? "unset")"
        case .assigned: "assigned"
        case .attachment: "attachment added"
        case let .other(subtype): subtype.replacingOccurrences(of: "_", with: " ")
        }
    }

    /// One-letter tag markers for the list column.
    static func markers(_ item: WorkItem) -> String {
        var s = ""
        if item.needsYou { s += "!" }
        if item.flags.contains(.retest) { s += "R" }
        if item.flags.contains(.expectedBehaviour) { s += "E" }
        if item.flags.contains(.overdue) { s += "O" }
        if item.flags.contains(.bounced) { s += "B" }
        if item.flags.contains(.noWorktree) { s += "W" }
        return s
    }

    static func tierColor(_ tier: Tier) -> Color {
        switch tier {
        case .needsYou: .red
        case .yoursInHand: .orange
        case .unassigned: .yellow
        case .someoneElses, .withThem, .closedOnBoard: .gray
        }
    }
}
