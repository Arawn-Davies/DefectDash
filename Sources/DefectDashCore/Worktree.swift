import Foundation

/// The read-only git state of one repository: a worktree's host checkout or one of its submodules.
public struct RepoState: Sendable, Equatable {
    public let path: URL
    public let label: String                 // "host" or the submodule path
    public let branch: String?               // nil when detached
    public let dirty: Bool
    public let ahead: Int?                   // nil = no upstream
    public let behind: Int?
    public let lastCommitAt: Date?
    public let lastCommitAuthorEmail: String?
    public let lastCommitSubject: String?
    public let myLastCommitAt: Date?
    public let error: String?

    public init(path: URL, label: String, branch: String?, dirty: Bool, ahead: Int?, behind: Int?,
                lastCommitAt: Date?, lastCommitAuthorEmail: String?, lastCommitSubject: String?,
                myLastCommitAt: Date?, error: String?) {
        self.path = path
        self.label = label
        self.branch = branch
        self.dirty = dirty
        self.ahead = ahead
        self.behind = behind
        self.lastCommitAt = lastCommitAt
        self.lastCommitAuthorEmail = lastCommitAuthorEmail
        self.lastCommitSubject = lastCommitSubject
        self.myLastCommitAt = myLastCommitAt
        self.error = error
    }
}

public struct Worktree: Sendable, Identifiable, Equatable {
    public var id: String { path.path }
    public let path: URL
    public let system: String
    public let relativePath: String
    public let host: RepoState
    public var submodules: [RepoState]

    public init(path: URL, system: String, relativePath: String, host: RepoState, submodules: [RepoState] = []) {
        self.path = path
        self.system = system
        self.relativePath = relativePath
        self.host = host
        self.submodules = submodules
    }

    public var branch: String? { host.branch }
    public var bugNumber: Int? { BugNumber.fromWorktree(relativePath: relativePath, branch: host.branch) }

    private var allRepos: [RepoState] { [host] + submodules }

    /// Host or any submodule has modified tracked files.
    public var dirty: Bool { allRepos.contains { $0.dirty } }
    /// Newest commit across host and submodules.
    public var lastCommitAt: Date? { allRepos.compactMap(\.lastCommitAt).max() }
    /// Newest commit of mine across host and submodules.
    public var myLastCommitAt: Date? { allRepos.compactMap(\.myLastCommitAt).max() }
    public var anySubmoduleAhead: Bool { submodules.contains { ($0.ahead ?? 0) > 0 } }
}
