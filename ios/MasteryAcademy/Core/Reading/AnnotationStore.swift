import Foundation
import Observation

/// A highlight, a note, or both, on one block of a lesson. Blocks are addressed by their index, which is
/// stable for one version of a course; the excerpt is kept so a note still reads well if the content moves.
struct Annotation: Codable, Identifiable, Equatable {
    var courseId: String
    var lessonId: String
    var blockIndex: Int
    var excerpt: String
    var note: String
    var highlighted: Bool
    var updatedAt: Date

    var id: String { Annotation.key(courseId, lessonId, blockIndex) }

    static func key(_ courseId: String, _ lessonId: String, _ blockIndex: Int) -> String {
        "\(courseId)|\(lessonId)|\(blockIndex)"
    }
}

struct ReadingSnapshot: Codable {
    var annotations: [Annotation] = []
    /// Index of the block at the top of the screen when the lesson was last left, per "course|lesson".
    var positions: [String: Int] = [:]
}

/// Highlights, notes and reading positions. Kept on this device only (not synced yet).
@MainActor
@Observable
final class AnnotationStore {
    private(set) var annotations: [String: Annotation] = [:]
    private var positions: [String: Int] = [:]
    private var positionsChanged = false

    private let fileURL: URL
    private let now: () -> Date

    init(fileURL: URL? = nil, now: @escaping () -> Date = { Date() }) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? directory.appendingPathComponent("reading.json")
        self.now = now
        load()
    }

    // MARK: Highlights and notes

    func annotation(_ courseId: String, _ lessonId: String, _ blockIndex: Int) -> Annotation? {
        annotations[Annotation.key(courseId, lessonId, blockIndex)]
    }

    /// Newest first.
    func annotations(courseId: String) -> [Annotation] {
        annotations.values.filter { $0.courseId == courseId }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func count(courseId: String) -> Int {
        annotations.values.reduce(0) { $0 + ($1.courseId == courseId ? 1 : 0) }
    }

    func toggleHighlight(_ courseId: String, _ lessonId: String, _ blockIndex: Int, excerpt: String) {
        var item = annotation(courseId, lessonId, blockIndex)
            ?? Annotation(courseId: courseId, lessonId: lessonId, blockIndex: blockIndex, excerpt: excerpt, note: "", highlighted: false, updatedAt: now())
        item.highlighted.toggle()
        store(item)
    }

    /// An empty note on a block that is not highlighted removes the annotation.
    func setNote(_ courseId: String, _ lessonId: String, _ blockIndex: Int, excerpt: String, note: String) {
        var item = annotation(courseId, lessonId, blockIndex)
            ?? Annotation(courseId: courseId, lessonId: lessonId, blockIndex: blockIndex, excerpt: excerpt, note: "", highlighted: false, updatedAt: now())
        item.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        store(item)
    }

    func remove(_ annotation: Annotation) {
        annotations[annotation.id] = nil
        save()
    }

    private func store(_ item: Annotation) {
        var item = item
        if !item.highlighted && item.note.isEmpty {
            annotations[item.id] = nil
        } else {
            item.updatedAt = now()
            annotations[item.id] = item
        }
        save()
    }

    // MARK: Reading position

    func position(_ courseId: String, _ lessonId: String) -> Int? {
        positions["\(courseId)|\(lessonId)"]
    }

    /// Kept in memory while the reader scrolls; `flush()` writes it.
    func setPosition(_ courseId: String, _ lessonId: String, _ blockIndex: Int) {
        let key = "\(courseId)|\(lessonId)"
        if positions[key] != blockIndex {
            positions[key] = blockIndex
            positionsChanged = true
        }
    }

    func flush() {
        if positionsChanged { save() }
    }

    func resetAll() {
        annotations = [:]
        positions = [:]
        save()
    }

    // MARK: Export

    /// The course's highlights and notes as Markdown, in course order.
    func markdown(for course: Course) -> String {
        var lines: [String] = ["# \(course.title): highlights and notes", ""]
        let mine = annotations.values.filter { $0.courseId == course.id }
        for lesson in course.allLessons {
            let items = mine.filter { $0.lessonId == lesson.id }.sorted { $0.blockIndex < $1.blockIndex }
            if items.isEmpty { continue }
            lines.append("## \(InlineMarkup.plain(lesson.title))")
            lines.append("")
            for item in items {
                lines.append("> " + item.excerpt.replacingOccurrences(of: "\n", with: " "))
                if !item.note.isEmpty {
                    lines.append("")
                    lines.append(item.note)
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONCoding.decoder().decode(ReadingSnapshot.self, from: data) else { return }
        annotations = Dictionary(snapshot.annotations.map { ($0.id, $0) }, uniquingKeysWith: { first, second in first.updatedAt >= second.updatedAt ? first : second })
        positions = snapshot.positions
    }

    private func save() {
        positionsChanged = false
        let snapshot = ReadingSnapshot(annotations: annotations.values.sorted { $0.id < $1.id }, positions: positions)
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONCoding.encoder().encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            // Stays in memory; the next change tries again.
        }
    }
}

extension Block {
    /// Whether the block can carry a highlight or a note.
    var isAnnotatable: Bool {
        switch self {
        case .heading, .text, .code, .list, .callout, .table: return true
        case .links, .diagram, .task, .unknown: return false
        }
    }

    /// Short plain text that stands for the block in the notes list and in exports.
    var excerpt: String {
        let plain = InlineMarkup.plain(searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.count > 240 ? String(plain.prefix(240)) + "…" : plain
    }
}
