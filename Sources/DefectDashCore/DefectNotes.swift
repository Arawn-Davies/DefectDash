import Foundation

/// The structured fields of a "Defect Report" form submission, parsed out of a task's `notes`.
public struct DefectNotes: Sendable, Equatable {
    public let raisedBy, dateRaised, deliverable, environment, browser, steps, expected, actual, testCaseId, priority, sprint: String?
    public let raw: String

    public init(raisedBy: String?, dateRaised: String?, deliverable: String?, environment: String?, browser: String?,
                steps: String?, expected: String?, actual: String?, testCaseId: String?, priority: String?,
                sprint: String?, raw: String) {
        self.raisedBy = raisedBy
        self.dateRaised = dateRaised
        self.deliverable = deliverable
        self.environment = environment
        self.browser = browser
        self.steps = steps
        self.expected = expected
        self.actual = actual
        self.testCaseId = testCaseId
        self.priority = priority
        self.sprint = sprint
        self.raw = raw
    }

    private enum Key: CaseIterable {
        case raisedBy, dateRaised, deliverable, environment, browser, steps, expected, actual, testCaseId, priority, sprint

        /// Accepted heading spellings, case-insensitive. The sprint heading is any label ending in "sprint".
        var aliases: [String] {
            switch self {
            case .raisedBy: ["Raised by", "Reported by", "Reporter", "Submitted by"]
            case .dateRaised: ["Date raised", "Date reported", "Reported on", "Date"]
            case .deliverable: ["Deliverable / acceptance criterion affected", "Acceptance criterion affected",
                                "Acceptance criterion", "Acceptance criteria", "Deliverable", "Requirement", "Feature"]
            case .environment: ["Environment", "Env"]
            case .browser: ["Browser / device", "Browser", "Device", "Platform"]
            case .steps: ["Steps to reproduce", "Reproduction steps", "Repro steps", "Steps"]
            case .expected: ["Expected result", "Expected results", "Expected behaviour", "Expected behavior", "Expected"]
            case .actual: ["Actual result", "Actual results", "Actual behaviour", "Actual behavior", "Actual", "Observed"]
            case .testCaseId: ["Test Case ID", "Test case", "Test ID"]
            case .priority: ["Priority", "Severity"]
            case .sprint: ["Sprint"]
            }
        }
    }

    /// A heading line: a known label, optional `(parenthetical)`, then one or two colons.
    private static var headingPattern: Regex<(Substring, Substring)> {
        var alternatives = Key.allCases.filter { $0 != .sprint }
            .flatMap(\.aliases)
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
        alternatives.append("(?:[A-Za-z0-9]+ - )?sprint")
        return try! Regex("^(\(alternatives.joined(separator: "|")))\\s*(?:\\([^)]*\\))?\\s*:{1,2}\\s*$").ignoresCase()
    }

    private static func key(forHeading heading: Substring) -> Key? {
        let text = String(heading)
        if text.uppercased().hasSuffix("SPRINT") { return .sprint }
        return Key.allCases.first { key in
            key.aliases.contains { $0.caseInsensitiveCompare(text) == .orderedSame }
        }
    }

    /// A horizontal rule line: three or more em dashes or hyphens.
    private static var rulePattern: Regex<Substring> { /^[—-]{3,}\s*$/ }

    /// A continuation heading line such as `(paste backlog task link, e.g. AC-01):`.
    private static var parentheticalLinePattern: Regex<Substring> { /^\([^)]*\)\s*:{1,2}\s*$/ }

    public static func parse(_ notes: String) -> DefectNotes {
        let normalised = notes.replacingOccurrences(of: "\r\n", with: "\n")
        var sections: [Key: [String]] = [:]
        var current: Key? = nil
        var currentLines: [String] = []

        func close() {
            if let key = current { sections[key] = currentLines }
            current = nil
            currentLines = []
        }

        for line in normalised.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            if let match = text.firstMatch(of: headingPattern), let key = key(forHeading: match.1) {
                close()
                current = key
                continue
            }
            if text.firstMatch(of: rulePattern) != nil {
                close()
                continue
            }
            guard current != nil else { continue }
            if currentLines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }),
               text.firstMatch(of: parentheticalLinePattern) != nil {
                continue   // second line of a two-line heading
            }
            currentLines.append(text)
        }
        close()

        func value(_ key: Key) -> String? {
            guard let lines = sections[key] else { return nil }
            let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        }

        return DefectNotes(raisedBy: value(.raisedBy), dateRaised: value(.dateRaised), deliverable: value(.deliverable),
                           environment: value(.environment), browser: value(.browser), steps: value(.steps),
                           expected: value(.expected), actual: value(.actual), testCaseId: value(.testCaseId),
                           priority: value(.priority), sprint: value(.sprint), raw: notes)
    }
}
