import Foundation
import Observation

/// Everything the learner has done, kept on device and merged with the server when signed in.
/// Conflict rule (same as the server): the record with the newest `updatedAt` wins.
@MainActor
@Observable
final class ProgressStore {
    private(set) var records: [String: ProgressRecord] = [:]
    private(set) var activeDays: Set<String> = []
    private(set) var lastCourseId: String?
    private(set) var lastLessonId: String?
    private var cursors: [String: Int] = [:]

    private let fileURL: URL
    private let now: () -> Date

    init(fileURL: URL? = nil, now: @escaping () -> Date = { Date() }) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? directory.appendingPathComponent("progress.json")
        self.now = now
        load()
    }

    // MARK: Reading

    func record(_ courseId: String, _ kind: ProgressKind, _ itemId: String) -> ProgressRecord? {
        records[ProgressRecord.key(courseId, kind, itemId)]
    }

    func isDone(_ courseId: String, _ kind: ProgressKind, _ itemId: String) -> Bool {
        record(courseId, kind, itemId)?.done ?? false
    }

    func isLessonDone(_ courseId: String, _ lessonId: String) -> Bool { isDone(courseId, .lesson, lessonId) }
    func isBookmarked(_ courseId: String, _ lessonId: String) -> Bool { isDone(courseId, .bookmark, lessonId) }
    func isCardKnown(_ courseId: String, _ questionId: String) -> Bool { isDone(courseId, .card, questionId) }
    func quizResult(_ courseId: String, _ lessonId: String) -> ProgressRecord? { record(courseId, .quiz, lessonId) }

    func count(_ courseId: String, _ kind: ProgressKind) -> Int {
        records.values.reduce(0) { $0 + (($1.courseId == courseId && $1.kind == kind && $1.done) ? 1 : 0) }
    }

    func totalDone(_ kind: ProgressKind) -> Int {
        records.values.reduce(0) { $0 + (($1.kind == kind && $1.done) ? 1 : 0) }
    }

    func bookmarks(_ courseId: String) -> [String] {
        records.values.filter { $0.courseId == courseId && $0.kind == .bookmark && $0.done }
            .sorted { $0.updatedAt > $1.updatedAt }.map { $0.itemId }
    }

    /// Consecutive days with activity, ending today or yesterday.
    var streak: Int {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: now())
        if !activeDays.contains(Self.dayKey(day)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while activeDays.contains(Self.dayKey(day)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    // MARK: Writing

    func setLessonDone(_ courseId: String, _ lessonId: String, _ done: Bool) {
        set(courseId, .lesson, lessonId, done: done)
        if done { markActiveToday() }
    }

    func toggleBookmark(_ courseId: String, _ lessonId: String) {
        set(courseId, .bookmark, lessonId, done: !isBookmarked(courseId, lessonId))
    }

    func setCardKnown(_ courseId: String, _ questionId: String, _ known: Bool) {
        set(courseId, .card, questionId, done: known)
        markActiveToday()
    }

    func setQuizResult(_ courseId: String, _ itemId: String, score: Int, total: Int) {
        set(courseId, .quiz, itemId, done: true, score: score, total: total)
        markActiveToday()
    }

    func setLastOpened(courseId: String, lessonId: String) {
        lastCourseId = courseId
        lastLessonId = lessonId
        save()
    }

    private func set(_ courseId: String, _ kind: ProgressKind, _ itemId: String, done: Bool, score: Int? = nil, total: Int? = nil) {
        // Whole seconds, so the value survives the round trip to the server unchanged.
        let stamp = Date(timeIntervalSince1970: now().timeIntervalSince1970.rounded(.down))
        let record = ProgressRecord(courseId: courseId, kind: kind, itemId: itemId, done: done, score: score, total: total, updatedAt: stamp, dirty: true)
        records[record.key] = record
        save()
    }

    private func markActiveToday() {
        if activeDays.insert(Self.dayKey(now())).inserted { save() }
    }

    func resetAll() {
        records = [:]
        activeDays = []
        cursors = [:]
        lastCourseId = nil
        lastLessonId = nil
        save()
    }

    // MARK: Sync support

    var dirtyRecords: [ProgressRecord] { records.values.filter { $0.dirty } }

    func cursor(for userId: String) -> Int { cursors[userId] ?? 0 }

    /// Clears the dirty flag for records the server accepted, unless they changed again while the request ran.
    func markSynced(_ sent: [ProgressRecord]) {
        for item in sent {
            if var current = records[item.key], current.updatedAt == item.updatedAt, current.done == item.done {
                current.dirty = false
                records[item.key] = current
            }
        }
        save()
    }

    /// Applies records pulled from the server. A local record wins only when it is strictly newer.
    @discardableResult
    func merge(remote: [ProgressRecord], cursor: Int, userId: String) -> Int {
        var applied = 0
        for incoming in remote {
            if let local = records[incoming.key], local.updatedAt > incoming.updatedAt { continue }
            var record = incoming
            record.dirty = false
            if records[incoming.key] != record {
                records[incoming.key] = record
                applied += 1
            }
        }
        cursors[userId] = cursor
        save()
        return applied
    }

    /// After signing in as a different user everything local must be pushed again and pulled from zero.
    func prepareForAccount(userId: String) {
        if cursors[userId] == nil {
            for key in records.keys { records[key]?.dirty = true }
            save()
        }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONCoding.decoder().decode(ProgressSnapshot.self, from: data) else { return }
        records = Dictionary(snapshot.records.map { ($0.key, $0) }, uniquingKeysWith: { first, second in first.updatedAt >= second.updatedAt ? first : second })
        cursors = snapshot.cursors
        activeDays = Set(snapshot.activeDays)
        lastCourseId = snapshot.lastCourseId
        lastLessonId = snapshot.lastLessonId
    }

    private func save() {
        let snapshot = ProgressSnapshot(records: Array(records.values), cursors: cursors, activeDays: activeDays.sorted(),
                                        lastCourseId: lastCourseId, lastLessonId: lastLessonId)
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONCoding.encoder().encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            // Progress stays in memory; the next change tries again.
        }
    }

    static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
