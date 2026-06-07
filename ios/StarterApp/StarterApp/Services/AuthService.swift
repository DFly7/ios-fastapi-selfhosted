import AuthenticationServices
import Auth
import Foundation
import Observation
import OSLog
import PostHog
import SwiftUI
import Supabase

/// Supabase auth with Keychain session storage; subscribes to ``AuthClient/authStateChanges`` so
/// token refresh and remote sign-out stay in sync with ``isAuthenticated`` / user fields.
@Observable
@MainActor
final class AuthService {
    private(set) var isAuthenticated = false
    private(set) var userId: UUID?
    private(set) var userEmail: String?
    var isLoading = false
    var errorMessage: String?
    var infoMessage: String?
    /// True until the first ``AuthChangeEvent/initialSession`` is processed from ``authStateChanges``.
    private(set) var isCheckingInitialSession = true

    let client: SupabaseClient

    private var authStateTask: Task<Void, Never>?

    /// Cached access token — updated in ``applySession(_:)`` and cleared in ``clearSessionState()``.
    /// Reading ``client.auth.currentSession?.accessToken`` directly can transiently return nil
    /// right after ``signUp`` / ``signIn`` because the Supabase SDK's Keychain write is async.
    private(set) var accessToken: String?

    init(supabaseURL: URL, supabaseAnonKey: String, startSessionCheck: Bool = true) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true

        let options = SupabaseClientOptions(
            auth: .init(
                storage: KeychainLocalStorage(),
                emitLocalSessionAsInitialSession: true
            ),
            global: .init(session: URLSession(configuration: configuration))
        )

