import Foundation

struct SyncUser: Codable, Equatable {
    let id: String
    let email: String
    let role: String
}

struct SessionResponse: Decodable {
    let token: String
    let expires: Double
    let user: SyncUser
}

struct PreloginResponse: Decodable {
    let salt: String
    let iterations: Int
}

struct ChangeItem: Decodable {
    let id: String
    let kind: String
    let version: Int
    let size: Int
    let deleted: Int
    let cursor: Int
}

struct ChangesResponse: Decodable {
    let changes: [ChangeItem]
    let cursor: Int
    let more: Bool
}

struct PutResponse: Decodable {
    let version: Int
    let conflict: Bool
}

struct StatsResponse: Decodable {
    let objects: Int
    let bytes: Int
    let limit: Int
}

enum SyncError: LocalizedError {
    case server(Int, String)
    case offline(String)
    case badAddress

    var errorDescription: String? {
        switch self {
        case .server(_, let message): message
        case .offline(let message): message
        case .badAddress: "Enter the server address first. It starts with https://"
        }
    }

    var isUnauthorized: Bool {
        if case .server(401, _) = self { return true }
        return false
    }

    var isNotFound: Bool {
        if case .server(404, _) = self { return true }
        return false
    }
}

/// Talks to the Inkwell sync Worker. Everything uploaded through here is already encrypted.
final class SyncAPI {
    let base: String
    var token: String?

    /// Accepts "https://example.workers.dev", with or without a trailing slash.
    init?(address: String, token: String? = nil) {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard text.lowercased().hasPrefix("https://"), URL(string: text) != nil else { return nil }
        base = text
        self.token = token
    }

    private struct ErrorBody: Decodable {
        let error: String?
        let detail: String?
    }

    private func send(_ path: String, method: String = "GET", json: (any Encodable)? = nil, body: Data? = nil,
                      headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: base + path) else { throw SyncError.badAddress }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }

        let data: Data
        let response: URLResponse
        do {
            if let json {
                request.httpBody = try JSONEncoder().encode(AnyEncodable(json))
                request.setValue("application/json", forHTTPHeaderField: "content-type")
                (data, response) = try await URLSession.shared.data(for: request)
            } else if let body {
                request.setValue("application/octet-stream", forHTTPHeaderField: "content-type")
                (data, response) = try await URLSession.shared.upload(for: request, from: body)
            } else {
                (data, response) = try await URLSession.shared.data(for: request)
            }
        } catch is URLError {
            throw SyncError.offline("Could not reach the server. Check your connection and the server address.")
        }
        guard let http = response as? HTTPURLResponse else { throw SyncError.offline("Unexpected reply from the server.") }
        guard (200..<300).contains(http.statusCode) else {
            let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data)
            let message = parsed?.error ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw SyncError.server(http.statusCode, message + (parsed?.detail.map { " (\($0))" } ?? ""))
        }
        return (data, http)
    }

    private func decoded<R: Decodable>(_ path: String, method: String = "GET", json: (any Encodable)? = nil) async throws -> R {
        let (data, _) = try await send(path, method: method, json: json)
        return try JSONDecoder().decode(R.self, from: data)
    }

    // MARK: Accounts

    func prelogin(email: String) async throws -> PreloginResponse {
        try await decoded("/auth/prelogin", method: "POST", json: ["email": email])
    }

    func register(invite: String, email: String, salt: String, loginKey: String) async throws -> SessionResponse {
        try await decoded("/auth/register", method: "POST", json: ["invite": invite, "email": email, "salt": salt, "loginKey": loginKey])
    }

    func reset(invite: String, email: String, salt: String, loginKey: String) async throws -> SessionResponse {
        try await decoded("/auth/reset", method: "POST", json: ["invite": invite, "email": email, "salt": salt, "loginKey": loginKey])
    }

    func login(email: String, loginKey: String) async throws -> SessionResponse {
        try await decoded("/auth/login", method: "POST", json: ["email": email, "loginKey": loginKey])
    }

    func logout() async {
        _ = try? await send("/auth/logout", method: "POST")
    }

    func changePassword(currentLoginKey: String, newLoginKey: String, newSalt: String) async throws {
        _ = try await send("/auth/password", method: "POST",
                           json: ["currentLoginKey": currentLoginKey, "newLoginKey": newLoginKey, "newSalt": newSalt])
    }

    // MARK: Sync

    func changes(since cursor: Int) async throws -> ChangesResponse {
        try await decoded("/api/changes?since=\(cursor)&limit=500")
    }

    func stats() async throws -> StatsResponse {
        try await decoded("/api/stats")
    }

    func getBlob(_ id: String, version: Int? = nil) async throws -> (data: Data, version: Int) {
        let suffix = version.map { "?version=\($0)" } ?? ""
        let (data, http) = try await send("/api/blob/\(id)\(suffix)")
        return (data, Int(http.value(forHTTPHeaderField: "x-version") ?? "") ?? version ?? 0)
    }

    func putBlob(_ id: String, kind: String, body: Data, baseVersion: Int?) async throws -> PutResponse {
        var headers = ["x-kind": kind]
        if let baseVersion { headers["x-base-version"] = String(baseVersion) }
        let (data, _) = try await send("/api/blob/\(id)", method: "PUT", body: body, headers: headers)
        return try JSONDecoder().decode(PutResponse.self, from: data)
    }

    func deleteBlob(_ id: String) async throws {
        _ = try await send("/api/blob/\(id)", method: "DELETE")
    }
}

private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
