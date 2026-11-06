import Foundation

/// Which side of the engagement a defect is waiting on.
public enum Awaiting: Sendable {
    case ours
    case theirs
}

/// The two option labels of the board's "Awaiting" custom field, as configured by the user.
/// Comparison is case-insensitive; an empty label never matches.
public struct AwaitingLabels: Sendable, Equatable {
    public let ours: String
    public let theirs: String

    public init(ours: String, theirs: String) {
        self.ours = ours.trimmingCharacters(in: .whitespaces)
        self.theirs = theirs.trimmingCharacters(in: .whitespaces)
    }

    public static let none = AwaitingLabels(ours: "", theirs: "")

    public func classify(_ label: String?) -> Awaiting? {
        guard let label = label?.trimmingCharacters(in: .whitespaces), !label.isEmpty else { return nil }
        if !theirs.isEmpty, label.caseInsensitiveCompare(theirs) == .orderedSame { return .theirs }
        if !ours.isEmpty, label.caseInsensitiveCompare(ours) == .orderedSame { return .ours }
        return nil
    }
}

public struct Defect: Sendable, Identifiable, Equatable {
    public let gid: String
    public var id: String { gid }
    public let bugNumber: Int?
    public let title: String
    public let workbenchName: String
    public let permalink: String?
    public let sourceGid: String?
    public let status: Int?            // Defect Status leading integer
    public let statusLabel: String?    // raw field value for display
    public let awaiting: Awaiting?     // nil when unset or unknown
    public let awaitingLabel: String?  // raw field value for display
    public let classification: String?
    public let sprint: String?
    public let assignee: AsanaUserRef?
    public let dueOn: Date?            // local-calendar midnight
    public let modifiedAt: Date
    public let notes: DefectNotes
    public let events: [ActivityEvent]

    public init(gid: String, bugNumber: Int?, title: String, workbenchName: String, permalink: String?, sourceGid: String?,
                status: Int?, statusLabel: String? = nil, awaiting: Awaiting?, awaitingLabel: String? = nil,
                classification: String?, sprint: String?, assignee: AsanaUserRef?, dueOn: Date?, modifiedAt: Date,
                notes: DefectNotes, events: [ActivityEvent]) {
        self.gid = gid
        self.bugNumber = bugNumber
        self.title = title
        self.workbenchName = workbenchName
        self.permalink = permalink
        self.sourceGid = sourceGid
        self.status = status
        self.statusLabel = statusLabel
        self.awaiting = awaiting
        self.awaitingLabel = awaitingLabel
        self.classification = classification
        self.sprint = sprint
        self.assignee = assignee
        self.dueOn = dueOn
        self.modifiedAt = modifiedAt
        self.notes = notes
        self.events = events
    }

    public init(task: AsanaTask, stories: [AsanaStory], sourceTitle: String?, myGid: String,
                awaitingLabels: AwaitingLabels, calendar: Calendar = .current) {
        func field(_ name: String) -> String? {
            task.customFields.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.displayValue
        }
        let awaitingLabel = field("Awaiting")
        let awaiting = awaitingLabels.classify(awaitingLabel)
        if let awaitingLabel, !awaitingLabel.isEmpty, awaiting == nil {
            Defect.log("unknown Awaiting value \"\(awaitingLabel)\" on task \(task.gid)")
        }
        let statusLabel = field("Defect Status")
        let status = Activity.parseStatusNumber(statusLabel)
        if let statusLabel, !statusLabel.isEmpty, status == nil {
            Defect.log("unknown Defect Status value \"\(statusLabel)\" on task \(task.gid)")
        }
        // Any custom field whose name ends in "sprint" (e.g. "Client - SPRINT").
        let sprint = task.customFields.first { $0.name.uppercased().hasSuffix("SPRINT") }?.displayValue
        self.init(
            gid: task.gid,
            bugNumber: BugNumber.fromTaskName(task.name),
            title: sourceTitle ?? task.name,
            workbenchName: task.name,
            permalink: task.permalinkUrl,
            sourceGid: task.dependents?.first?.gid,
            status: status,
            statusLabel: statusLabel,
            awaiting: awaiting,
            awaitingLabel: awaitingLabel,
            classification: field("Classification"),
            sprint: sprint,
            assignee: task.assignee,
            dueOn: task.dueOn.flatMap { Defect.parseDay($0, calendar: calendar) },
            modifiedAt: task.modifiedAt,
            notes: DefectNotes.parse(task.notes ?? ""),
            events: Activity.events(from: stories, myGid: myGid)
        )
    }

    /// "yyyy-MM-dd" -> midnight in the calendar's time zone.
    static func parseDay(_ string: String, calendar: Calendar) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func log(_ message: String) {
        #if DEBUG
        FileHandle.standardError.write(Data("DefectDash: \(message)\n".utf8))
        #endif
    }
}
