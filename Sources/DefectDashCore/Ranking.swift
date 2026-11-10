import Foundation

public enum Tier: Int, CaseIterable, Sendable, Comparable, Codable {
    case needsYou = 1, yoursInHand, unassigned, someoneElses, withThem, closedOnBoard

    public var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .yoursInHand: "Yours, in hand"
        case .unassigned: "Unassigned, on our side"
        case .someoneElses: "Someone else's"
        case .withThem: "With the other side"
        case .closedOnBoard: "Closed on the board, still open in Asana"
        }
    }

    /// Groups 4–6 are shown dimmed and hidden by the "hide dimmed" toggle.
    public var isDimmed: Bool { rawValue >= Tier.someoneElses.rawValue }

    public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct Flags: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let retest = Flags(rawValue: 1 << 0)
    public static let expectedBehaviour = Flags(rawValue: 1 << 1)
    public static let overdue = Flags(rawValue: 1 << 2)
    public static let bounced = Flags(rawValue: 1 << 3)
    public static let noWorktree = Flags(rawValue: 1 << 4)

    /// Row tags in display order.
    public var labels: [String] {
        var out: [String] = []
        if contains(.retest) { out.append("RETEST") }
        if contains(.expectedBehaviour) { out.append("EXPECTED BEHAVIOUR") }
        if contains(.overdue) { out.append("OVERDUE") }
        if contains(.bounced) { out.append("BOUNCED") }
        if contains(.noWorktree) { out.append("NO WORKTREE") }
        return out
    }
}

public struct WorkItem: Sendable, Identifiable, Codable {
    public var id: String { defect.gid }
    public let defect: Defect
    public let worktrees: [Worktree]
    public let primaryWorktree: Worktree?
    public let group: Tier
    public let flags: Flags
    public let needsYou: Bool
    public let lastOtherActivity: ActivityEvent?
    public let myLastAction: Date?

    public init(defect: Defect, worktrees: [Worktree], primaryWorktree: Worktree?, group: Tier, flags: Flags,
                needsYou: Bool, lastOtherActivity: ActivityEvent?, myLastAction: Date?) {
        self.defect = defect
        self.worktrees = worktrees
        self.primaryWorktree = primaryWorktree
        self.group = group
        self.flags = flags
        self.needsYou = needsYou
        self.lastOtherActivity = lastOtherActivity
        self.myLastAction = myLastAction
    }
}

public struct RankingContext: Sendable {
    public let myGid: String
    /// Systems whose worktrees may be joined to defects; empty means every system.
    public let matchSystems: Set<String>
    public let board: BoardConfig
    public let now: Date
    public let calendar: Calendar

    public init(myGid: String, matchSystems: Set<String>, board: BoardConfig = .default, now: Date = Date(),
                calendar: Calendar = .current) {
        self.myGid = myGid
        self.matchSystems = matchSystems
        self.board = board
        self.now = now
        self.calendar = calendar
    }
}

public enum Ranking {
    private static var retestPattern: Regex<Substring> { /\bre-?test(?:ed|ing)?\b/.ignoresCase() }
    private static var expectedBehaviourPattern: Regex<Substring> { /expected behaviou?r/.ignoresCase() }

    /// Joins defects to worktrees, decides group and flags, and returns the items in display order.
    public static func rank(defects: [Defect], worktrees: [Worktree], context: RankingContext) -> [WorkItem] {
        let candidates = worktrees.filter {
            (context.matchSystems.isEmpty || context.matchSystems.contains($0.system)) && $0.bugNumber != nil
        }
        let startOfToday = context.calendar.startOfDay(for: context.now)
        let items = defects.map { build($0, candidates: candidates, startOfToday: startOfToday, context: context) }
        return items.sorted { a, b in
            if a.group != b.group { return a.group < b.group }
            return before(a, b, in: a.group)
        }
    }

    /// Unmatched worktrees that are dirty or ahead, newest commit first.
    public static func otherWorktrees(_ worktrees: [Worktree], matched: Set<String>) -> [Worktree] {
        worktrees
            .filter { !matched.contains($0.id) && ($0.dirty || ($0.host.ahead ?? 0) > 0 || $0.anySubmoduleAhead) }
            .sorted { ($0.lastCommitAt ?? .distantPast) > ($1.lastCommitAt ?? .distantPast) }
    }

    // MARK: - Building one item

