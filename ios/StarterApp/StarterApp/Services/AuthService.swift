import Foundation
import Observation
import OSLog
import PostHog
import SwiftUI

// MARK: - Auth seam protocol

/// A single-flight token provider. BackendAPIService uses this to refresh expired tokens
/// without knowing about AuthService internals.
@MainActor
protocol AuthTokenProviding: AnyObject {
    /// The current access token, or nil if the user is not signed in.
    var accessToken: String? { get }
    /// Refreshes the access token using the stored refresh token.
    /// Concurrent calls while a refresh is in flight join the same underlying Task.
    /// Returns the new token, or nil if refresh failed (session has been cleared).
    func refreshAccessToken() async -> String?
}

@Observable
@MainActor
final class AuthService {
    private(set) var isAuthenticated = false
    private(set) var userId: UUID?
    private(set) var userEmail: String?
    var isLoading = false
    var errorMessage: String?
    var infoMessage: String?
    private(set) var isCheckingInitialSession = true
    private(set) var accessToken: String?

    private let backendURL: URL
    private let session: URLSession

    // MARK: - Single-flight refresh state

    private var refreshTask: Task<String?, Never>?

    init(backendURL: URL, session: URLSession = .shared) {
        self.backendURL = backendURL
        self.session = session
        Task { await restoreSession() }
    }

    // MARK: – Session restore

    private func restoreSession() async {
        defer { isCheckingInitialSession = false }
        guard KeychainTokenStore.loadRefreshToken() != nil else {
            clearSessionState()
            return
        }
        _ = await refreshAccessToken()
    }

    // MARK: – Public API

    func signIn(email: String, password: String) async {
        isLoading = true; errorMessage = nil; infoMessage = nil
        defer { isLoading = false }
        do {
            let resp: TokenResponse = try await post(
                path: "/api/v1/auth/token",
                body: ["email": email, "password": password]
            )
            applyTokens(resp)
            AppLog.auth.info("Signed in")
        } catch {
            errorMessage = friendlyMessage(error)
        }
    }

    func register(email: String, password: String) async {
        isLoading = true; errorMessage = nil; infoMessage = nil
        defer { isLoading = false }
        do {
            let resp: TokenResponse = try await post(
                path: "/api/v1/auth/register",
                body: ["email": email, "password": password]
            )
            applyTokens(resp)
            AppLog.auth.info("Registered")
        } catch {
            errorMessage = friendlyMessage(error)
        }
    }

    func signOut() {
        Task {
            if let refresh = KeychainTokenStore.loadRefreshToken() {
                _ = try? await post(path: "/api/v1/auth/logout", body: ["refresh_token": refresh]) as EmptyResponse
            }
            withAnimation { clearSessionState() }
        }
    }

    // MARK: – AuthTokenProviding conformance helpers

    func refreshAccessToken() async -> String? {
        if let existing = refreshTask { return await existing.value }  // join in-flight refresh
        let task = Task<String?, Never> { [weak self] in
            await self?.doRefresh() ?? nil
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func doRefresh() async -> String? {
        guard let refresh = KeychainTokenStore.loadRefreshToken() else {
            clearSessionState()
            return nil
        }
        do {
            let resp: TokenResponse = try await post(
                path: "/api/v1/auth/refresh",
                body: ["refresh_token": refresh]
            )
            applyTokens(resp)
            return resp.accessToken
        } catch {
            AppLog.auth.error("Token refresh failed: \(error.localizedDescription, privacy: .public)")
            withAnimation { clearSessionState() }
            return nil
        }
    }

    // MARK: – Internal

    private func applyTokens(_ resp: TokenResponse) {
        KeychainTokenStore.save(accessToken: resp.accessToken, refreshToken: resp.refreshToken)
        accessToken = resp.accessToken
        if let payload = decodeJWTPayload(resp.accessToken) {
            userId = UUID(uuidString: payload["sub"] as? String ?? "")
            userEmail = payload["email"] as? String
        }
        isAuthenticated = true
        if APIConfig.isPostHogConfigured, let uid = userId {
            var props: [String: Any] = [:]
            if let email = userEmail { props["email"] = email }
            PostHogSDK.shared.identify(uid.uuidString, userProperties: props)
        }
    }

    private func clearSessionState() {
        KeychainTokenStore.clear()
        accessToken = nil
        isAuthenticated = false
        userId = nil
        userEmail = nil
        if APIConfig.isPostHogConfigured { PostHogSDK.shared.reset() }
    }

    // MARK: – HTTP helpers

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func post<B: Encodable, R: Decodable>(path: String, body: B) async throws -> R {
        var req = URLRequest(url: backendURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AuthError.network }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.message
            throw AuthError.server(http.statusCode, msg ?? "Unknown error")
        }
        return try Self.decoder.decode(R.self, from: data)
    }

    private func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    func signInWithApple(idToken: String, nonce: String) async {
        isLoading = true; errorMessage = nil; infoMessage = nil
        defer { isLoading = false }
        errorMessage = "Apple Sign In is not yet implemented."
    }

    func signInWithGoogle() async {
        isLoading = true; errorMessage = nil; infoMessage = nil
        defer { isLoading = false }
        errorMessage = "Google Sign In is not yet implemented."
    }

    func sendMagicLink(email: String) async {
        isLoading = true; errorMessage = nil; infoMessage = nil
        defer { isLoading = false }
        errorMessage = "Magic Link is not yet implemented."
    }

    static func userFacingMessage(for error: Error) -> String {
        error.localizedDescription
    }

    private func friendlyMessage(_ error: Error) -> String {
        if let authErr = error as? AuthError {
            switch authErr {
            case .server(409, _): return "An account with this email already exists."
            case .server(401, _): return "Incorrect email or password."
            case .server(403, _): return "Account disabled."
            case .server(429, _):
                return "Slow down! You've made too many requests. Please try again shortly."
            case .server: return "Something went wrong. Please try again."
            case .network: return "No internet connection. Please check your network."
            }
        }
        if let urlErr = error as? URLError, urlErr.code == .notConnectedToInternet {
            return "No internet connection. Please check your network."
        }
        return "Something went wrong. Please try again."
    }

    // MARK: – Preview helpers

    fileprivate func applyPreviewAuthenticated(userId: UUID = UUID(), email: String = "preview@example.com") {
        isAuthenticated = true; self.userId = userId; userEmail = email
    }
}

// MARK: – AuthTokenProviding conformance

extension AuthService: AuthTokenProviding {}

// MARK: – Supporting types

private struct APIErrorBody: Decodable {
    let detail: String?
    let error: String?

    var message: String? {
        if let detail, !detail.isEmpty { return detail }
        if let error, !error.isEmpty { return error }
        return nil
    }
}
private struct EmptyResponse: Decodable {}

private enum AuthError: Error {
    case server(Int, String)
    case network
}

// MARK: – Previews

extension AuthService {
    @MainActor static var previewSignedOut: AuthService {
        AuthService(backendURL: URL(string: "http://localhost:8000")!)
    }

    @MainActor static var previewAuthenticated: AuthService {
        let svc = AuthService(backendURL: URL(string: "http://localhost:8000")!)
        svc.applyPreviewAuthenticated()
        return svc
    }
}
