import SwiftUI
import DefectDashCore

struct DetailView: View {
    @Environment(AppModel.self) private var model
    let item: WorkItem

    private var defect: Defect { item.defect }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                worktrees
                notes
                activity
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textSelection(.enabled)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Format.bug(defect.bugNumber)).font(.system(.title2, design: .monospaced)).bold()
                Text(defect.title).font(.title2)
            }
            HStack(spacing: 10) {
                if let link = defect.permalink.flatMap(URL.init(string:)) {
                    Link("Open in Asana", destination: link)
                }
                if let source = defect.sourceGid, let url = URL(string: "https://app.asana.com/0/0/\(source)/f") {
                    Link("Source task", destination: url)
                }
                ForEach(item.flags.labels + (item.needsYou ? ["NEEDS YOU"] : []), id: \.self) { TagView(text: $0) }
            }
            .font(.callout)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                field("Status", defect.statusLabel)
                field("Awaiting", defect.awaitingLabel)
                field("Classification", defect.classification)
                field("Assignee", defect.assignee?.name)
                field("Due", defect.dueOn.map(Format.day))
                field("Sprint", defect.sprint)
                field("Priority", defect.notes.priority)
                field("Tier", "\(item.group.rawValue). \(item.group.title)")
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private func field(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            GridRow {
                Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                Text(value)
            }
        }
    }

    // MARK: Worktrees

    @ViewBuilder
    private var worktrees: some View {
        if !item.worktrees.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Worktrees")
                ForEach(item.worktrees) { wt in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(wt.path.path).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            if wt.id == item.primaryWorktree?.id {
                                Text("primary").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Finder") { model.openInFinder(wt) }
                            Button("Terminal") { model.openInTerminal(wt) }
                            Button("Copy path") { model.copyPath(wt) }
                        }
                        .controlSize(.small)
                        repoLine(wt.host)
                        ForEach(wt.submodules, id: \.label) { repoLine($0) }
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func repoLine(_ repo: RepoState) -> some View {
        HStack(spacing: 6) {
            Text(repo.label).font(.system(.caption, design: .monospaced)).frame(minWidth: 60, alignment: .leading)
            Text(repo.branch ?? "detached").font(.caption)
            Text(Format.repoSummary(repo)).font(.caption).foregroundStyle(.secondary)
            if let subject = repo.lastCommitSubject {
                Text("· \(repo.lastCommitAuthorEmail ?? "") \(repo.lastCommitAt.map(Format.dateTime) ?? "") · \(subject)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if let error = repo.error {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(1)
            }
        }
    }

    // MARK: Notes

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Report")
            let n = defect.notes
            let parsed: [(String, String?)] = [
                ("Expected result", n.expected), ("Actual result", n.actual), ("Steps to reproduce", n.steps),
                ("Environment", n.environment), ("Browser / device", n.browser), ("Raised by", n.raisedBy),
            ]
            if parsed.allSatisfy({ $0.1 == nil }) {
                if n.raw.isEmpty {
                    Text("No description.").foregroundStyle(.secondary)
                } else {
                    DisclosureGroup("Raw notes") {
                        Text(n.raw).font(.callout)
                    }
                }
            } else {
                ForEach(parsed, id: \.0) { label, value in
                    if let value {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label).font(.caption).foregroundStyle(.secondary)
                            Text(value).font(.callout)
                        }
                    }
                }
            }
        }
    }

    // MARK: Activity

    private var activity: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Activity")
            if defect.events.isEmpty {
                Text("No activity.").foregroundStyle(.secondary)
            }
            ForEach(defect.events) { event in
                ActivityRow(event: event)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.headline)
    }
}

struct ActivityRow: View {
    let event: ActivityEvent

    var body: some View {
        switch event.kind {
        case let .comment(author, text, viaRelay):
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(author).bold()
                    if viaRelay { Text("via relay by \(event.byName ?? "?")").foregroundStyle(.secondary) }
                    Text(Format.dateTime(event.at)).foregroundStyle(.secondary)
                }
                .font(.caption)
                Text(text).font(.callout)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(event.isMine ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 6))
        default:
            HStack(spacing: 6) {
                Text(Format.dateTime(event.at)).foregroundStyle(.secondary)
                Text(event.byName ?? "Asana").bold()
                Text(Format.describe(event.kind))
            }
            .font(.caption)
            .padding(.horizontal, 8)
        }
    }
}
