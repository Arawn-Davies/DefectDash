import Foundation

public enum BugNumber {
    /// Matches `<prefix>-0*(\d+)`, case-insensitive. "Follow up of BUG-184" -> 184
    public static func fromTaskName(_ name: String, prefix: String = "BUG") -> Int? {
        guard let regex = try? Regex("\\b\(NSRegularExpression.escapedPattern(for: prefix))-0*(\\d+)").ignoresCase(),
              let match = name.firstMatch(of: regex) else { return nil }
        return match.output[1].substring.flatMap { Int($0) }
    }

    /// Matches `(?i)\b<prefix>[-_/]?0*(\d+)\b` against relativePath first, then branch.
    public static func fromWorktree(relativePath: String, branch: String?, prefix: String = "BUG") -> Int? {
        guard let regex = try? Regex("\\b\(NSRegularExpression.escapedPattern(for: prefix))[-_/]?0*(\\d+)\\b").ignoresCase()
        else { return nil }
        for candidate in [relativePath, branch].compactMap({ $0 }) {
            if let match = candidate.firstMatch(of: regex), let n = match.output[1].substring.flatMap({ Int($0) }) {
                return n
            }
        }
        return nil
    }
}
