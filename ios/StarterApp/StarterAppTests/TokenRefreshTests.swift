import Foundation
import Testing
@testable import StarterApp

// MARK: - StubURLProtocol

/// A URLProtocol that dequeues pre-configured (statusCode, body) responses.
/// Thread-safe via NSLock. Use with a URLSession backed by URLSessionConfiguration.ephemeral.
///
/// Call `StubURLProtocol.reset()` before each test that uses it.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct StubResponse {
        let statusCode: Int
        let body: Data
    }

    // Class-level state — guarded by `lock`.
    private static let lock = NSLock()
    private static var queue: [StubResponse] = []
    private(set) static var requestCount = 0

    static func enqueue(statusCode: Int, body: Data) {
        lock.withLock { queue.append(StubResponse(statusCode: statusCode, body: body)) }
    }

    static func enqueue(statusCode: Int, json: String) {
        enqueue(statusCode: statusCode, body: Data(json.utf8))
    }

    static func reset() {
        lock.withLock { queue = []; requestCount = 0 }
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response: StubResponse = StubURLProtocol.lock.withLock {
            StubURLProtocol.requestCount += 1
            guard !StubURLProtocol.queue.isEmpty else {
                return StubResponse(statusCode: 500, body: Data("{\"detail\":\"StubURLProtocol queue empty\"}".utf8))
            }
            return StubURLProtocol.queue.removeFirst()
        }

        let httpResponse = HTTPURLResponse(
            url: request.url ?? URL(string: "http://stub")!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - MockAuthProvider

/// A lightweight AuthTokenProviding stub for unit tests.
@MainActor
final class MockAuthProvider: AuthTokenProviding {
    var accessToken: String?
    private(set) var refreshCount = 0
    var tokenAfterRefresh: String?   // what to return (and set as accessToken) on refresh

    init(accessToken: String? = "initial-token", tokenAfterRefresh: String? = "new-token") {
        self.accessToken = accessToken
        self.tokenAfterRefresh = tokenAfterRefresh
    }

    func refreshAccessToken() async -> String? {
        refreshCount += 1
        accessToken = tokenAfterRefresh
        return tokenAfterRefresh
    }
}

// MARK: - Test A: 401 → refresh → retry succeeds

@MainActor
@Suite("BackendAPIService — 401 retry")
struct BackendAPIServiceRetryTests {

    @Test("fetchNotes retries once on 401 and succeeds")
    func retryOn401Succeeds() async throws {
        StubURLProtocol.reset()

        // First response: 401
        StubURLProtocol.enqueue(statusCode: 401, json: #"{"detail":"Unauthorized"}"#)
        // Second response: 200 with an empty notes array
        StubURLProtocol.enqueue(statusCode: 200, json: "[]")

        let mock = MockAuthProvider(accessToken: "expired-token", tokenAfterRefresh: "fresh-token")
        let session = StubURLProtocol.makeSession()

        let notes = try await BackendAPIService.fetchNotes(auth: mock, session: session)

        #expect(notes.isEmpty)
        #expect(mock.refreshCount == 1)
        #expect(StubURLProtocol.requestCount == 2)  // one 401 + one retry
    }
}

// MARK: - Test B: AuthService single-flight refresh

@MainActor
@Suite("AuthService — single-flight refresh")
struct AuthServiceSingleFlightTests {

    @Test("5 concurrent refreshAccessToken() calls result in exactly one HTTP request")
    func singleFlightRefresh() async throws {
        StubURLProtocol.reset()

        // Valid TokenResponse JSON
        let tokenJSON = """
        {
            "access_token": "new-access-token",
            "refresh_token": "new-refresh-token",
            "token_type": "bearer"
        }
        """
        // Enqueue enough responses; only one should be consumed under single-flight.
        for _ in 0..<5 {
            StubURLProtocol.enqueue(statusCode: 200, json: tokenJSON)
        }

        // Ensure Keychain has a refresh token so doRefresh() doesn't immediately bail out.
        // Note: if the test environment disallows Keychain access this save may be a no-op
        // and the test will record 0 requests (all refreshes return nil). The assertion below
        // will catch that scenario — see report for details.
        KeychainTokenStore.clear()
        KeychainTokenStore.save(accessToken: "old-access", refreshToken: "stored-refresh")
        defer { KeychainTokenStore.clear() }

        let stubSession = StubURLProtocol.makeSession()
        let authService = AuthService(
            backendURL: URL(string: "http://stub-auth")!,
            session: stubSession
        )

        // Allow AuthService.init's `Task { await restoreSession() }` to complete.
        // restoreSession() will call refreshAccessToken() → doRefresh() → one HTTP hit.
        // We then reset the counter before our 5-concurrent test.
        try await Task.sleep(nanoseconds: 100_000_000)  // 100 ms

        // The init's restoreSession consumed one response; reset for the actual test.
        StubURLProtocol.reset()
        for _ in 0..<5 {
            StubURLProtocol.enqueue(statusCode: 200, json: tokenJSON)
        }

        // Fire 5 concurrent refreshes.
        await withTaskGroup(of: String?.self) { group in
            for _ in 0..<5 {
                group.addTask { await authService.refreshAccessToken() }
            }
            for await _ in group {}
        }

        // Single-flight: only one HTTP request should have been sent.
        #expect(StubURLProtocol.requestCount == 1)
    }
}

// MARK: - Test C: refresh failure propagates original error

@MainActor
@Suite("BackendAPIService — refresh failure")
struct BackendAPIServiceRefreshFailureTests {

    @Test("On 401, when refresh returns nil, original AppError.requestFailed(401) is rethrown")
    func refreshFailurePropagatesOriginalError() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(statusCode: 401, json: #"{"detail":"Unauthorized"}"#)

        // Mock returns nil on refresh (simulating expired refresh token / session cleared)
        let mock = MockAuthProvider(accessToken: "expired-token", tokenAfterRefresh: nil)
        let session = StubURLProtocol.makeSession()

        do {
            _ = try await BackendAPIService.fetchNotes(auth: mock, session: session)
            Issue.record("Expected an error to be thrown")
        } catch let error as AppError {
            guard case .requestFailed(let status, _) = error else {
                Issue.record("Expected AppError.requestFailed, got \(error)")
                return
            }
            #expect(status == 401)
        } catch {
            Issue.record("Expected AppError, got \(error)")
        }

        // Must not have retried after refresh failed
        #expect(StubURLProtocol.requestCount == 1)
        #expect(mock.refreshCount == 1)
    }
}

// MARK: - KeychainTokenStore round-trip

// The test target runs as a hosted test bundle inside StarterApp.app on the simulator,
// so Keychain access is available. If this test fails with OSStatus -34018 in a different
// CI environment (e.g. vanilla Xcode Cloud without entitlements), comment it out and note
// so in the report. The Keychain entitlement is inherited from the host app.
@Suite("KeychainTokenStore — round-trip")
struct KeychainTokenStoreTests {

    @Test("save → load → clear round-trip")
    func roundTrip() {
        KeychainTokenStore.clear()
        KeychainTokenStore.save(accessToken: "acc123", refreshToken: "ref456")

        #expect(KeychainTokenStore.loadAccessToken() == "acc123")
        #expect(KeychainTokenStore.loadRefreshToken() == "ref456")

        KeychainTokenStore.clear()

        #expect(KeychainTokenStore.loadAccessToken() == nil)
        #expect(KeychainTokenStore.loadRefreshToken() == nil)
    }
}
