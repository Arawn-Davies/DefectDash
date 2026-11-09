import Darwin
import Foundation

/// Saved tty state for restoration from a signal handler (C function, no captures allowed).
nonisolated(unsafe) private var savedTermios: termios?
nonisolated(unsafe) private var terminalIsRaw = false

private func restoreTerminalState() {
    guard terminalIsRaw else { return }
    terminalIsRaw = false
    let leave = "\u{1B}[0m\u{1B}[?25h\u{1B}[?1049l"
    _ = leave.withCString { write(STDOUT_FILENO, $0, strlen($0)) }
    if var original = savedTermios {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
    }
}

/// Raw-mode terminal on stdin/stdout with the alternate screen.
final class Terminal: @unchecked Sendable {
    let isTTY: Bool

    init() {
        isTTY = isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
    }

    func enterRawMode() {
        guard isTTY, !terminalIsRaw else { return }
        var original = termios()
        tcgetattr(STDIN_FILENO, &original)
        savedTermios = original
        var raw = original
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG | IEXTEN)
        raw.c_iflag &= ~tcflag_t(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
        raw.c_oflag &= ~tcflag_t(OPOST)
        raw.c_cflag |= tcflag_t(CS8)
        withUnsafeMutablePointer(to: &raw.c_cc) { ptr in
            ptr.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { cc in
                cc[Int(VMIN)] = 1
                cc[Int(VTIME)] = 0
            }
        }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        terminalIsRaw = true
        write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[2J")
        for sig in [SIGINT, SIGTERM, SIGHUP, SIGQUIT] {
            signal(sig) { _ in
                restoreTerminalState()
                _exit(0)
            }
        }
    }

    func restore() {
        restoreTerminalState()
    }

    var size: (cols: Int, rows: Int) {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0, ws.ws_col > 0, ws.ws_row > 0 {
            return (Int(ws.ws_col), Int(ws.ws_row))
        }
        return (80, 24)
    }

    func write(_ string: String) {
        var data = Array(string.utf8)
        var offset = 0
        while offset < data.count {
            let n = data.withUnsafeMutableBufferPointer { buf in
                Darwin.write(STDOUT_FILENO, buf.baseAddress! + offset, buf.count - offset)
            }
            if n <= 0 { break }
            offset += n
        }
    }

    /// Blocking read of whatever is available on stdin (up to 256 bytes). nil on EOF/error.
    static func readBytes() -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: 256)
        let n = buffer.withUnsafeMutableBytes { Darwin.read(STDIN_FILENO, $0.baseAddress, 256) }
        guard n > 0 else { return nil }
        return Array(buffer[0..<n])
    }
}
