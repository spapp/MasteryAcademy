import Foundation

// Content schema v1. Produced by tools/content/build_content.mjs and served unchanged by the API.
// Field-by-field description: kb/00-core/04-content-schema.md.

struct Catalog: Codable {
    let schemaVersion: Int
    let courses: [CourseSummary]
}

struct CourseSummary: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let tint: String
    let group: String
    let status: String
    let artifactURL: String?
    let note: String?
    let version: String
    let lessonCount: Int
    let questionCount: Int
    let quizCount: Int
    let minutes: Int
    let web: String?

    var isAvailable: Bool { status == "available" }
}

struct Course: Decodable, Identifiable {
    let schemaVersion: Int
    let id: String
    let title: String
    let subtitle: String
    let version: String
    let modules: [CourseModule]
    let questions: [QAItem]
    let resources: [LinkItem]

    var allLessons: [Lesson] { modules.flatMap { $0.lessons } }

    func lesson(id: String) -> Lesson? {
        for module in modules {
            if let found = module.lessons.first(where: { $0.id == id }) { return found }
        }
        return nil
    }

    func module(containing lessonID: String) -> CourseModule? {
        modules.first { module in module.lessons.contains { $0.id == lessonID } }
    }

    /// The lesson after `lessonID` in course order, crossing module boundaries.
    func lesson(after lessonID: String) -> Lesson? {
        let all = allLessons
        guard let index = all.firstIndex(where: { $0.id == lessonID }), index + 1 < all.count else { return nil }
        return all[index + 1]
    }
}

struct CourseModule: Decodable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let tag: String
    let lessons: [Lesson]
}

struct Lesson: Decodable, Identifiable {
    let id: String
    let title: String
    let minutes: Int
    let level: Int
    let blocks: [Block]
    let quiz: [QuizQuestion]
}

struct QuizQuestion: Decodable, Equatable {
    let q: String
    let options: [String]
    let answer: Int
    let why: String
}

struct QAItem: Decodable, Identifiable {
    let id: String
    let topic: String
    let level: String
    let q: String
    let a: String
    let points: [QAPoint]
}

struct QAPoint: Decodable {
    let title: String
    let items: [String]
}

struct LinkItem: Decodable, Equatable {
    let title: String
    let kind: String
    let url: String
}

struct CodeBlock: Equatable {
    let code: String
    let language: String
    let caption: String?
}

struct Callout: Equatable {
    let style: String
    let title: String
    let text: String
}

/// Phase 2: something the learner does, with the criteria the tutor marks against.
struct TaskBlock: Equatable {
    let id: String
    let prompt: String
    let material: String
    let rubric: [String]
    let answer: String
}

struct TableBlock: Equatable {
    let headers: [String]
    let rows: [[String]]
}

/// One piece of a lesson. Unknown types decode to `.unknown` so newer content never crashes an older app.
enum Block: Decodable {
    case heading(String)
    case text(String)
    case code(CodeBlock)
    case list(ordered: Bool, items: [String])
    case callout(Callout)
    case table(TableBlock)
    case links([LinkItem])
    case diagram(Diagram)
    case task(TaskBlock)
    case unknown(String)

    private enum Keys: String, CodingKey {
        case type, text, code, language, caption, ordered, items, style, title, headers, rows, links, diagram
        case id, prompt, material, rubric, answer
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "heading":
            self = .heading(try c.decode(String.self, forKey: .text))
        case "text":
            self = .text(try c.decode(String.self, forKey: .text))
        case "code":
            self = .code(CodeBlock(code: try c.decode(String.self, forKey: .code),
                                   language: try c.decodeIfPresent(String.self, forKey: .language) ?? "swift",
                                   caption: try c.decodeIfPresent(String.self, forKey: .caption)))
        case "list":
            self = .list(ordered: try c.decodeIfPresent(Bool.self, forKey: .ordered) ?? false,
                         items: try c.decode([String].self, forKey: .items))
        case "callout":
            self = .callout(Callout(style: try c.decodeIfPresent(String.self, forKey: .style) ?? "note",
                                    title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
                                    text: try c.decodeIfPresent(String.self, forKey: .text) ?? ""))
        case "table":
            self = .table(TableBlock(headers: try c.decode([String].self, forKey: .headers),
                                     rows: try c.decode([[String]].self, forKey: .rows)))
        case "links":
            self = .links(try c.decode([LinkItem].self, forKey: .links))
        case "diagram":
            self = .diagram(try c.decode(Diagram.self, forKey: .diagram))
        case "task":
            self = .task(TaskBlock(id: try c.decode(String.self, forKey: .id),
                                   prompt: try c.decodeIfPresent(String.self, forKey: .prompt) ?? "",
                                   material: try c.decodeIfPresent(String.self, forKey: .material) ?? "",
                                   rubric: try c.decodeIfPresent([String].self, forKey: .rubric) ?? [],
                                   answer: try c.decodeIfPresent(String.self, forKey: .answer) ?? ""))
        default:
            self = .unknown(type)
        }
    }

    /// Plain text used by search.
    var searchText: String {
        switch self {
        case .heading(let s), .text(let s): return s
        case .code(let c): return c.code
        case .list(_, let items): return items.joined(separator: " ")
        case .callout(let c): return c.title + " " + c.text
        case .table(let t): return t.rows.map { $0.joined(separator: " ") }.joined(separator: " ")
        case .task(let t): return t.prompt + " " + t.rubric.joined(separator: " ")
        case .links, .diagram, .unknown: return ""
        }
    }
}

struct Diagram: Decodable {
    let title: String
    let width: Double
    let height: Double
    let caption: String
    let lanes: [Lane]
    let nodes: [Node]
    let edges: [Edge]
    let steps: [Step]

    struct Lane: Decodable {
        let y: Double
        let h: Double
        let label: String
    }

    struct Node: Decodable, Identifiable {
        let id: String
        let label: String
        let sub: String
        let x: Double
        let y: Double
        let w: Double
        let h: Double
        let kind: String
        let hot: Bool
        let detail: String

        var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    }

    /// Either an explicit polyline (`points`) or a connection between two node ids (`from`/`to`).
    struct Edge: Decodable {
        let from: String?
        let to: String?
        let points: [[Double]]?
        let label: String
        let dashed: Bool
        let hot: Bool
    }

    struct Step: Decodable {
        let from: String
        let to: String
        let text: String
    }
}
