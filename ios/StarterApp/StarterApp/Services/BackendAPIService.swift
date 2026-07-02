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

/// Calls the FastAPI backend using a JWT (`Authorization: Bearer …`).
/// All public methods accept an `AuthTokenProviding` rather than a raw token so the
/// service can automatically refresh an expired token on HTTP 401 and retry once.
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

    // MARK: - Core request helpers

    /// Raw HTTP send. Takes an explicit non-optional token; does NOT perform refresh.
    /// - Throws: `AppError.networkFailure` on transport error, `AppError.requestFailed` on non-2xx.
    private static func send(
        method: String,
        path: String,
        bodyData: Data? = nil,
        token: String,
        session: URLSession
    ) async throws -> Data {
        var urlRequest = URLRequest(url: APIConfig.backendURL.appending(path: path))
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let bodyData {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = bodyData
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
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

    /// Authorized request with automatic single-retry on HTTP 401.
    ///
    /// Flow: send with current token → on 401, call `auth.refreshAccessToken()` → send once more
    /// with the new token. If refresh fails (returns nil) the original 401 error is rethrown.
    private static func request(
        method: String,
        path: String,
        bodyData: Data? = nil,
        auth: any AuthTokenProviding,
        session: URLSession
    ) async throws -> Data {
        guard let token = auth.accessToken, !token.isEmpty else { throw AppError.notSignedIn }
        do {
            return try await send(method: method, path: path, bodyData: bodyData, token: token, session: session)
        } catch let original as AppError {
            guard case .requestFailed(401, _) = original else { throw original }   // only refresh on 401
            guard let newToken = await auth.refreshAccessToken() else { throw original }  // refresh failed → rethrow
            return try await send(method: method, path: path, bodyData: bodyData, token: newToken, session: session)  // retry once
        }
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

    static func fetchSecureTest(auth: any AuthTokenProviding, session: URLSession = .shared) async throws -> SecureTestResponse {
        let data = try await request(
            method: "GET",
            path: "api/v1/secure-test",
            auth: auth,
            session: session
        )
        return try decode(SecureTestResponse.self, from: data)
    }

    // MARK: - Profile

    static func fetchMyProfile(auth: any AuthTokenProviding, session: URLSession = .shared) async throws -> ProfileOut {
        let data = try await request(method: "GET", path: "api/v1/me/profile", auth: auth, session: session)
        return try decode(ProfileOut.self, from: data)
    }

    /// PATCH /api/v1/me/profile — only non-nil fields are sent so the server only updates those columns.
    static func updateMyProfile(
        displayName: String? = nil,
        avatarUrl: String? = nil,
        auth: any AuthTokenProviding,
        session: URLSession = .shared
    ) async throws -> ProfileOut {
        let payload = ProfileUpdate(displayName: displayName, avatarUrl: avatarUrl)
        let body = try encoder.encode(payload)
        let data = try await request(
            method: "PATCH",
            path: "api/v1/me/profile",
            bodyData: body,
            auth: auth,
            session: session
        )
        return try decode(ProfileOut.self, from: data)
    }

    // MARK: - Notes

    static func fetchNotes(auth: any AuthTokenProviding, session: URLSession = .shared) async throws -> [NoteOut] {
        let data = try await request(method: "GET", path: "api/v1/me/notes", auth: auth, session: session)
        return try decode([NoteOut].self, from: data)
    }

    /// POST /api/v1/me/notes — returns the created note with its server-assigned id and timestamps.
    static func createNote(title: String, body: String? = nil, auth: any AuthTokenProviding, session: URLSession = .shared) async throws -> NoteOut {
        let payload = NoteIn(title: title, body: body)
        let bodyData = try encoder.encode(payload)
        let data = try await request(
            method: "POST",
            path: "api/v1/me/notes",
            bodyData: bodyData,
            auth: auth,
            session: session
        )
        return try decode(NoteOut.self, from: data)
    }

    /// PATCH /api/v1/me/notes/{id} — only supplied fields are changed.
    static func updateNote(
        id: UUID,
        title: String? = nil,
        body: String? = nil,
        auth: any AuthTokenProviding,
        session: URLSession = .shared
    ) async throws -> NoteOut {
        let payload = NoteUpdate(title: title, body: body)
        let bodyData = try encoder.encode(payload)
        let data = try await request(
            method: "PATCH",
            path: "api/v1/me/notes/\(id.uuidString.lowercased())",
            bodyData: bodyData,
            auth: auth,
            session: session
        )
        return try decode(NoteOut.self, from: data)
    }

    /// DELETE /api/v1/me/notes/{id} — server returns 204 No Content on success.
    static func deleteNote(id: UUID, auth: any AuthTokenProviding, session: URLSession = .shared) async throws {
        _ = try await request(
            method: "DELETE",
            path: "api/v1/me/notes/\(id.uuidString.lowercased())",
            auth: auth,
            session: session
        )
    }
}
