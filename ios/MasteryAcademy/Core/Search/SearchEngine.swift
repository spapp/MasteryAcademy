import Foundation

struct SearchHit: Identifiable, Equatable {
    enum Kind: String { case lesson, question }

    let id: String
    let kind: Kind
    let courseId: String
    let courseTitle: String
    /// Lesson id for lessons, question id for questions.
    let itemId: String
    let title: String
    let detail: String
}

/// In-memory search over installed courses. Every word of the query must appear; matches in titles rank first.
struct SearchEngine: Sendable {
    struct Entry: Sendable {
        let hit: SearchHit
        let title: String
        let body: String
    }

    private(set) var entries: [Entry] = []

    init() {}

    init(courses: [Course]) {
        for course in courses { add(course) }
    }

    mutating func add(_ course: Course) {
        for module in course.modules {
            for lesson in module.lessons {
                let body = lesson.blocks.map { $0.searchText }.joined(separator: " ")
                let hit = SearchHit(id: "\(course.id)|l|\(lesson.id)", kind: .lesson, courseId: course.id, courseTitle: course.title,
                                    itemId: lesson.id, title: InlineMarkup.plain(lesson.title), detail: module.title)
                entries.append(Entry(hit: hit, title: Self.fold(lesson.title), body: Self.fold(body)))
            }
        }
        for question in course.questions {
            let hit = SearchHit(id: "\(course.id)|q|\(question.id)", kind: .question, courseId: course.id, courseTitle: course.title,
                                itemId: question.id, title: InlineMarkup.plain(question.q), detail: question.topic)
            entries.append(Entry(hit: hit, title: Self.fold(question.q), body: Self.fold(question.a + " " + question.topic)))
        }
    }

    func search(_ query: String, limit: Int = 60) -> [SearchHit] {
        let words = Self.fold(query).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        var scored: [(score: Int, order: Int, hit: SearchHit)] = []
        for (order, entry) in entries.enumerated() {
            var score = 0
            var matchedAll = true
            for word in words {
                if entry.title.contains(word) {
                    score += 10
                } else if entry.body.contains(word) {
                    score += 1
                } else {
                    matchedAll = false
                    break
                }
            }
            if !matchedAll { continue }
            if entry.title.hasPrefix(words[0]) { score += 5 }
            if entry.hit.kind == .lesson { score += 2 }
            scored.append((score, order, entry.hit))
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
        return scored.prefix(limit).map { $0.hit }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }
}
