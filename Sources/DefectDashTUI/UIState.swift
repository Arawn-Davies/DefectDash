import Foundation
import DefectDashCore

enum Row {
    case header(Tier, Int)
    case item(WorkItem)
    case otherHeader(Int)
    case other(Worktree)
}

enum Focus: Equatable { case list, detail, filter, help }

enum Command: Equatable { case none, quit, refresh, openAsana, finder, terminal, copyPath, toggleDimmed }

/// All UI state; pure value type so it is easy to test. Rendering reads it, key handling mutates it.
struct UIState {
    var items: [WorkItem] = []
    var otherWorktrees: [Worktree] = []
    var me: AsanaUserRef?
    var lastRefreshed: Date?
    var isRefreshing = false
    var banner: String?
    var refreshMinutes = 5

    var focus: Focus = .list
    var filter = ""
    var hideDimmed = false
    var showOtherWorktrees = false
    var detailScroll = 0
    var listScroll = 0
    /// Gid of the selected defect; nil = first item.
    var selectedGid: String?

    // MARK: Derived

    var visibleItems: [WorkItem] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { item in
            if hideDimmed && item.group.isDimmed { return false }
            guard !needle.isEmpty else { return true }
            let hay = "bug-\(item.defect.bugNumber ?? 0) \(item.defect.title) \(item.defect.workbenchName)".lowercased()
            return hay.contains(needle)
        }
    }

    var rows: [Row] {
        var out: [Row] = []
        let visible = visibleItems
        for tier in Tier.allCases {
            let tierItems = visible.filter { $0.group == tier }
            guard !tierItems.isEmpty else { continue }
            out.append(.header(tier, tierItems.count))
            out.append(contentsOf: tierItems.map(Row.item))
        }
        out.append(.otherHeader(otherWorktrees.count))
        if showOtherWorktrees { out.append(contentsOf: otherWorktrees.map(Row.other)) }
        return out
    }

    var selectedItem: WorkItem? {
        let visible = visibleItems
        if let gid = selectedGid, let item = visible.first(where: { $0.id == gid }) { return item }
        return visible.first
    }

    /// Index of the selected item's row within `rows`, if any.
    var selectedRowIndex: Int? {
        guard let selected = selectedItem else { return nil }
        return rows.firstIndex { if case let .item(i) = $0 { return i.id == selected.id } else { return false } }
    }

    // MARK: Mutations

    mutating func move(by delta: Int) {
        let visible = visibleItems
        guard !visible.isEmpty else { return }
        let current = selectedItem.flatMap { s in visible.firstIndex { $0.id == s.id } } ?? 0
        let next = min(max(0, current + delta), visible.count - 1)
        selectedGid = visible[next].id
        detailScroll = 0
    }

    mutating func jump(to tier: Tier) {
        guard let first = visibleItems.first(where: { $0.group == tier }) else { return }
        selectedGid = first.id
        detailScroll = 0
    }

    mutating func selectFirst() {
        selectedGid = visibleItems.first?.id
        detailScroll = 0
    }

    mutating func selectLast() {
        selectedGid = visibleItems.last?.id
        detailScroll = 0
    }

    /// Applies a key and returns the side-effecting command the loop must run.
    mutating func apply(_ key: Key) -> Command {
        switch focus {
        case .filter:
            switch key {
            case .enter: focus = .list
            case .escape: filter = ""; focus = .list
            case .backspace: if !filter.isEmpty { filter.removeLast() }
            case let .char(c): filter.append(c)
            case .ctrlC: return .quit
            default: break
            }
            if selectedItem == nil { selectFirst() }
            return .none
        case .help:
            switch key {
            case .ctrlC: return .quit
            case .char("q"), .escape, .char("?"), .enter: focus = .list
            default: break
            }
            return .none
        case .list, .detail:
            break
        }

        switch key {
        case .char("q"), .ctrlC: return .quit
        case .char("r"): return .refresh
        case .char("o"): return .openAsana
        case .char("f"): return .finder
        case .char("t"): return .terminal
        case .char("c"): return .copyPath
        case .char("d"):
            hideDimmed.toggle()
            if selectedItem == nil { selectFirst() }
            return .toggleDimmed
        case .char("?"): focus = .help
        case .char("/"): focus = .filter
        case .char("j"), .down: if focus == .list { move(by: 1) } else { detailScroll += 1 }
        case .char("k"), .up: if focus == .list { move(by: -1) } else { detailScroll = max(0, detailScroll - 1) }
        case .char("g"), .home: if focus == .list { selectFirst() } else { detailScroll = 0 }
        case .char("G"), .end: if focus == .list { selectLast() } else { detailScroll = Int.max / 2 }
        case .char("J"), .pageDown, .char(" "): detailScroll += 10
        case .char("K"), .pageUp: detailScroll = max(0, detailScroll - 10)
        case .enter, .char("l"), .right, .tab: focus = .detail
        case .escape, .char("h"), .left:
            if focus == .detail { focus = .list } else if !filter.isEmpty { filter = "" }
        case .char("O"):
            showOtherWorktrees.toggle()
        case let .char(c) where c.isNumber:
            if let n = c.wholeNumberValue, let tier = Tier(rawValue: n) { jump(to: tier) }
        default: break
        }
        return .none
    }

    mutating func applyRefresh(_ result: RefreshResult, at date: Date = Date()) {
        items = result.items
        otherWorktrees = result.otherWorktrees
        me = result.me
        lastRefreshed = date
        banner = nil
        if selectedItem == nil { selectFirst() }
    }
}
