import Foundation

public protocol GitRunning: Sendable {
    /// Runs `git -C <dir> <args>` and returns stdout. Throws `GitError.failed` on a non-zero exit.
    func run(_ args: [String], in dir: URL) async throws -> String
}

public enum GitError: Error, Equatable {
    case failed(status: Int32, stderr: String)
    case launch(String)
}

/// Runs the system git binary. Only ever invoked with read-only subcommands by this package.
public struct ProcessGitRunner: GitRunning {
    public let gitPath: String
    public let timeout: TimeInterval

    public init(gitPath: String = ProcessGitRunner.defaultGitPath, timeout: TimeInterval = 60) {
        self.gitPath = gitPath
        self.timeout = timeout
    }

    /// `/usr/bin/git` is Apple's xcrun shim and adds tens of milliseconds to every launch; prefer the real binary.
    public static let defaultGitPath: String = {
        let candidates = [
            "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
            "/Library/Developer/CommandLineTools/usr/bin/git",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/git"
    }()

    public func run(_ args: [String], in dir: URL) async throws -> String {
        try await run(args, in: dir, environment: [:])
    }

    public func run(_ args: [String], in dir: URL, environment extra: [String: String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["-C", dir.path] + args
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["LC_ALL"] = "C"
        for (k, v) in extra { env[k] = v }
        process.environment = env
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        // Both pipes are drained on GCD threads from before launch, so a child that writes more than the
        // pipe buffer (a very dirty `status --porcelain`) can never block on a full pipe and fail to exit.
        let outSink = DataSink(stdout.fileHandleForReading)
        let errSink = DataSink(stderr.fileHandleForReading)

        // Termination is observed through the handler, set before launch so an early exit cannot be missed
        // (`waitUntilExit` from a cooperative thread has been seen to hang after the child is already gone).
        let box = ProcessBox(process)
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: GitError.launch(error.localizedDescription))
                return
            }
            // Safety net: a git that hangs (network, lock, prompt) is killed rather than stalling the refresh.
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if box.process.isRunning { box.process.terminate() }
            }
        }

        let (out, err) = await (outSink.data(), errSink.data())

        guard status == 0 else {
            throw GitError.failed(status: status,
                                  stderr: String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: out, as: UTF8.self)
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}

/// Reads a file handle to EOF on a global dispatch queue, starting immediately.
private final class DataSink: @unchecked Sendable {
    private let group = DispatchGroup()
    private var result = Data()

    init(_ handle: FileHandle) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            self.result = handle.readDataToEndOfFile()
            self.group.leave()
        }
    }

    func data() async -> Data {
        await withCheckedContinuation { continuation in
            group.notify(queue: .global()) { continuation.resume(returning: self.result) }
        }
    }
}
