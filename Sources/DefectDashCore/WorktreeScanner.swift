import Foundation

public struct WorktreeScanner: Sendable {
    public let git: GitRunning
    public let maxConcurrent: Int

    public init(git: GitRunning, maxConcurrent: Int = 8) {
        self.git = git
        self.maxConcurrent = max(1, maxConcurrent)
    }

    // MARK: - Enumeration

    /// Walks `root` up to `maxDepth` levels, skipping dot-directories, stopping at any directory containing `.git`.
    /// `system` is the first path component under root; `relativePath` is the rest.
    public func enumerate(root: URL, maxDepth: Int = 4) -> [(path: URL, system: String, relativePath: String)] {
        var found: [(path: URL, system: String, relativePath: String)] = []
        walk(dir: root, components: [], depth: 0, maxDepth: maxDepth, into: &found)
        return found.sorted { $0.path.path < $1.path.path }
    }

    private func walk(dir: URL, components: [String], depth: Int, maxDepth: Int,
                      into found: inout [(path: URL, system: String, relativePath: String)]) {
        guard depth <= maxDepth else { return }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                        options: [.skipsHiddenFiles]) else { return }
        for entry in entries {
            let name = entry.lastPathComponent
            guard !name.hasPrefix("."),
                  let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let path = components + [name]
            if fm.fileExists(atPath: entry.appending(path: ".git").path) {
                guard let system = path.first else { continue }
                found.append((path: entry, system: system, relativePath: path.dropFirst().joined(separator: "/")))
                continue
            }
            walk(dir: entry, components: path, depth: depth + 1, maxDepth: maxDepth, into: &found)
        }
    }

    // MARK: - Reading one repository

    public func readHost(_ path: URL) async -> RepoState {
        await readRepo(path, label: "host")
    }

    /// Reads every initialised submodule: declared in `.gitmodules` (via `config --file`) and checked out (has `.git`).
    /// `submodule foreach` is a shell script costing ~200 ms per call; `config` is ~10 ms.
    public func readSubmodules(_ path: URL) async -> [RepoState] {
        let names = await submodulePaths(path)
        guard !names.isEmpty else { return [] }
        // user.email is resolved once from the host; submodules inherit the same global/user config.
        let email = (try? await git.run(["config", "user.email"], in: path))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return await Self.mapConcurrently(names, limit: maxConcurrent) { name in
            await readRepo(path.appending(path: name, directoryHint: .isDirectory), label: name, email: email ?? "")
        }
    }

    func submodulePaths(_ path: URL) async -> [String] {
        let modulesFile = path.appending(path: ".gitmodules")
        guard FileManager.default.fileExists(atPath: modulesFile.path),
              let listing = try? await git.run(["config", "--file", ".gitmodules", "--get-regexp", "^submodule\\..*\\.path$"], in: path)
        else { return [] }
        return listing.split(separator: "\n").compactMap { line -> String? in
            // "submodule.engines/foo.path engines/foo"
            guard let space = line.firstIndex(of: " ") else { return nil }
            let sub = line[line.index(after: space)...].trimmingCharacters(in: .whitespaces)
            guard !sub.isEmpty,
                  FileManager.default.fileExists(atPath: path.appending(path: sub).appending(path: ".git").path)
            else { return nil }
            return sub
        }
    }

    /// `email` nil = look it up with `config user.email`; "" = unknown, skip the author query.
    private func readRepo(_ path: URL, label: String, email: String? = nil) async -> RepoState {
        func output(_ args: [String]) async -> Result<String, GitError> {
            do {
                return .success(try await git.run(args, in: path).trimmingCharacters(in: .whitespacesAndNewlines))
            } catch let error as GitError {
                return .failure(error)
            } catch {
                return .failure(.launch(error.localizedDescription))
            }
        }

        // One `status --porcelain=v2 --branch` gives branch, detached state, ahead/behind and dirtiness.
        // `--ignore-submodules=dirty` still reports a moved submodule pointer but skips the child `git status`
        // per submodule (≈100 ms each); submodule contents are read separately by `readSubmodules`.
        let status = await output(["status", "--porcelain=v2", "--branch", "--untracked-files=no", "--ignore-submodules=dirty"])
        var error: String? = nil
        if case let .failure(failure) = status {
            if case let .failed(_, stderr) = failure { error = stderr } else { error = "\(failure)" }
        }
        var branch: String? = nil
        var dirty = false
        var ahead: Int? = nil
        var behind: Int? = nil
        if let text = try? status.get() {
            for line in text.split(separator: "\n") {
                if line.hasPrefix("# branch.head ") {
                    let name = String(line.dropFirst("# branch.head ".count))
                    branch = name == "(detached)" ? nil : name
                } else if line.hasPrefix("# branch.ab ") {
                    let parts = line.dropFirst("# branch.ab ".count).split(separator: " ")
                    if parts.count == 2 {
                        ahead = Int(parts[0].dropFirst())    // "+3"
                        behind = Int(parts[1].dropFirst())   // "-1"
                    }
                } else if !line.hasPrefix("#") {
                    dirty = true
                }
            }
        }

        var lastCommitAt: Date? = nil
        var authorEmail: String? = nil
        var subject: String? = nil
        if let line = try? await output(["log", "-1", "--format=%ct%x09%ae%x09%s"]).get(), !line.isEmpty {
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count >= 1, let ts = TimeInterval(parts[0]) { lastCommitAt = Date(timeIntervalSince1970: ts) }
            if parts.count >= 2 { authorEmail = String(parts[1]) }
            if parts.count >= 3 { subject = String(parts[2]) }
        }

        var myLastCommitAt: Date? = nil
        let resolvedEmail: String
        if let email {
            resolvedEmail = email
        } else {
            resolvedEmail = (try? await output(["config", "user.email"]).get()) ?? ""
        }
        if !resolvedEmail.isEmpty,
           let line = try? await output(["log", "-1", "--fixed-strings", "--author=\(resolvedEmail)", "--format=%ct"]).get(),
           let ts = TimeInterval(line) {
            myLastCommitAt = Date(timeIntervalSince1970: ts)
        }

        return RepoState(path: path, label: label, branch: branch, dirty: dirty, ahead: ahead, behind: behind,
                         lastCommitAt: lastCommitAt, lastCommitAuthorEmail: authorEmail, lastCommitSubject: subject,
                         myLastCommitAt: myLastCommitAt, error: error)
    }

    // MARK: - Whole-root scans

    /// Host reads only; `submodules` is empty on every result.
    public func scanHosts(root: URL) async -> [Worktree] {
        let entries = enumerate(root: root)
        return await Self.mapConcurrently(entries, limit: maxConcurrent) { entry in
            let host = await readHost(entry.path)
            return Worktree(path: entry.path, system: entry.system, relativePath: entry.relativePath, host: host)
        }
    }

    /// Reads submodules for the worktrees the predicate selects; others pass through unchanged.
    public func enrich(_ worktrees: [Worktree], where shouldDeepRead: @Sendable (Worktree) -> Bool) async -> [Worktree] {
        let selected = worktrees.map(shouldDeepRead)
        return await Self.mapConcurrently(Array(zip(worktrees, selected)), limit: maxConcurrent) { pair in
            var (worktree, deep) = pair
            if deep { worktree.submodules = await readSubmodules(worktree.path) }
            return worktree
        }
    }

    // MARK: - Concurrency

    /// Order-preserving concurrent map with at most `limit` operations in flight.
    static func mapConcurrently<T: Sendable, R: Sendable>(_ items: [T], limit: Int,
                                                          _ transform: @Sendable @escaping (T) async -> R) async -> [R] {
        guard !items.isEmpty else { return [] }
        var results: [R?] = Array(repeating: nil, count: items.count)
        await withTaskGroup(of: (Int, R).self) { group in
            var next = 0
            func launch() {
                let index = next
                let item = items[index]
                next += 1
                group.addTask { (index, await transform(item)) }
            }
            while next < items.count, next < limit { launch() }
            for await (index, result) in group {
                results[index] = result
                if next < items.count { launch() }
            }
        }
        return results.map { $0! }
    }
}
