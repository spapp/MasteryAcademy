import Foundation
import Security

struct Tokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresIn: Int
}

/// Where tokens live. The app uses the Keychain; tests use the in-memory store.
protocol TokenStoring: Sendable {
    func read() -> Tokens?
    func write(_ tokens: Tokens?)
}

struct KeychainTokenStore: TokenStoring {
    private let service = "com.dibya.masteryacademy.tokens"
    private let account = "session"

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func read() -> Tokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: data)
    }

    func write(_ tokens: Tokens?) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let tokens, let data = try? JSONEncoder().encode(tokens) else { return }
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }
}

final class MemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: Tokens?

    init(_ tokens: Tokens? = nil) { self.tokens = tokens }

    func read() -> Tokens? {
        lock.lock(); defer { lock.unlock() }
        return tokens
    }

    func write(_ tokens: Tokens?) {
        lock.lock(); defer { lock.unlock() }
        self.tokens = tokens
    }
}
