import Darwin
import Foundation
import DefectDashCore

enum Event: Sendable {
    case keys([Key])
    case resize
    case tick
    case refreshed(Result<RefreshResult, any Error>)
}

/// Produces the TUI's event stream from stdin, SIGWINCH and a clock. Lives outside `main.swift` so none of
/// its callbacks inherit the top-level code's main-actor isolation (they run on GCD queues and a thread).
enum EventSources {
    nonisolated(unsafe) private static var winch: DispatchSourceSignal?
    nonisolated(unsafe) private static var ticker: DispatchSourceTimer?

    static func start(tickSeconds: Double = 15) -> (AsyncStream<Event>, AsyncStream<Event>.Continuation) {
        let (stream, continuation) = AsyncStream<Event>.makeStream()

        let keyThread = Thread {
            while let bytes = Terminal.readBytes() {
                continuation.yield(.keys(KeyParser.parse(bytes)))
            }
            continuation.yield(.keys([.ctrlC]))
        }
        keyThread.name = "defectdash-keys"
        keyThread.start()

        signal(SIGWINCH, SIG_IGN)
        let winch = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: .global())
        winch.setEventHandler { continuation.yield(.resize) }
        winch.resume()
        Self.winch = winch

        let ticker = DispatchSource.makeTimerSource(queue: .global())
        ticker.schedule(deadline: .now() + tickSeconds, repeating: tickSeconds)
        ticker.setEventHandler { continuation.yield(.tick) }
        ticker.resume()
        Self.ticker = ticker

        return (stream, continuation)
    }
}

/// Fire-and-forget helper process (open, pbcopy). Output is discarded.
enum Shell {
    static func run(_ args: [String], stdin input: String? = nil) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        if let input {
            let pipe = Pipe()
            process.standardInput = pipe
            try? process.run()
            pipe.fileHandleForWriting.write(Data(input.utf8))
            try? pipe.fileHandleForWriting.close()
        } else {
            try? process.run()
        }
    }
}
