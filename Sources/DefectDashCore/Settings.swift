import Foundation

/// UserDefaults-backed settings. Every property is a computed accessor over the defaults store,
/// so the class holds no mutable state of its own. UserDefaults is thread-safe.
///
/// Nothing board-specific is defaulted here: project/section gids and the two "Awaiting" labels
/// are entered once in the Settings sheet and live only in this user's defaults.
public final class Settings: @unchecked Sendable {
    public static let shared = Settings(defaults: .standard)

    public static let defaultRefreshMinutes = 5
    public static let refreshRange = 1...30
    public static var defaultWorktreesRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appending(path: "src/wtrees", directoryHint: .isDirectory)
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private enum Key {
        static let projectGid = "dd.projectGid"
        static let sectionGid = "dd.sectionGid"
        static let worktreesRoot = "dd.worktreesRoot"
        static let matchSystems = "dd.matchSystems"
        static let refreshMinutes = "dd.refreshMinutes"
        static let hideDimmed = "dd.hideDimmed"
        static let ourSideLabel = "dd.ourSideLabel"
        static let theirSideLabel = "dd.theirSideLabel"
        static let bugPrefix = "dd.bugPrefix"
        static let statusField = "dd.statusField"
        static let awaitingField = "dd.awaitingField"
        static let classificationField = "dd.classificationField"
        static let sprintField = "dd.sprintField"
        static let closedFromStatus = "dd.closedFromStatus"
        static let retestStatus = "dd.retestStatus"
        static let relayPattern = "dd.relayPattern"
    }

    /// Asana project gid (informational; the section gid drives the query).
    public var projectGid: String {
        get { trimmed(defaults.string(forKey: Key.projectGid)) }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: Key.projectGid) }
    }

    /// Asana section gid whose open tasks are the defects. Empty until configured.
    public var sectionGid: String {
        get { trimmed(defaults.string(forKey: Key.sectionGid)) }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: Key.sectionGid) }
    }

    public var worktreesRoot: URL {
        get {
            let path = trimmed(defaults.string(forKey: Key.worktreesRoot))
            guard !path.isEmpty else { return Self.defaultWorktreesRoot }
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        set { defaults.set(newValue.path, forKey: Key.worktreesRoot) }
    }

    /// Systems (top-level directories under the root) whose worktrees may match defects. Empty = all.
    public var matchSystems: [String] {
        get { defaults.stringArray(forKey: Key.matchSystems) ?? [] }
        set {
            let cleaned = newValue.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            defaults.set(cleaned, forKey: Key.matchSystems)
        }
    }

    public var refreshMinutes: Int {
        get {
            guard defaults.object(forKey: Key.refreshMinutes) != nil else { return Self.defaultRefreshMinutes }
            return clamp(defaults.integer(forKey: Key.refreshMinutes))
        }
        set { defaults.set(clamp(newValue), forKey: Key.refreshMinutes) }
    }

    public var hideDimmed: Bool {
        get { defaults.bool(forKey: Key.hideDimmed) }
        set { defaults.set(newValue, forKey: Key.hideDimmed) }
    }

    /// The "Awaiting" option that means the ball is with us.
    public var ourSideLabel: String {
        get { trimmed(defaults.string(forKey: Key.ourSideLabel)) }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: Key.ourSideLabel) }
    }

    /// The "Awaiting" option that means the ball is with the other side.
    public var theirSideLabel: String {
        get { trimmed(defaults.string(forKey: Key.theirSideLabel)) }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: Key.theirSideLabel) }
    }

    public var awaitingLabels: AwaitingLabels { AwaitingLabels(ours: ourSideLabel, theirs: theirSideLabel) }

    /// The board vocabulary. Unset keys fall back to `BoardConfig.default`.
    public var board: BoardConfig {
        get {
            let d = BoardConfig.default
            func string(_ key: String, _ fallback: String) -> String {
                let value = trimmed(defaults.string(forKey: key))
                return value.isEmpty ? fallback : value
            }
            func int(_ key: String, _ fallback: Int) -> Int {
                defaults.object(forKey: key) == nil ? fallback : max(0, defaults.integer(forKey: key))
            }
            return BoardConfig(
                bugPrefix: string(Key.bugPrefix, d.bugPrefix),
                statusField: string(Key.statusField, d.statusField),
                awaitingField: string(Key.awaitingField, d.awaitingField),
                classificationField: string(Key.classificationField, d.classificationField),
                sprintField: string(Key.sprintField, d.sprintField),
                awaitingLabels: awaitingLabels,
                closedFromStatus: int(Key.closedFromStatus, d.closedFromStatus),
                retestStatus: int(Key.retestStatus, d.retestStatus),
                relayPattern: trimmed(defaults.string(forKey: Key.relayPattern))
            )
        }
        set {
            defaults.set(newValue.bugPrefix.trimmingCharacters(in: .whitespaces), forKey: Key.bugPrefix)
            defaults.set(newValue.statusField.trimmingCharacters(in: .whitespaces), forKey: Key.statusField)
            defaults.set(newValue.awaitingField.trimmingCharacters(in: .whitespaces), forKey: Key.awaitingField)
            defaults.set(newValue.classificationField.trimmingCharacters(in: .whitespaces), forKey: Key.classificationField)
            defaults.set(newValue.sprintField.trimmingCharacters(in: .whitespaces), forKey: Key.sprintField)
            defaults.set(newValue.closedFromStatus, forKey: Key.closedFromStatus)
            defaults.set(newValue.retestStatus, forKey: Key.retestStatus)
            defaults.set(newValue.relayPattern.trimmingCharacters(in: .whitespaces), forKey: Key.relayPattern)
            ourSideLabel = newValue.awaitingLabels.ours
            theirSideLabel = newValue.awaitingLabels.theirs
        }
    }

    private func clamp(_ minutes: Int) -> Int {
        min(max(minutes, Self.refreshRange.lowerBound), Self.refreshRange.upperBound)
    }

    private func trimmed(_ string: String?) -> String {
        (string ?? "").trimmingCharacters(in: .whitespaces)
    }
}
