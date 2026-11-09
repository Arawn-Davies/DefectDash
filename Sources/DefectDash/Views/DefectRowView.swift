import SwiftUI
import DefectDashCore

struct DefectRowView: View {
    let item: WorkItem

    private var tags: [String] {
        item.flags.labels + (item.needsYou ? ["NEEDS YOU"] : [])
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Format.groupColor(item.group))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(Format.bug(item.defect.bugNumber))
                        .font(.system(.body, design: .monospaced)).bold()
                    Text(item.defect.displayTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                if !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tags, id: \.self) { tag in
                            TagView(text: tag)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Text(item.defect.statusLabel ?? "no status")
                    Text("· \(item.defect.awaitingLabel ?? "awaiting unset")")
                    Text("· \(Format.initials(item.defect.assignee?.name))")
                        .help(item.defect.assignee?.name ?? "unassigned")
                    if let due = item.defect.dueOn {
                        Text("· due \(Format.day(due))")
                            .foregroundStyle(item.flags.contains(.overdue) ? .red : .secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !item.worktrees.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(item.worktrees) { wt in
                            WorktreeChip(worktree: wt, primary: wt.id == item.primaryWorktree?.id)
                        }
                    }
                }
                if let last = item.lastOtherActivity {
                    Text("\(last.byName ?? "someone") · \(Format.shortAge(last.at)) · \(Format.describe(last.kind).prefix(80))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
        .opacity(item.group.isDimmed ? 0.55 : 1)
    }
}

struct TagView: View {
    let text: String

    private var color: Color {
        switch text {
        case "NEEDS YOU": .red
        case "OVERDUE": .orange
        case "BOUNCED": .purple
        case "RETEST": .blue
        case "EXPECTED BEHAVIOUR": .teal
        default: .gray
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
}

struct WorktreeChip: View {
    let worktree: Worktree
    let primary: Bool

    var body: some View {
        HStack(spacing: 3) {
            Text(worktree.branch ?? worktree.relativePath)
                .font(.system(size: 10, design: .monospaced))
            Text(Format.repoSummary(worktree.host))
                .font(.system(size: 10))
            if worktree.anySubmoduleAhead {
                Text("+sub").font(.system(size: 10)).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(primary ? Color.accentColor.opacity(0.6) : .clear))
        .help(worktree.path.path)
    }
}
