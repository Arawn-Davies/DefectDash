import SwiftUI
import DefectDashCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: String?
    @State private var search = ""
    @State private var showSettings = false
    @State private var hideDimmed = Settings.shared.hideDimmed

    private var visibleItems: [WorkItem] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return model.items.filter { item in
            if hideDimmed && item.group.isDimmed { return false }
            guard !needle.isEmpty else { return true }
            let haystack = "\(Format.bug(item.defect.bugNumber)) \(item.defect.title) \(item.defect.workbenchName)".lowercased()
            return haystack.contains(needle)
        }
    }

    var body: some View {
        NavigationSplitView {
            // A plain scrolling stack rather than `List`: SwiftUI's List is an NSOutlineView, and on macOS 26.6
            // its mouse-down tracking crashed inside QuartzCore's accelerated CG path on every row click.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(Tier.allCases, id: \.rawValue) { group in
                        let items = visibleItems.filter { $0.group == group }
                        if !items.isEmpty {
                            Section {
                                ForEach(items) { item in
                                    SelectableRow(isSelected: selectedID == item.id) {
                                        selectedID = item.id
                                    } content: {
                                        DefectRowView(item: item)
                                    }
                                }
                            } header: {
                                SectionHeader(text: "\(group.rawValue). \(group.title) (\(items.count))")
                            }
                        }
                    }
                    if model.items.isEmpty && !model.isRefreshing {
                        Text(model.banner == nil ? "No open defects." : "Nothing loaded yet.")
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                    OtherWorktreesView(worktrees: model.otherWorktrees)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                }
                .padding(.bottom, 12)
            }
            .navigationSplitViewColumnWidth(min: 440, ideal: 560, max: 800)
        } detail: {
            if let item = model.items.first(where: { $0.id == selectedID }) {
                DetailView(item: item)
            } else {
                ContentUnavailableView("Select a defect", systemImage: "ladybug",
                                       description: Text("Pick a row to see its report, worktrees and activity."))
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Bug number or title")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)
                .keyboardShortcut("r", modifiers: .command)
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                }
                Text(lastRefreshedText).foregroundStyle(.secondary).font(.callout)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $hideDimmed) {
                    Label("Hide dimmed", systemImage: "eye.slash")
                }
                .toggleStyle(.button)
                .help("Hide groups 4–6")
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let banner = model.banner {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(banner)
                    Spacer()
                }
                .font(.callout)
                .padding(8)
                .background(.red.opacity(0.18))
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: hideDimmed) { _, value in
            model.settings.hideDimmed = value
        }
        .onChange(of: model.needsSettings) { _, value in
            if value { showSettings = true }
        }
        .onChange(of: model.settingsRequests) { _, _ in
            showSettings = true
        }
        .onAppear {
            if model.needsSettings { showSettings = true }
        }
    }

    private var lastRefreshedText: String {
        guard let at = model.lastRefreshed else { return "not refreshed yet" }
        return "refreshed \(Format.shortAge(at)) ago"
    }
}

/// One clickable row with a selection highlight; no AppKit table machinery involved.
struct SelectableRow<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 8)
    }
}

struct SectionHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
    }
}
