import Foundation

/// The last successful refresh, persisted so the next launch can show something immediately
/// while a fresh refresh runs in the background.
public struct CachedRefresh: Codable, Sendable {
    public let items: [WorkItem]
    public let otherWorktrees: [Worktree]
    public let me: AsanaUserRef
    public let savedAt: Date

    public init(items: [WorkItem], otherWorktrees: [Worktree], me: AsanaUserRef, savedAt: Date) {
        self.items = items
        self.otherWorktrees = otherWorktrees
        self.me = me
        self.savedAt = savedAt
    }
}

public enum RefreshCache {
    /// `~/Library/Caches/<bundle id>/last-refresh.json`
    public static var defaultURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Caches")
        return caches.appending(path: Settings.bundleIdentifier, directoryHint: .isDirectory)
            .appending(path: "last-refresh.json")
    }

    /// Writes atomically with mode 0600; creates the parent directory on demand. The token is never part of this.
    public static func save(_ result: RefreshResult, savedAt: Date = Date(), to url: URL = defaultURL) throws {
        let payload = CachedRefresh(items: result.items, otherWorktrees: result.otherWorktrees, me: result.me, savedAt: savedAt)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// nil when there is no cache or it cannot be decoded (for example after a model change).
    public static func load(from url: URL = defaultURL) -> CachedRefresh? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedRefresh.self, from: data)
    }
}
