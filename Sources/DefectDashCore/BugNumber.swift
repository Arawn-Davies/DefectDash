import Foundation

public enum BugNumber {
    // Computed, not stored: `Regex` is not Sendable, so a stored static would be a shared mutable global.
    private static var taskNamePattern: Regex<(Substring, Substring)> { /BUG-0*(\d+)/.ignoresCase() }
    private static var worktreePattern: Regex<(Substring, Substring)> { /\bbug[-_\/]?0*(\d+)\b/.ignoresCase() }

    /// Matches `BUG-0*(\d+)`, case-insensitive. "Follow up of BUG-184" -> 184
    public static func fromTaskName(_ name: String) -> Int? {
        guard let match = name.firstMatch(of: taskNamePattern) else { return nil }
        return Int(match.1)
    }

    /// Matches `(?i)\bbug[-_/]?0*(\d+)\b` against relativePath first, then branch.
    public static func fromWorktree(relativePath: String, branch: String?) -> Int? {
        if let match = relativePath.firstMatch(of: worktreePattern), let n = Int(match.1) {
            return n
        }
        if let branch, let match = branch.firstMatch(of: worktreePattern), let n = Int(match.1) {
            return n
        }
        return nil
    }
}
