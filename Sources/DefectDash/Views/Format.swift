import Foundation
import SwiftUI
import DefectDashCore

enum Format {
    /// "5m", "3h", "2d", "3w"
    static func shortAge(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        case ..<(14 * 86_400): return "\(Int(seconds / 86_400))d"
        default: return "\(Int(seconds / (7 * 86_400)))w"
        }
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    static func initials(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "—" }
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    static func bug(_ number: Int?) -> String {
        number.map { "BUG-\($0)" } ?? "—"
    }

    /// "● +1/-0" style chip text for one repo state.
    static func repoSummary(_ repo: RepoState) -> String {
        var parts: [String] = []
        if repo.dirty { parts.append("●") }
        if let ahead = repo.ahead, let behind = repo.behind {
            parts.append("+\(ahead)/-\(behind)")
        } else {
            parts.append("no upstream")
        }
        if let at = repo.lastCommitAt { parts.append(shortAge(at)) }
        if repo.error != nil { parts.append("git error") }
        return parts.joined(separator: " ")
    }

    static func groupColor(_ group: Tier) -> Color {
        switch group {
        case .needsYou: .red
        case .yoursInHand: .orange
        case .unassigned: .yellow
        case .someoneElses, .withThem, .closedOnBoard: .gray
        }
    }

    static func describe(_ kind: ActivityKind) -> String {
        switch kind {
        case let .comment(author, text, viaRelay):
            return "\(author)\(viaRelay ? " (relayed)" : ""): \(text)"
        case let .awaitingChanged(from, to):
            return "Awaiting: \(from ?? "unset") → \(to ?? "unset")"
        case let .defectStatusChanged(from, to):
            return "Defect Status: \(from.map(String.init) ?? "unset") → \(to.map(String.init) ?? "unset")"
        case .assigned:
            return "assigned"
        case .attachment:
            return "attachment added"
        case let .other(subtype):
            return subtype.replacingOccurrences(of: "_", with: " ")
        }
    }
}
