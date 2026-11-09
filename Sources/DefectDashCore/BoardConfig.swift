import Foundation

/// Everything about *your* board's vocabulary. Nothing here is hard-coded elsewhere; the app reads it from Settings.
public struct BoardConfig: Sendable, Equatable {
    /// Ticket prefix: tasks named "… BUG-101 …" and worktrees named "fix/bug-101" with prefix "BUG".
    public var bugPrefix: String
    /// Custom field whose options start with a number ("1 · Open" … "5 · Closed"); the number drives ranking.
    public var statusField: String
    /// Custom field saying which side the ticket is waiting on; see `awaitingLabels`.
    public var awaitingField: String
    /// Custom field whose value "Expected Behaviour" raises the EXPECTED BEHAVIOUR tag.
    public var classificationField: String
    /// Custom field for the sprint; matched case-insensitively as a suffix ("Sprint", "Client - SPRINT").
    public var sprintField: String
    public var awaitingLabels: AwaitingLabels
    /// Status numbers at or above this are "closed on the board".
    public var closedFromStatus: Int
    /// The status number that means "awaiting retest"; a retest comment in this status raises RETEST.
    public var retestStatus: Int
    /// Optional regex for comments relayed from another tracker. Group 1 is the real author; the match is
    /// stripped from the displayed text. Empty disables relay parsing.
    public var relayPattern: String

    public init(bugPrefix: String = "BUG", statusField: String = "Status", awaitingField: String = "Awaiting",
                classificationField: String = "Classification", sprintField: String = "Sprint",
                awaitingLabels: AwaitingLabels = .none, closedFromStatus: Int = 5, retestStatus: Int = 4,
                relayPattern: String = "") {
        self.bugPrefix = bugPrefix
        self.statusField = statusField
        self.awaitingField = awaitingField
        self.classificationField = classificationField
        self.sprintField = sprintField
        self.awaitingLabels = awaitingLabels
        self.closedFromStatus = closedFromStatus
        self.retestStatus = retestStatus
        self.relayPattern = relayPattern
    }

    public static let `default` = BoardConfig()

    /// Compiled relay regex, or nil when unset or invalid.
    public var relayRegex: Regex<AnyRegexOutput>? {
        let trimmed = relayPattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return try? Regex(trimmed)
    }
}
