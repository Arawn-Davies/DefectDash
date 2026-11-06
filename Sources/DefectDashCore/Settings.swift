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

    private func clamp(_ minutes: Int) -> Int {
        min(max(minutes, Self.refreshRange.lowerBound), Self.refreshRange.upperBound)
    }

    private func trimmed(_ string: String?) -> String {
        (string ?? "").trimmingCharacters(in: .whitespaces)
    }
}
