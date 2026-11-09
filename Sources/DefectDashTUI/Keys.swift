import Foundation

enum Key: Equatable, Sendable {
    case char(Character)
    case up, down, left, right
    case pageUp, pageDown, home, end
    case enter, escape, backspace, tab, ctrlC
    case unknown
}

/// Turns raw bytes from a terminal in raw mode into keys. Handles CSI and SS3 cursor sequences,
/// a lone ESC, control characters and multi-byte UTF-8.
enum KeyParser {
    static func parse(_ bytes: [UInt8]) -> [Key] {
        var keys: [Key] = []
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x1B {
                if i + 1 < bytes.count, bytes[i + 1] == UInt8(ascii: "[") || bytes[i + 1] == UInt8(ascii: "O") {
                    let isCSI = bytes[i + 1] == UInt8(ascii: "[")
                    var j = i + 2
                    var params: [UInt8] = []
                    while j < bytes.count, !(0x40...0x7E).contains(bytes[j]) {
                        params.append(bytes[j])
                        j += 1
                    }
                    guard j < bytes.count else { keys.append(.escape); i = bytes.count; break }
                    let final = bytes[j]
                    keys.append(isCSI ? csi(params: params, final: final) : ss3(final: final))
                    i = j + 1
                    continue
                }
                keys.append(.escape)
                i += 1
                continue
            }
            switch b {
            case 0x0D, 0x0A: keys.append(.enter)
            case 0x7F, 0x08: keys.append(.backspace)
            case 0x09: keys.append(.tab)
            case 0x03: keys.append(.ctrlC)
            case 0x00..<0x20: keys.append(.unknown)
            default:
                let length = utf8Length(leading: b)
                let end = min(bytes.count, i + length)
                let scalarBytes = Array(bytes[i..<end])
                if let s = String(bytes: scalarBytes, encoding: .utf8), let c = s.first {
                    keys.append(.char(c))
                } else {
                    keys.append(.unknown)
                }
                i = end
                continue
            }
            i += 1
        }
        return keys
    }

    private static func csi(params: [UInt8], final: UInt8) -> Key {
        let p = String(decoding: params, as: UTF8.self)
        switch (p, final) {
        case ("", UInt8(ascii: "A")): return .up
        case ("", UInt8(ascii: "B")): return .down
        case ("", UInt8(ascii: "C")): return .right
        case ("", UInt8(ascii: "D")): return .left
        case ("", UInt8(ascii: "H")), ("1", UInt8(ascii: "~")), ("7", UInt8(ascii: "~")): return .home
        case ("", UInt8(ascii: "F")), ("4", UInt8(ascii: "~")), ("8", UInt8(ascii: "~")): return .end
        case ("5", UInt8(ascii: "~")): return .pageUp
        case ("6", UInt8(ascii: "~")): return .pageDown
        default: return .unknown
        }
    }

    private static func ss3(final: UInt8) -> Key {
        switch final {
        case UInt8(ascii: "A"): .up
        case UInt8(ascii: "B"): .down
        case UInt8(ascii: "C"): .right
        case UInt8(ascii: "D"): .left
        case UInt8(ascii: "H"): .home
        case UInt8(ascii: "F"): .end
        default: .unknown
        }
    }

    private static func utf8Length(leading: UInt8) -> Int {
        switch leading {
        case 0xF0...0xF7: 4
        case 0xE0...0xEF: 3
        case 0xC0...0xDF: 2
        default: 1
        }
    }
}
