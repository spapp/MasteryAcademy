import Foundation

struct DataEnvelope<T: Decodable>: Decodable {
    let data: T
}

struct PageInfo: Decodable {
    let nextCursor: Int?
    let cursor: Int
}

struct PagedEnvelope<T: Decodable>: Decodable {
    let data: [T]
    let page: PageInfo
}

struct ErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String
        let message: String
        let requestId: String?
        let fields: [String: String]?
    }
    let error: Body
}

enum APIError: LocalizedError, Equatable {
    case server(status: Int, code: String, message: String)
    case notSignedIn
    case unreachable(String)
    case badServerURL

    var errorDescription: String? {
        switch self {
        case .server(_, _, let message): return message
        case .notSignedIn: return "Sign in to sync your progress."
        case .unreachable(let reason): return "Can't reach the server. \(reason)"
        case .badServerURL: return "The server address is not a valid URL."
        }
    }
}

/// Talks to the Mastery Academy API. Adds the bearer token, refreshes it once on 401 (one refresh at a time),
/// and turns the error envelope into `APIError`.
actor APIClient {
    static let serverURLKey = "serverURL"
    static let defaultServerURL = "http://localhost:8000"
    /// The personal app key that unlocks the AI routes on the server. Sent as X-App-Key when set.
    static let appKeyKey = "appKey"

    private let session: URLSession
    private let tokens: TokenStoring
    private let baseURLProvider: @Sendable () -> String
    private var refreshTask: Task<Tokens, Error>?

    init(session: URLSession = .shared, tokens: TokenStoring = KeychainTokenStore(),
         baseURL: @escaping @Sendable () -> String = { UserDefaults.standard.string(forKey: APIClient.serverURLKey) ?? APIClient.defaultServerURL }) {
        self.session = session
        self.tokens = tokens
        self.baseURLProvider = baseURL
    }

    nonisolated var hasSession: Bool { tokens.read() != nil }

    func setTokens(_ value: Tokens?) { tokens.write(value) }

    // MARK: Requests

    func send<T: Decodable>(_ operation: APIOperation, query: [String: String] = [:]) async throws -> T {
        let data = try await perform(operation, query: query, body: nil)
        return try JSONCoding.decoder().decode(DataEnvelope<T>.self, from: data).data
    }

    func send<T: Decodable, Body: Encodable>(_ operation: APIOperation, body: Body) async throws -> T {
        let data = try await perform(operation, query: [:], body: try JSONCoding.encoder().encode(body))
        return try JSONCoding.decoder().decode(DataEnvelope<T>.self, from: data).data
    }

    func sendPaged<T: Decodable>(_ operation: APIOperation, query: [String: String]) async throws -> PagedEnvelope<T> {
        let data = try await perform(operation, query: query, body: nil)
        return try JSONCoding.decoder().decode(PagedEnvelope<T>.self, from: data)
    }

    /// For operations that answer 204.
    func sendNoContent(_ operation: APIOperation) async throws {
        _ = try await perform(operation, query: [:], body: nil)
    }

    /// The untouched response body (used to cache course content exactly as served).
    func sendRaw(_ operation: APIOperation) async throws -> Data {
        try await perform(operation, query: [:], body: nil)
    }

    private func perform(_ operation: APIOperation, query: [String: String], body: Data?) async throws -> Data {
        if operation.requiresAuth && tokens.read() == nil { throw APIError.notSignedIn }
        let (data, response) = try await transport(operation, query: query, body: body, token: tokens.read()?.accessToken)
        if response.statusCode == 401 && operation.requiresAuth {
            let fresh = try await refreshedTokens()
            let (retryData, retryResponse) = try await transport(operation, query: query, body: body, token: fresh.accessToken)
            return try check(retryData, retryResponse)
        }
        return try check(data, response)
    }

    private func transport(_ operation: APIOperation, query: [String: String], body: Data?, token: String?) async throws -> (Data, HTTPURLResponse) {
        guard var components = URLComponents(string: baseURLProvider().trimmingCharacters(in: .whitespaces) + APIOperation.basePath + operation.path) else {
            throw APIError.badServerURL
        }
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url, url.scheme == "http" || url.scheme == "https" else { throw APIError.badServerURL }
        var request = URLRequest(url: url)
        request.httpMethod = operation.method
        // A model call takes longer than a database read.
        request.timeoutInterval = operation.path.hasPrefix("/ai/") ? 90 : 20
        if let appKey = UserDefaults.standard.string(forKey: APIClient.appKeyKey), !appKey.isEmpty {
            request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if operation.requiresAuth, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.unreachable("Unexpected response.") }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.unreachable(error.localizedDescription)
        }
    }

    private func check(_ data: Data, _ response: HTTPURLResponse) throws -> Data {
        if (200..<300).contains(response.statusCode) { return data }
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            throw APIError.server(status: response.statusCode, code: envelope.error.code, message: envelope.error.message)
        }
        throw APIError.server(status: response.statusCode, code: "INTERNAL", message: "The server answered \(response.statusCode).")
    }

    /// Refresh tokens are single-use, so concurrent 401s must share one refresh call.
    private func refreshedTokens() async throws -> Tokens {
        if let running = refreshTask { return try await running.value }
        guard let current = tokens.read() else { throw APIError.notSignedIn }
        let task = Task { () throws -> Tokens in
            let body = try JSONEncoder().encode(["refreshToken": current.refreshToken])
            let (data, response) = try await self.transport(.refreshSession, query: [:], body: body, token: nil)
            let checked = try self.check(data, response)
            return try JSONDecoder().decode(DataEnvelope<Tokens>.self, from: checked).data
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            tokens.write(fresh)
            return fresh
        } catch let error as APIError {
            // The server refused the refresh token: the session is over. A network failure keeps the tokens.
            if case .server(let status, _, _) = error, status == 401 { tokens.write(nil) }
            throw error
        }
    }
}