        self.client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: supabaseAnonKey,
            options: options
        )

        if startSessionCheck {
            startObservingAuthState()
        } else {
            isCheckingInitialSession = false
        }
    }

    private func startObservingAuthState() {
        authStateTask?.cancel()
        authStateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await (event, session) in self.client.auth.authStateChanges {
                await self.handleAuthStateChange(event: event, session: session)
                if event == .initialSession {
                    self.isCheckingInitialSession = false
                }
            }
        }
    }

    private func handleAuthStateChange(event: AuthChangeEvent, session: Session?) async {
        switch event {
        case .signedOut, .userDeleted:
            withAnimation { clearSessionState() }
        case .initialSession:
            if let session {
                if session.isExpired {
                    await refreshExpiredAndApply(session)
                } else {
                    withAnimation { applySession(session) }
                }
            } else {
                withAnimation { clearSessionState() }
            }
        case .signedIn, .tokenRefreshed, .userUpdated:
            if let session {
                withAnimation { applySession(session) }
            }
        case .passwordRecovery, .mfaChallengeVerified:
            break
        }
    }

    private func refreshExpiredAndApply(_ session: Session) async {
        AppLog.auth.info("Refreshing expired session")
        do {
            let refreshed = try await client.auth.refreshSession(refreshToken: session.refreshToken)
            withAnimation {
                applySession(refreshed)
            }
        } catch {
            AppLog.auth.error("refreshSession failed: \(error.localizedDescription, privacy: .public)")
            withAnimation {
                clearSessionState()
            }
        }
    }

    private func applySession(_ session: Session) {
        accessToken = session.accessToken
        userId = session.user.id
        userEmail = session.user.email
        isAuthenticated = true
        if APIConfig.isPostHogConfigured {
            var props: [String: Any] = [:]
            if let email = session.user.email {
                props["email"] = email
            }
            PostHogSDK.shared.identify(session.user.id.uuidString, userProperties: props)
        }
    }

    private func clearSessionState() {
        AppLog.auth.info("Session cleared")
        accessToken = nil
        isAuthenticated = false
        userId = nil
        userEmail = nil
        if APIConfig.isPostHogConfigured {
            PostHogSDK.shared.reset()
        }
    }

    /// Re-reads the current session after recoverable errors. ``authStateChanges`` normally updates state.
    func checkSession() async {
        do {
            var session = try await client.auth.session
            if session.isExpired {
                session = try await client.auth.refreshSession()
            }
            applySession(session)
        } catch {
            clearSessionState()
        }
    }

    func signOut() {
        AppLog.auth.info("Sign out requested")
        Task { @MainActor in
            // Intentional: errors from the remote sign-out call are silently
            // ignored with `try?`. Local session state is always cleared
            // regardless of whether the server request succeeds, so the user
            // is never left stuck on a signed-in screen due to a network
            // failure. The server-side session will expire on its own.
            // Do NOT convert this to `try await` — that would block sign-out
            // whenever the network is unavailable.
            try? await client.auth.signOut()
            withAnimation {
                clearSessionState()
            }
        }
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        infoMessage = nil
        defer { isLoading = false }

        do {
            let session = try await client.auth.signIn(email: email, password: password)
            applySession(session)
            AppLog.auth.info("Signed in")
        } catch {
            AppLog.auth.error("signIn failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = AuthService.userFacingMessage(for: error)
        }
    }

    func register(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        infoMessage = nil
        defer { isLoading = false }

        do {
            let response = try await client.auth.signUp(email: email, password: password)
            if let session = response.session {
                applySession(session)
                AppLog.auth.info("Registered and signed in")
            } else {
                infoMessage = "Check your email to confirm your account."
                AppLog.auth.info("Registered (confirm email)")
            }
        } catch {
            AppLog.auth.error("register failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = AuthService.userFacingMessage(for: error)
        }
    }

    func sendMagicLink(email: String) async {
        isLoading = true
        errorMessage = nil
        infoMessage = nil
        defer { isLoading = false }

        do {
            try await client.auth.signInWithOTP(
                email: email,
                redirectTo: URL(string: "\(APIConfig.authRedirectScheme)://magiclink")
            )
            infoMessage = "Check your email for the login link."
            AppLog.auth.info("Magic link sent")
        } catch {
            AppLog.auth.error("magic link failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = AuthService.userFacingMessage(for: error)
        }
    }

    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            _ = try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: "\(APIConfig.authRedirectScheme)://google")
            )
            AppLog.auth.info("Google OAuth opened")
        } catch {
            AppLog.auth.error("Google OAuth failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = AuthService.userFacingMessage(for: error)
        }
    }

    func signInWithApple(idToken: String, nonce: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
            )
            applySession(session)
            AppLog.auth.info("Signed in with Apple")
        } catch {
            AppLog.auth.error("Sign in with Apple failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = AuthService.userFacingMessage(for: error)
        }
    }

    func handleIncomingURL(_ url: URL) async {
        errorMessage = nil
        do {
            let session = try await client.auth.session(from: url)
            applySession(session)
            AppLog.auth.info("Signed in via deep link")
        } catch {
            AppLog.auth.error("Deep link session failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Could not complete sign-in from link."
        }
    }

    /// Maps Supabase, network, and system auth errors to UI-safe copy.
    ///
    /// Template: replace returned strings or extend the private mapper below to
    /// match your product voice and any new SDK error substrings you see in logs.
    static func userFacingMessage(for error: Error) -> String {
        friendlyMessage(for: error)
    }

    /// Substring heuristics for Supabase ``AuthError`` / server messages (already lowercased).
    private static func supabaseUserFacingMessage(normalizedDescription raw: String) -> String? {
        if raw.contains("invalid login credentials") || raw.contains("invalid email or password") {
            return "Incorrect email or password."
        }
        if raw.contains("email not confirmed") {
            return "Please confirm your email address before signing in."
        }
        if raw.contains("user already registered") || raw.contains("email address is already") {
            return "An account with this email already exists."
        }
        if raw.contains("password should be at least") || raw.contains("password is too short") {
            return "Password must be at least 6 characters."
        }
        if raw.contains("jwt expired") || raw.contains("session expired") {
            return "Your session has expired. Please sign in again."
        }
        if raw.contains("rate limit") || raw.contains("too many requests") {
            return "Too many attempts. Please wait a moment and try again."
        }
        if raw.contains("signup is disabled") {
            return "New registrations are currently disabled."
        }
        if raw.contains("invalid email") {
            return "Please enter a valid email address."
        }
        return nil
    }

    /// Maps raw Supabase / network / Sign in with Apple errors to short strings.
    ///
    /// Supabase SDK errors echo server text (e.g. "Invalid login credentials").
    /// Match on stable substrings; extend when new raw messages appear in support logs.
    private static func friendlyMessage(for error: Error) -> String {
        if let apple = error as? ASAuthorizationError {
            if apple.code == .canceled {
                return "Sign in was cancelled."
            }
            return "Could not sign in with Apple. Please try again."
        }

        // Network-level failures (no connection, timeout, etc.)
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "No internet connection. Please check your network and try again."
            case .timedOut:
                return "The request timed out. Please try again."
            default:
                return "A network error occurred. Please try again."
            }
        }

        // Supabase SDK ships AuthError whose localizedDescription echoes the
        // server message verbatim. Match on stable substrings rather than the
        // full string so minor wording changes on the server don't break this.
        let raw = error.localizedDescription.lowercased()
        if let message = supabaseUserFacingMessage(normalizedDescription: raw) {
            return message
        }

        // Unknown error — show a generic message so no raw SDK string ever
        // reaches the UI. Log `error.localizedDescription` here if you add
        // crash reporting (e.g. Sentry / PostHog) to preserve observability.
        return "Something went wrong. Please try again."
    }

    /// SwiftUI previews only; avoids mutating `private(set)` state from an extension in another file.
    fileprivate func applyPreviewAuthenticated(
        userId: UUID = UUID(),
        email: String = "preview@example.com"
    ) {
        isAuthenticated = true
        self.userId = userId
        userEmail = email
    }
}

extension AuthService {
    @MainActor
    static var previewSignedOut: AuthService {
        AuthService(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            supabaseAnonKey: "anon",
            startSessionCheck: false
        )
    }

    @MainActor
    static var previewAuthenticated: AuthService {
        let svc = AuthService(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            supabaseAnonKey: "anon",
            startSessionCheck: false
        )
        svc.applyPreviewAuthenticated()
        return svc
    }
}
