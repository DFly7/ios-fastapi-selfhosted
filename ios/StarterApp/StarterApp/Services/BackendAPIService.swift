import Foundation

/// Response body for `GET /api/v1/secure-test` (file scope avoids SwiftLint nesting; must be ≥ internal for `SecureTestResponse` typealias).
struct SecureTestResponseBody: Decodable, Equatable {
    let message: String
    let userId: String?

    enum CodingKeys: String, CodingKey {
        case message
        case userId = "user_id"
    }
}

/// Calls the FastAPI backend using the Supabase JWT (`Authorization: Bearer …`).
enum BackendAPIService {
    typealias SecureTestResponse = SecureTestResponseBody

    // MARK: - Shared codecs

    /// FastAPI serialises `datetime` fields as ISO 8601 strings; the decoder must match.
    private static let decoder: JSONDecoder = {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        return jsonDecoder
    }()

    private static let encoder: JSONEncoder = {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        return jsonEncoder
    }()

    // MARK: - Core request helper

    /// Executes an authorized HTTP request and returns the raw response `Data`.
    ///
    /// - Parameters:
    ///   - method: HTTP method string ("GET", "POST", "PATCH", "DELETE", …).
    ///   - path: Path relative to `APIConfig.backendURL` (e.g. `"api/v1/me/profile"`).
    ///   - bodyData: Already-encoded JSON body, or `nil` for requests without a body.
    ///   - accessToken: Supabase JWT; throws `AppError.notSignedIn` when absent.
    /// - Throws: `AppError.notSignedIn`, `AppError.networkFailure`, or `AppError.requestFailed`.
    private static func request(
        method: String,
        path: String,
        bodyData: Data? = nil,
        accessToken: String?
    ) async throws -> Data {
        guard let accessToken, !accessToken.isEmpty else {
            throw AppError.notSignedIn
        }

        var urlRequest = URLRequest(url: APIConfig.backendURL.appending(path: path))
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let bodyData {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = bodyData
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw AppError.networkFailure(underlying: error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200 ... 299).contains(status) else {
            let fallback = String(data: data, encoding: .utf8) ?? ""
            let message = AppError.message(from: data, fallback: fallback)
            throw AppError.requestFailed(statusCode: status, message: message)
        }
        return data
    }

    /// Decodes `data` into `T`, wrapping any `DecodingError` as `AppError.decodingFailure`.
    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw AppError.decodingFailure(underlying: error)
        }
    }

    // MARK: - Auth / demo

    static func fetchSecureTest(accessToken: String?) async throws -> SecureTestResponse {
        let data = try await request(
            method: "GET",
            path: "api/v1/secure-test",
            accessToken: accessToken
        )
        return try decode(SecureTestResponse.self, from: data)
    }

    // MARK: - Profile

    static func fetchMyProfile(accessToken: String?) async throws -> ProfileOut {
        let data = try await request(method: "GET", path: "api/v1/me/profile", accessToken: accessToken)
        return try decode(ProfileOut.self, from: data)
    }

    /// PATCH /api/v1/me/profile — only non-nil fields are sent so the server only updates those columns.
    static func updateMyProfile(
        displayName: String? = nil,
        avatarUrl: String? = nil,
        accessToken: String?
    ) async throws -> ProfileOut {
        let payload = ProfileUpdate(displayName: displayName, avatarUrl: avatarUrl)
        let body = try encoder.encode(payload)
        let data = try await request(
            method: "PATCH",
            path: "api/v1/me/profile",
            bodyData: body,
            accessToken: accessToken
        )
        return try decode(ProfileOut.self, from: data)
    }

    // MARK: - Notes

    static func fetchNotes(accessToken: String?) async throws -> [NoteOut] {
        let data = try await request(method: "GET", path: "api/v1/me/notes", accessToken: accessToken)
        return try decode([NoteOut].self, from: data)
    }

    /// POST /api/v1/me/notes — returns the created note with its server-assigned id and timestamps.
    static func createNote(title: String, body: String? = nil, accessToken: String?) async throws -> NoteOut {
        let payload = NoteIn(title: title, body: body)
        let bodyData = try encoder.encode(payload)
        let data = try await request(
            method: "POST",
            path: "api/v1/me/notes",
            bodyData: bodyData,
            accessToken: accessToken
        )
        return try decode(NoteOut.self, from: data)
    }

    /// PATCH /api/v1/me/notes/{id} — only supplied fields are changed.
    static func updateNote(
        id: UUID,
        title: String? = nil,
        body: String? = nil,
        accessToken: String?
    ) async throws -> NoteOut {
        let payload = NoteUpdate(title: title, body: body)
        let bodyData = try encoder.encode(payload)
        let data = try await request(
            method: "PATCH",
            path: "api/v1/me/notes/\(id.uuidString.lowercased())",
            bodyData: bodyData,
            accessToken: accessToken
        )
        return try decode(NoteOut.self, from: data)
    }

    /// DELETE /api/v1/me/notes/{id} — server returns 204 No Content on success.
    static func deleteNote(id: UUID, accessToken: String?) async throws {
        _ = try await request(
            method: "DELETE",
            path: "api/v1/me/notes/\(id.uuidString.lowercased())",
            accessToken: accessToken
        )
    }
}
