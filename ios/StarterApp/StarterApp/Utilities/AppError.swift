import Foundation

/// Typed application errors surfaced from the network layer to the UI.
///
/// Add new cases here when you introduce new failure modes (e.g. `.unauthorized`, `.offline`).
/// Every case produces a user-facing `errorDescription` via `LocalizedError`, so views can
/// call `error.localizedDescription` and always show something meaningful.
///
/// ### FastAPI 422 – business-rule violations
/// FastAPI returns `{"detail": "…"}` for custom `HTTPException`s and
/// `{"detail": [{…}]}` for Pydantic validation errors. `AppError.message(from:fallback:)`
/// parses both shapes so the user sees a readable message instead of raw JSON.
enum AppError: LocalizedError {

    /// No access token found — the user needs to sign in.
    case notSignedIn

    /// The server replied with a non-2xx HTTP status.
    /// `message` is extracted from the response body (FastAPI `detail` field when available).
    case requestFailed(statusCode: Int, message: String)

    /// A URLSession-level failure (no internet, timeout, DNS lookup failed, etc.).
    case networkFailure(underlying: Error)

    /// The HTTP response was successful but the payload couldn't be decoded into the expected type.
    case decodingFailure(underlying: Error)

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You're not signed in. Please sign in and try again."

        case let .requestFailed(statusCode, message):
            guard !message.isEmpty else {
                return "Request failed (HTTP \(statusCode))."
            }
            // 422 messages from FastAPI are already user-readable (business rules / validation).
            if statusCode == 422 { return message }
            return "HTTP \(statusCode): \(message)"

        case .networkFailure:
            return "Network connection failed. Check your connection and try again."

        case .decodingFailure:
            return "The server returned an unexpected response format."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .networkFailure:
            return "Make sure you're connected to the internet, then retry."
        default:
            return nil
        }
    }

    // MARK: - FastAPI error body parser

    /// Extracts a user-readable message from a FastAPI error response body.
    ///
    /// FastAPI serialises errors in two shapes:
    /// - `{"detail": "Human-readable string"}` — raised via `HTTPException(detail=…)`
    /// - `{"detail": [{"loc": […], "msg": "…", "type": "…"}]}` — Pydantic validation errors
    ///
    /// Falls back to `fallback` when neither shape matches (e.g. plain-text or empty body).
    static func message(from data: Data, fallback: String) -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let detail = json["detail"]
        else { return fallback }

        if let string = detail as? String, !string.isEmpty {
            return string
        }
        if let array = detail as? [[String: Any]] {
            let messages = array.compactMap { $0["msg"] as? String }
            if !messages.isEmpty { return messages.joined(separator: "; ") }
        }
        return fallback
    }
}
