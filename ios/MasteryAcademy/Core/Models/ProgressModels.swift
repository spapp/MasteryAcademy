import Foundation

/// One syncable fact about the learner. Wire shape of `ProgressRecord` in spec/api.json, plus a local `dirty` flag.
struct ProgressRecord: Codable, Equatable {
    var courseId: String
    var kind: ProgressKind
    var itemId: String
    var done: Bool
    var score: Int?
    var total: Int?
    var updatedAt: Date
    /// Changed on this device and not yet accepted by the server. Never sent on the wire.
    var dirty: Bool = false

    var key: String { ProgressRecord.key(courseId, kind, itemId) }

    static func key(_ courseId: String, _ kind: ProgressKind, _ itemId: String) -> String {
        "\(courseId)|\(kind.rawValue)|\(itemId)"
    }

    private enum CodingKeys: String, CodingKey {
        case courseId, kind, itemId, done, score, total, updatedAt, dirty
    }

    init(courseId: String, kind: ProgressKind, itemId: String, done: Bool, score: Int? = nil, total: Int? = nil, updatedAt: Date, dirty: Bool = false) {
        self.courseId = courseId
        self.kind = kind
        self.itemId = itemId
        self.done = done
        self.score = score
        self.total = total
        self.updatedAt = updatedAt
        self.dirty = dirty
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        courseId = try c.decode(String.self, forKey: .courseId)
        kind = try c.decode(ProgressKind.self, forKey: .kind)
        itemId = try c.decode(String.self, forKey: .itemId)
        done = try c.decode(Bool.self, forKey: .done)
        score = try c.decodeIfPresent(Int.self, forKey: .score)
        total = try c.decodeIfPresent(Int.self, forKey: .total)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        dirty = try c.decodeIfPresent(Bool.self, forKey: .dirty) ?? false
    }
}

/// What is written to disk.
struct ProgressSnapshot: Codable {
    var records: [ProgressRecord] = []
    /// Server cursor of the last successful pull, per signed-in user id.
    var cursors: [String: Int] = [:]
    /// Local calendar days (yyyy-MM-dd) on which something was completed.
    var activeDays: [String] = []
    var lastCourseId: String?
    var lastLessonId: String?
}

/// Where the user can go. Screens are addressed by id so navigation state stays small.
enum Route: Hashable {
    case course(String)
    case lesson(courseId: String, lessonId: String)
    case questions(courseId: String)
    case flashcards(courseId: String)
    case quiz(courseId: String)
    case web(courseId: String)
    case notes(courseId: String)
    case downloads
    case interview(courseId: String)
}
