import Foundation

enum TextLayout {
    /// Cuts to `width` cells with a trailing ellipsis when something was removed.
    static func truncate(_ text: String, width: Int) -> String {
        guard width > 0 else { return "" }
        if text.count <= width { return text }
        guard width > 1 else { return "…" }
        return String(text.prefix(width - 1)) + "…"
    }

    /// Truncates or right-pads with spaces to exactly `width` cells.
    static func pad(_ text: String, width: Int) -> String {
        let cut = truncate(text, width: width)
        return cut + String(repeating: " ", count: max(0, width - cut.count))
    }

    /// Greedy word wrap; words longer than `width` are hard-broken; blank lines are preserved.
    static func wrap(_ text: String, width: Int) -> [String] {
        let width = max(1, width)
        var lines: [String] = []
        for paragraph in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            var current = ""
            for word in paragraph.split(separator: " ", omittingEmptySubsequences: true) {
                var word = String(word)
                while word.count > width {
                    if !current.isEmpty { lines.append(current); current = "" }
                    lines.append(String(word.prefix(width)))
                    word = String(word.dropFirst(width))
                }
                if current.isEmpty {
                    current = word
                } else if current.count + 1 + word.count <= width {
                    current += " " + word
                } else {
                    lines.append(current)
                    current = word
                }
            }
            lines.append(current)
        }
        return lines
    }
}
