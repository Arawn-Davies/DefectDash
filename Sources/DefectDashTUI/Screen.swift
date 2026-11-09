import Foundation

enum Color: Equatable, Sendable {
    case `default`, black, red, green, yellow, blue, magenta, cyan, white, gray, orange, purple, teal

    /// 16-colour SGR code (foreground; add 10 for background).
    var ansi: Int {
        switch self {
        case .default: 39
        case .black: 30
        case .red: 31
        case .green: 32
        case .yellow: 33
        case .blue: 34
        case .magenta, .purple: 35
        case .cyan, .teal: 36
        case .white: 37
        case .gray: 90
        case .orange: 93
        }
    }

    var rgb: (Int, Int, Int)? {
        switch self {
        case .default: nil
        case .black: (0x1B, 0x1D, 0x24)
        case .red: (0xFF, 0x5A, 0x5F)
        case .green: (0x7E, 0xD3, 0x8A)
        case .yellow: (0xF2, 0xCC, 0x60)
        case .blue: (0x7A, 0xA2, 0xF7)
        case .magenta: (0xD8, 0x8B, 0xF2)
        case .cyan: (0x7D, 0xCF, 0xFF)
        case .white: (0xE6, 0xE6, 0xE6)
        case .gray: (0x80, 0x86, 0x94)
        case .orange: (0xFF, 0xA0, 0x4D)
        case .purple: (0xB8, 0x8C, 0xFF)
        case .teal: (0x5F, 0xD7, 0xC8)
        }
    }
}

struct Style: Equatable, Sendable {
    var fg: Color = .default
    var bg: Color = .default
    var bold = false
    var dim = false
    var reverse = false
    var underline = false

    static let plain = Style()
    static let dimmed = Style(dim: true)
    static let bold = Style(bold: true)
    static func fg(_ color: Color, bold: Bool = false, dim: Bool = false) -> Style { Style(fg: color, bold: bold, dim: dim) }
}

enum Palette: Sendable {
    case none, ansi16, truecolor

    static func detect(environment: [String: String] = ProcessInfo.processInfo.environment) -> Palette {
        if environment["NO_COLOR"] != nil { return .none }
        let colorterm = environment["COLORTERM"]?.lowercased() ?? ""
        if colorterm.contains("truecolor") || colorterm.contains("24bit") { return .truecolor }
        if let term = environment["TERM"], term.contains("kitty") || term.contains("direct") { return .truecolor }
        return .ansi16
    }

    func sgr(_ style: Style) -> String {
        var codes: [String] = ["0"]
        if style.bold { codes.append("1") }
        if style.dim { codes.append("2") }
        if style.underline { codes.append("4") }
        if style.reverse { codes.append("7") }
        if self != .none {
            codes.append(contentsOf: colorCodes(style.fg, background: false))
            codes.append(contentsOf: colorCodes(style.bg, background: true))
        }
        return "\u{1B}[" + codes.joined(separator: ";") + "m"
    }

    private func colorCodes(_ color: Color, background: Bool) -> [String] {
        if color == .default { return [] }
        switch self {
        case .truecolor:
            if let (r, g, b) = color.rgb { return [background ? "48" : "38", "2", "\(r)", "\(g)", "\(b)"] }
            return []
        case .ansi16:
            return ["\(color.ansi + (background ? 10 : 0))"]
        case .none:
            return []
        }
    }
}

struct Cell: Equatable {
    var char: Character = " "
    var style: Style = .plain
}

/// A fixed-size grid of styled characters, rendered to one escape-sequence string per frame.
final class Screen {
    let cols: Int
    let rows: Int
    private var cells: [[Cell]]

    init(cols: Int, rows: Int) {
        self.cols = max(0, cols)
        self.rows = max(0, rows)
        cells = Array(repeating: Array(repeating: Cell(), count: max(0, cols)), count: max(0, rows))
    }

    func put(x: Int, y: Int, _ text: String, style: Style) {
        guard y >= 0, y < rows else { return }
        var cx = x
        for ch in text {
            if cx >= cols { break }
            if cx >= 0 { cells[y][cx] = Cell(char: ch, style: style) }
            cx += 1
        }
    }

    func fill(x: Int, y: Int, width: Int, height: Int, char: Character = " ", style: Style) {
        for yy in max(0, y)..<min(rows, y + height) {
            for xx in max(0, x)..<min(cols, x + width) {
                cells[yy][xx] = Cell(char: char, style: style)
            }
        }
    }

    func line(_ y: Int) -> String {
        guard y >= 0, y < rows else { return "" }
        return String(cells[y].map(\.char))
    }

    func render(palette: Palette) -> String {
        var out = "\u{1B}[H"
        for y in 0..<rows {
            out += "\u{1B}[\(y + 1);1H"
            var current: Style? = nil
            for cell in cells[y] {
                if cell.style != current {
                    out += palette.sgr(cell.style)
                    current = cell.style
                }
                out.append(cell.char)
            }
        }
        out += "\u{1B}[0m"
        return out
    }
}
