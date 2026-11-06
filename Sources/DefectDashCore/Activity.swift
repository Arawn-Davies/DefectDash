import Foundation

public enum ActivityKind: Sendable, Equatable {
    case comment(author: String, text: String, viaRelay: Bool)
    case awaitingChanged(from: String?, to: String?)
    case defectStatusChanged(from: Int?, to: Int?)
    case assigned
    case attachment
    case other(String)
}

public struct ActivityEvent: Sendable, Identifiable, Equatable {
    public let id: String
    public let at: Date
    public let byGid: String?
    public let byName: String?
    public let kind: ActivityKind
    public let isMine: Bool

    public init(id: String, at: Date, byGid: String?, byName: String?, kind: ActivityKind, isMine: Bool) {
        self.id = id
        self.at = at
        self.byGid = byGid
        self.byName = byName
        self.kind = kind
        self.isMine = isMine
    }
}

public enum Activity {
    public static let noiseSubtypes: Set<String> = [
        "due_today", "personal_comment_reminder_story", "mentioned_comment_reminder_story",
        "task_due_time_approaching_story", "story_reaction_added",
    ]

    /// A comment relayed from the other side's tracker: "<Org> comment on BUG-184 - Tester A, 10/28/2026, 03:01:27 PM\n<body>"
    private static var relayPattern: Regex<(Substring, Substring)> {
        /^\S+ comment on BUG-\d+ - (.+?), \d{1,2}\/\d{1,2}\/\d{4}, [^\n]*\n/
    }
    private static var relayRefPattern: Regex<Substring> { /\n+ref \d+\s*$/ }
    private static var profileMentionPattern: Regex<Substring> { /https:\/\/app\.asana\.com\/\S*?\/profile\/\d+/ }
    private static var statusNumberPattern: Regex<(Substring, Substring)> { /^\s*(\d+)\s*[·.]/ }

    /// Drops noise; sets isMine by gid; parses the relay prefix into author + stripped text. Newest first.
    public static func events(from stories: [AsanaStory], myGid: String) -> [ActivityEvent] {
        stories
            .filter { !noiseSubtypes.contains($0.resourceSubtype) }
            .map { story in
                ActivityEvent(id: story.gid, at: story.createdAt, byGid: story.createdBy?.gid, byName: story.createdBy?.name,
                              kind: kind(of: story), isMine: story.createdBy?.gid == myGid)
            }
            .sorted { $0.at > $1.at }
    }

    public static func lastOther(_ events: [ActivityEvent]) -> ActivityEvent? {
        events.first { !$0.isMine }
    }

    public static func myLast(_ events: [ActivityEvent]) -> ActivityEvent? {
        events.first { $0.isMine }
    }

    /// true if any Defect Status change goes from 4 back to 3 or 2.
    public static func bounced(_ events: [ActivityEvent]) -> Bool {
        events.contains {
            if case let .defectStatusChanged(from, to) = $0.kind, from == 4, let to, to == 3 || to == 2 { return true }
            return false
        }
    }

    /// "4 · Verify / UAT retest" -> 4, "7. Change Request" -> 7
    public static func parseStatusNumber(_ label: String?) -> Int? {
        guard let label, let match = label.firstMatch(of: statusNumberPattern) else { return nil }
        return Int(match.1)
    }

    // MARK: - Private

    private static func kind(of story: AsanaStory) -> ActivityKind {
        switch story.resourceSubtype {
        case "comment_added":
            return comment(story)
        case "enum_custom_field_changed":
            switch story.customField?.name {
            case "Awaiting":
                return .awaitingChanged(from: story.oldEnumValue?.name, to: story.newEnumValue?.name)
            case "Defect Status":
                return .defectStatusChanged(from: parseStatusNumber(story.oldEnumValue?.name),
                                            to: parseStatusNumber(story.newEnumValue?.name))
            default:
                return .other(story.resourceSubtype)
            }
        case "assigned":
            return .assigned
        case "attachment_added":
            return .attachment
        default:
            return .other(story.resourceSubtype)
        }
    }

    private static func comment(_ story: AsanaStory) -> ActivityKind {
        let raw = story.text ?? ""
        if let match = raw.firstMatch(of: relayPattern) {
            var body = String(raw[match.range.upperBound...])
            body = body.replacing(relayRefPattern, with: "")
            return .comment(author: String(match.1), text: clean(body), viaRelay: true)
        }
        return .comment(author: story.createdBy?.name ?? "Unknown", text: clean(raw), viaRelay: false)
    }

    /// Removes @-mention profile URLs and surrounding whitespace for display.
    private static func clean(_ text: String) -> String {
        text.replacing(profileMentionPattern, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
