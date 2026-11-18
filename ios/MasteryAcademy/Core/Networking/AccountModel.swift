import Foundation
import Observation

struct UserAccount: Codable, Equatable {
    let id: String
    let email: String
    let displayName: String
}

private struct AuthResult: Decodable {
    let user: UserAccount
    let tokens: Tokens
}

private struct RegisterBody: Encodable {
    let email: String
    let password: String
    let displayName: String
}

private struct SessionBody: Encodable {
    let email: String
    let password: String
    let deviceName: String
}

/// `ProgressRecord` as it travels: no local flags.
private struct WireRecord: Codable {
    let courseId: String
    let kind: ProgressKind
    let itemId: String
    let done: Bool
    let score: Int?
    let total: Int?
    let updatedAt: Date

    init(_ r: ProgressRecord) {
        courseId = r.courseId; kind = r.kind; itemId = r.itemId; done = r.done; score = r.score; total = r.total; updatedAt = r.updatedAt
    }

    var record: ProgressRecord {
        ProgressRecord(courseId: courseId, kind: kind, itemId: itemId, done: done, score: score, total: total, updatedAt: updatedAt)
    }
}

private struct PushBody: Encodable {
    let records: [WireRecord]
}

private struct PushResult: Decodable {
    let applied: Int
    let stale: Int
    let cursor: Int
}

/// Sign-in state and progress sync. The app is fully usable signed out; an account only adds sync.
@MainActor
@Observable
final class AccountModel {
    enum SyncState: Equatable {
        case idle
        case syncing
        case synced(Date)
        case failed(String)
    }

    private(set) var user: UserAccount?
    private(set) var syncState: SyncState = .idle
    private(set) var isWorking = false
    var errorMessage: String?

    let client: APIClient
    private let progress: ProgressStore
    private let defaults: UserDefaults
    private static let userKey = "signedInUser"

    init(client: APIClient, progress: ProgressStore, defaults: UserDefaults = .standard) {
        self.client = client
        self.progress = progress
        self.defaults = defaults
        if client.hasSession, let data = defaults.data(forKey: Self.userKey) {
            user = try? JSONDecoder().decode(UserAccount.self, from: data)
        }
    }

    var isSignedIn: Bool { user != nil }

    func register(email: String, password: String, displayName: String) async {
        await authenticate { try await self.client.send(.registerUser, body: RegisterBody(email: email, password: password, displayName: displayName)) }
    }

    func signIn(email: String, password: String, deviceName: String) async {
        await authenticate { try await self.client.send(.createSession, body: SessionBody(email: email, password: password, deviceName: deviceName)) }
    }

    private func authenticate(_ call: @escaping () async throws -> AuthResult) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let result = try await call()
            await client.setTokens(result.tokens)
            setUser(result.user)
            progress.prepareForAccount(userId: result.user.id)
            await sync()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        try? await client.sendNoContent(.deleteSession)
        await client.setTokens(nil)
        setUser(nil)
        syncState = .idle
    }

    func deleteAccount() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.sendNoContent(.deleteMe)
            await client.setTokens(nil)
            setUser(nil)
            syncState = .idle
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Push local changes, then pull everything after the stored cursor. Safe to call often.
    func sync() async {
        guard let user, syncState != .syncing else { return }
        syncState = .syncing
        do {
            let dirty = progress.dirtyRecords
            for start in stride(from: 0, to: dirty.count, by: 400) {
                let batch = Array(dirty[start..<min(start + 400, dirty.count)])
                let _: PushResult = try await client.send(.pushProgress, body: PushBody(records: batch.map { WireRecord($0) }))
                progress.markSynced(batch)
            }
            var cursor = progress.cursor(for: user.id)
            while true {
                let page: PagedEnvelope<WireRecord> = try await client.sendPaged(.listProgress, query: ["since": String(cursor), "limit": "500"])
                progress.merge(remote: page.data.map { $0.record }, cursor: page.page.cursor, userId: user.id)
                guard let next = page.page.nextCursor else { break }
                cursor = next
            }
            syncState = .synced(Date())
        } catch let error as APIError {
            if case .server(let status, _, _) = error, status == 401 {
                setUser(nil)
                syncState = .failed("Your session ended. Sign in again.")
            } else {
                syncState = .failed(error.localizedDescription)
            }
        } catch {
            syncState = .failed(error.localizedDescription)
        }
    }

    private func setUser(_ value: UserAccount?) {
        user = value
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: Self.userKey)
        } else {
            defaults.removeObject(forKey: Self.userKey)
        }
    }
}
