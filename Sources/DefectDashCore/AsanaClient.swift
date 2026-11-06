import Foundation

public protocol AsanaAPI: Sendable {
    func me() async throws -> AsanaUserRef
    func openTasks(inSection section: String) async throws -> [AsanaTask]
    func stories(forTask gid: String) async throws -> [AsanaStory]
    func taskName(gid: String) async throws -> String
}

/// GET-only Asana REST client. Builds no request other than GET.
public final class AsanaClient: AsanaAPI {
    private let pat: String
    private let session: URLSession
    private let baseURL: URL
    private let sleep: @Sendable (Int) async -> Void

    static let taskOptFields = [
        "name", "notes", "assignee.gid", "assignee.name", "due_on", "modified_at", "permalink_url",
        "custom_fields.name", "custom_fields.display_value", "dependents.gid",
    ].joined(separator: ",")

    static let storyOptFields = [
        "created_at", "created_by.gid", "created_by.name", "type", "resource_subtype", "text",
        "custom_field.name", "new_enum_value.name", "old_enum_value.name",
    ].joined(separator: ",")

    public init(pat: String,
                session: URLSession = .shared,
                baseURL: URL = URL(string: "https://app.asana.com/api/1.0")!,
                sleep: @escaping @Sendable (Int) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.pat = pat
        self.session = session
        self.baseURL = baseURL
        self.sleep = sleep
    }

    public func me() async throws -> AsanaUserRef {
        try await get("/users/me", query: []).data
    }

    public func openTasks(inSection section: String) async throws -> [AsanaTask] {
        try await pages("/sections/\(section)/tasks", query: [
            URLQueryItem(name: "completed_since", value: "now"),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "opt_fields", value: Self.taskOptFields),
        ])
    }

    public func stories(forTask gid: String) async throws -> [AsanaStory] {
        try await pages("/tasks/\(gid)/stories", query: [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "opt_fields", value: Self.storyOptFields),
        ])
    }

    public func taskName(gid: String) async throws -> String {
        struct NameOnly: Decodable, Sendable { let name: String }
        let envelope: AsanaEnvelope<NameOnly> = try await get("/tasks/\(gid)", query: [
            URLQueryItem(name: "opt_fields", value: "name"),
        ])
        return envelope.data.name
    }

    // MARK: - Private

    private func pages<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]) async throws -> [T] {
        var collected: [T] = []
        var offset: String? = nil
        repeat {
            var q = query
            if let offset { q.append(URLQueryItem(name: "offset", value: offset)) }
            let envelope: AsanaEnvelope<[T]> = try await get(path, query: q)
            collected.append(contentsOf: envelope.data)
            offset = envelope.nextPage?.offset
        } while offset != nil
        return collected
    }

    private func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]) async throws -> AsanaEnvelope<T> {
        let request = makeGET(path, query: query)
        var attempt = 0
        while true {
            attempt += 1
            let (data, response) = try await perform(request)
            switch response.statusCode {
            case 200..<300:
                do {
                    return try AsanaDecoding.makeDecoder().decode(AsanaEnvelope<T>.self, from: data)
                } catch {
                    throw AsanaError.transport("decode: \(error)")
                }
            case 401:
                throw AsanaError.unauthorized
            case 429:
                let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init) ?? 1
                if attempt >= 2 { throw AsanaError.rateLimited(retryAfter: retryAfter) }
                await sleep(retryAfter)
            default:
                throw AsanaError.http(response.statusCode, Self.errorMessage(from: data))
            }
        }
    }

    private func makeGET(_ path: String, query: [URLQueryItem]) -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AsanaError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AsanaError.transport("non-HTTP response")
        }
        return (data, http)
    }

    private static func errorMessage(from data: Data) -> String {
        if let envelope = try? JSONDecoder().decode(AsanaErrorEnvelope.self, from: data),
           let message = envelope.errors.first?.message {
            return message
        }
        return String(decoding: data.prefix(200), as: UTF8.self)
    }
}
