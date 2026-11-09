import SwiftUI
import DefectDashCore

/// Dirty or unpushed worktrees that matched no defect, newest commit first. Collapsed by default.
struct OtherWorktreesView: View {
    @Environment(AppModel.self) private var model
    let worktrees: [Worktree]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(worktrees) { wt in
                    HStack(spacing: 6) {
                        Text("\(wt.system)/\(wt.relativePath)")
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                        if let branch = wt.branch, branch != wt.relativePath {
                            Text("· \(branch)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(Format.repoSummary(wt.host)).font(.caption).foregroundStyle(.secondary)
                        if wt.anySubmoduleAhead { Text("+sub").font(.caption).foregroundStyle(.orange) }
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button("Open in Finder") { model.openInFinder(wt) }
                        Button("Open in Terminal") { model.openInTerminal(wt) }
                        Button("Copy path") { model.copyPath(wt) }
                    }
                }
            } label: {
                Text("Other worktrees (\(worktrees.count))")
                    .font(.headline)
            }
        }
    }
}
