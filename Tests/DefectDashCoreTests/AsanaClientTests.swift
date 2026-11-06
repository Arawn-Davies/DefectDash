import Foundation
import XCTest
@testable import DefectDashCore

// MARK: - URLProtocol stub

/// Lock-protected mutable state shared with the URL loading system's background thread.
final class StubState: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private var _handler: (@Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data))?
    private var _calls: [String: Int] = [:]

    var requests: [URLRequest] { lock.withLock { _requests } }
    var handler: (@Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data))? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }
    func record(_ request: URLRequest) { lock.withLock { _requests.append(request) } }
    /// Returns the 1-based call count for `key` after incrementing it.
    func bump(_ key: String) -> Int {
        lock.withLock { _calls[key, default: 0] += 1; return _calls[key]! }
    }
    func reset() { lock.withLock { _requests = []; _handler = nil; _calls = [:] } }
}

final class StubURLProtocol: URLProtocol {
    static let state = StubState()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.state.record(request)
        guard let handler = Self.state.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let result = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: result.status, httpVersion: "HTTP/1.1", headerFields: result.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

actor SleepRecorder {
    var seconds: [Int] = []
    func add(_ s: Int) { seconds.append(s) }
}

// MARK: - Tests

final class AsanaClientTests: XCTestCase {
    let base = URL(string: "https://stub.test/api/1.0")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.state.reset()
    }

    func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func makeClient(sleep: SleepRecorder? = nil) -> AsanaClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        if let sleep {
            return AsanaClient(pat: "tok", session: session, baseURL: base, sleep: { await sleep.add($0) })
        }
        return AsanaClient(pat: "tok", session: session, baseURL: base, sleep: { _ in })
    }

    func json(_ string: String) -> Data { Data(string.utf8) }

    static let meBody = #"{"data":{"gid":"100","name":"Dev One"}}"#
    static let storiesBody = #"""
    {"data":[
      {"gid":"s1","created_at":"2026-11-04T10:52:52.000Z","created_by":{"gid":"77","name":"Manager"},
       "type":"system","resource_subtype":"enum_custom_field_changed","text":"changed Awaiting from \"Client\" to \"Vendor\"",
       "custom_field":{"gid":"902","name":"Awaiting"},"new_enum_value":{"gid":"1","name":"Vendor"},"old_enum_value":{"gid":"2","name":"Client"}},
      {"gid":"s2","created_at":"2026-11-03T12:53:33Z","created_by":{"gid":"100","name":"Dev One"},
       "type":"comment","resource_subtype":"comment_added","text":"Fixed on staging"}
    ],"next_page":null}
    """#

    /// Routes every endpoint the client knows to a canned 200.
    func installAllRoutes() throws {
        let page1 = try fixture("tasks-page1")
        let page2 = try fixture("tasks-page2")
        let me = json(Self.meBody)
        let stories = json(Self.storiesBody)
        let name = json(#"{"data":{"gid":"5001","name":"[BUG-184] Receipt time"}}"#)
        StubURLProtocol.state.handler = { request in
            let url = request.url!
            let path = url.path
            let query = url.query ?? ""
            if path.hasSuffix("/users/me") { return (200, [:], me) }
            if path.hasSuffix("/sections/S/tasks") {
                return (200, [:], query.contains("offset=OFF2") ? page2 : page1)
            }
            if path.hasSuffix("/stories") { return (200, [:], stories) }
            if path.hasSuffix("/tasks/5001") { return (200, [:], name) }
            return (404, [:], Data(#"{"errors":[{"message":"no route"}]}"#.utf8))
        }
    }

    func testOnlyGETIsEverSent() async throws {
        try installAllRoutes()
        let client = makeClient()
        _ = try await client.me()
        _ = try await client.openTasks(inSection: "S")
        _ = try await client.stories(forTask: "1")
        _ = try await client.taskName(gid: "5001")
        let requests = StubURLProtocol.state.requests
        XCTAssertEqual(requests.count, 5)   // me, page1, page2, stories, name
        for request in requests {
            XCTAssertEqual(request.httpMethod, "GET", request.url?.absoluteString ?? "")
            XCTAssertNil(request.httpBody)
        }
    }

    func testBearerHeaderAndCompletedSinceNow() async throws {
        try installAllRoutes()
        let client = makeClient()
        _ = try await client.openTasks(inSection: "S")
        let request = try XCTUnwrap(StubURLProtocol.state.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        let query = try XCTUnwrap(request.url?.query)
        XCTAssertTrue(query.contains("completed_since=now"), query)
        XCTAssertTrue(query.contains("limit=100"), query)
        XCTAssertTrue(query.contains("custom_fields.display_value"), query)
    }

    func testPaginationFollowsOffset() async throws {
        try installAllRoutes()
        let client = makeClient()
        let tasks = try await client.openTasks(inSection: "S")
        XCTAssertEqual(tasks.map(\.gid), ["1", "2"])
        XCTAssertEqual(tasks[0].customFields.first { $0.name == "Status" }?.displayValue, "4 · Retest")
        XCTAssertEqual(tasks[0].dueOn, "2026-10-26")
        XCTAssertEqual(tasks[0].dependents?.first?.gid, "5001")
        XCTAssertEqual(tasks[0].assignee, AsanaUserRef(gid: "100", name: "Dev One"))
        XCTAssertNil(tasks[1].assignee)
        XCTAssertNil(tasks[1].dueOn)
    }

    func testUnauthorizedMapsTo401() async throws {
        StubURLProtocol.state.handler = { _ in
            (401, [:], Data(#"{"errors":[{"message":"Not Authorized"}]}"#.utf8))
        }
        let client = makeClient()
        do {
            _ = try await client.me()
            XCTFail("expected throw")
        } catch let error as AsanaError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testRateLimitRetriesOnceThenSucceeds() async throws {
        let me = json(Self.meBody)
        StubURLProtocol.state.handler = { _ in
            if StubURLProtocol.state.bump("me") == 1 {
                return (429, ["Retry-After": "2"], Data(#"{"errors":[{"message":"Rate Limit Enforced"}]}"#.utf8))
            }
            return (200, [:], me)
        }
        let recorder = SleepRecorder()
        let client = makeClient(sleep: recorder)
        let user = try await client.me()
        XCTAssertEqual(user.name, "Dev One")
        let slept = await recorder.seconds
        XCTAssertEqual(slept, [2])
        XCTAssertEqual(StubURLProtocol.state.requests.count, 2)
    }

    func testStoriesDecodeEnumChange() async throws {
        try installAllRoutes()
        let client = makeClient()
        let stories = try await client.stories(forTask: "1")
        XCTAssertEqual(stories.count, 2)
        let change = stories[0]
        XCTAssertEqual(change.resourceSubtype, "enum_custom_field_changed")
        XCTAssertEqual(change.customField?.name, "Awaiting")
        XCTAssertEqual(change.newEnumValue?.name, "Vendor")
        XCTAssertEqual(change.oldEnumValue?.name, "Client")
        XCTAssertEqual(change.createdBy?.name, "Manager")
        XCTAssertEqual(change.createdAt, Date(timeIntervalSince1970: 1_793_789_572))   // 2026-11-04T10:52:52Z
        XCTAssertEqual(stories[1].createdAt, Date(timeIntervalSince1970: 1_793_710_413))  // 2026-11-03T12:53:33Z (no fractional seconds)
        XCTAssertNil(stories[1].customField)
    }
}