    private static func build(_ defect: Defect, candidates: [Worktree], startOfToday: Date, context: RankingContext) -> WorkItem {
        let matched = defect.bugNumber.map { bug in candidates.filter { $0.bugNumber == bug } } ?? []
        let primary = matched.max { ($0.lastCommitAt ?? .distantPast) < ($1.lastCommitAt ?? .distantPast) }

        let closed = defect.status.map { $0 >= context.board.closedFromStatus } ?? false
        let awaiting = defect.awaiting ?? .ours
        let assignedToMe = defect.assignee?.gid == context.myGid

        let lastOther = Activity.lastOther(defect.events)
        let myLastAction = [Activity.myLast(defect.events)?.at, primary?.myLastCommitAt].compactMap { $0 }.max()
        let needsYou = !closed && awaiting == .ours
            && (lastOther.map { $0.at > (myLastAction ?? .distantPast) } ?? false)

        let group: Tier
        if closed {
            group = .closedOnBoard
        } else if awaiting == .theirs {
            group = .withThem
        } else if needsYou && (assignedToMe || primary != nil) {
            group = .needsYou
        } else if assignedToMe {
            group = .yoursInHand
        } else if defect.assignee == nil {
            group = .unassigned
        } else {
            group = .someoneElses
        }

        var flags: Flags = []
        let bounced = Activity.bounced(defect.events, retestStatus: context.board.retestStatus)
        if let newest = newestComment(defect.events), newest.text.firstMatch(of: retestPattern) != nil,
           defect.status == context.board.retestStatus || bounced {
            flags.insert(.retest)
        }
        if defect.classification == "Expected Behaviour" {
            flags.insert(.expectedBehaviour)
        } else if let relayed = newestComment(defect.events, relayedOnly: true),
                  relayed.text.firstMatch(of: expectedBehaviourPattern) != nil {
            flags.insert(.expectedBehaviour)
        }
        if let due = defect.dueOn, due < startOfToday { flags.insert(.overdue) }
        if bounced { flags.insert(.bounced) }
        if !closed && awaiting == .ours && assignedToMe && matched.isEmpty { flags.insert(.noWorktree) }

        return WorkItem(defect: defect, worktrees: matched, primaryWorktree: primary, group: group, flags: flags,
                        needsYou: needsYou, lastOtherActivity: lastOther, myLastAction: myLastAction)
    }

    private static func newestComment(_ events: [ActivityEvent], relayedOnly: Bool = false) -> (text: String, viaRelay: Bool)? {
        for event in events {
            if case let .comment(_, text, viaRelay) = event.kind, !relayedOnly || viaRelay {
                return (text, viaRelay)
            }
        }
        return nil
    }

    // MARK: - Ordering

    /// Further along first (higher number), unset last.
    private static func statusRank(_ status: Int?) -> Int {
        guard let status else { return Int.max }
        return -status
    }

    private static func latestActivity(_ item: WorkItem) -> Date {
        item.defect.events.first?.at ?? item.defect.modifiedAt
    }

    private static func before(_ a: WorkItem, _ b: WorkItem, in group: Tier) -> Bool {
        switch group {
        case .needsYou:
            let ao = a.flags.contains(.overdue), bo = b.flags.contains(.overdue)
            if ao != bo { return ao }
            let asr = statusRank(a.defect.status), bsr = statusRank(b.defect.status)
            if asr != bsr { return asr < bsr }
            let aw = a.lastOtherActivity?.at ?? .distantFuture, bw = b.lastOtherActivity?.at ?? .distantFuture
            if aw != bw { return aw < bw }
        case .yoursInHand, .unassigned:
            let ad = a.defect.dueOn ?? .distantFuture, bd = b.defect.dueOn ?? .distantFuture
            if ad != bd { return ad < bd }
            let asr = statusRank(a.defect.status), bsr = statusRank(b.defect.status)
            if asr != bsr { return asr < bsr }
        case .someoneElses, .withThem:
            let aa = latestActivity(a), ba = latestActivity(b)
            if aa != ba { return aa > ba }
        case .closedOnBoard:
            if a.defect.modifiedAt != b.defect.modifiedAt { return a.defect.modifiedAt > b.defect.modifiedAt }
        }
        return (a.defect.bugNumber ?? Int.max, a.defect.gid) < (b.defect.bugNumber ?? Int.max, b.defect.gid)
    }
}
