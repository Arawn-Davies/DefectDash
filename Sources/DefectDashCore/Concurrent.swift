import Foundation

public enum Concurrent {
    /// Order-preserving concurrent map with at most `limit` operations in flight. The first error cancels the rest.
    public static func map<T: Sendable, R: Sendable>(_ items: [T], limit: Int,
                                                     _ transform: @Sendable @escaping (T) async throws -> R) async throws -> [R] {
        guard !items.isEmpty else { return [] }
        let cap = max(1, limit)
        var results: [R?] = Array(repeating: nil, count: items.count)
        try await withThrowingTaskGroup(of: (Int, R).self) { group in
            var next = 0
            func launch() {
                let index = next
                let item = items[index]
                next += 1
                group.addTask { (index, try await transform(item)) }
            }
            while next < items.count, next < cap { launch() }
            for try await (index, result) in group {
                results[index] = result
                if next < items.count { launch() }
            }
        }
        return results.map { $0! }
    }
}
