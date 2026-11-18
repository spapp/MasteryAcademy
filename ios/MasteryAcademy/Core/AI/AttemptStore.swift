import Foundation
import Observation

/// One marked answer: a lesson task, a quiz-me question or a mock interview question.
struct Attempt: Codable, Identifiable, Equatable {
    var id: UUID
    var courseId: String
    var kind: MarkKind
    var itemId: String
    var answer: String
    var score: Int
    var verdict: String
    var feedback: String
    var date: Date
}

/// Marked attempts, newest last. Kept on this device; the newest 300 are kept.
@MainActor
@Observable
final class AttemptStore {
    private(set) var attempts: [Attempt] = []
    private let fileURL: URL
    private let now: () -> Date
    static let limit = 300

    init(fileURL: URL? = nil, now: @escaping () -> Date = { Date() }) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? directory.appendingPathComponent("attempts.json")
        self.now = now
        if let data = try? Data(contentsOf: self.fileURL), let saved = try? JSONCoding.decoder().decode([Attempt].self, from: data) {
            attempts = saved
        }
    }

    func record(courseId: String, kind: MarkKind, itemId: String, answer: String, result: MarkResult) {
        attempts.append(Attempt(id: UUID(), courseId: courseId, kind: kind, itemId: itemId, answer: answer,
                                score: result.score, verdict: result.verdict, feedback: result.feedback, date: now()))
        if attempts.count > AttemptStore.limit { attempts.removeFirst(attempts.count - AttemptStore.limit) }
        save()
    }

    func latest(courseId: String, itemId: String) -> Attempt? {
        attempts.last { $0.courseId == courseId && $0.itemId == itemId }
    }

    func count(courseId: String, itemId: String) -> Int {
        attempts.reduce(0) { $0 + (($1.courseId == courseId && $1.itemId == itemId) ? 1 : 0) }
    }

    /// Best score per item of one kind in a course, for "tasks done" style numbers.
    func best(courseId: String, kind: MarkKind) -> [String: Int] {
        var result: [String: Int] = [:]
        for attempt in attempts where attempt.courseId == courseId && attempt.kind == kind {
            result[attempt.itemId] = max(result[attempt.itemId] ?? 0, attempt.score)
        }
        return result
    }

    func resetAll() {
        attempts = []
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONCoding.encoder().encode(attempts).write(to: fileURL, options: .atomic)
        } catch {
            // Stays in memory; the next attempt tries again.
        }
    }
}
