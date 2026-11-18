import Foundation
import Testing
@testable import MasteryAcademy

@MainActor
struct ContentTests {
    @Test func catalogListsAvailableAndPlannedCourses() {
        let repository = ContentRepository()
        #expect(repository.loadError == nil)
        #expect(repository.catalog.count >= 20)
        #expect(Set(repository.availableCourses.map(\.id)) == ["swiftui", "swift-dsa", "system-design", "python-node", "sql", "devops", "android", "git", "ide", "jenkins", "redis-kafka", "pwa", "fde", "power-bi", "blockchain", "ai-engineer", "fullstack-ai", "prompt-engineering", "flutter", "claude-mastery", "ai-tools", "mobile-design", "kmp", "career"])
        #expect(Set(repository.catalog.map(\.id)).count == repository.catalog.count)
    }

    @Test(arguments: ["swiftui", "swift-dsa", "system-design", "python-node", "sql", "devops", "android", "git", "ide", "jenkins", "redis-kafka", "pwa", "fde", "power-bi", "blockchain", "ai-engineer", "fullstack-ai", "prompt-engineering", "flutter", "claude-mastery", "ai-tools", "mobile-design", "kmp", "career"])
    func bundledCourseDecodesAndMatchesTheCatalog(id: String) async throws {
        let repository = ContentRepository()
        let course = try await repository.course(id)
        let summary = try #require(repository.summary(id))
        #expect(course.version == summary.version)
        #expect(course.allLessons.count == summary.lessonCount)
        #expect(course.questions.count == summary.questionCount)
        #expect(Set(course.allLessons.map(\.id)).count == course.allLessons.count)
        for lesson in course.allLessons {
            #expect(!lesson.blocks.isEmpty, "empty lesson \(lesson.id)")
            for question in lesson.quiz {
                #expect(question.options.indices.contains(question.answer), "bad answer index in \(lesson.id)")
            }
            for block in lesson.blocks {
                if case .unknown(let type) = block { Issue.record("unknown block type \(type) in \(lesson.id)") }
            }
        }
    }

    @Test func systemDesignCourseHasNoBigBasketSection() async throws {
        let course = try await ContentRepository().course("system-design")
        #expect(!course.modules.contains { $0.title.localizedCaseInsensitiveContains("bigbasket") })
    }

    @Test func nextLessonCrossesModules() async throws {
        let course = try await ContentRepository().course("swiftui")
        let first = try #require(course.modules.first)
        let last = try #require(first.lessons.last)
        #expect(course.lesson(after: last.id)?.id == course.modules[1].lessons.first?.id)
        let lastLesson = try #require(course.allLessons.last)
        #expect(course.lesson(after: lastLesson.id) == nil)
    }

    @Test func unknownBlockTypesAreKeptNotFatal() throws {
        let json = #"{"id":"l","title":"t","minutes":1,"level":0,"quiz":[],"blocks":[{"type":"hologram","x":1},{"type":"text","text":"ok"}]}"#
        let lesson = try JSONCoding.decoder().decode(Lesson.self, from: Data(json.utf8))
        #expect(lesson.blocks.count == 2)
        if case .unknown(let type) = lesson.blocks[0] { #expect(type == "hologram") } else { Issue.record("expected .unknown") }
    }
}

struct InlineMarkupTests {
    @Test func parsesCodeBoldAndItalic() {
        #expect(InlineMarkup.parse("Use `let` by **default**, *not* var") ==
                [.plain("Use "), .code("let"), .plain(" by "), .bold("default"), .plain(", "), .italic("not"), .plain(" var")])
    }

    @Test func leavesArithmeticAndUnclosedMarkersAlone() {
        #expect(InlineMarkup.parse("a * b * c") == [.plain("a * b * c")])
        #expect(InlineMarkup.parse("O(n * m) and `open") == [.plain("O(n * m) and `open")])
        #expect(InlineMarkup.parse("2 ** 3") == [.plain("2 ** 3")])
    }

    @Test func asterisksInsideCodeAreLiteral() {
        #expect(InlineMarkup.parse("`a ** b` and `*p`") == [.code("a ** b"), .plain(" and "), .code("*p")])
        #expect(InlineMarkup.plain("**Bold** `code`") == "Bold code")
    }
}

struct HighlighterTests {
    @Test func classifiesTokens() {
        let tokens = SwiftHighlighter.tokenize("let x: Int = 42 // answer\n@MainActor func f() { print(\"hi\") }")
        func kind(_ text: String) -> SwiftHighlighter.Kind? { tokens.first { $0.text == text }?.kind }
        #expect(kind("let") == .keyword)
        #expect(kind("Int") == .type)
        #expect(kind("42") == .number)
        #expect(kind("// answer") == .comment)
        #expect(kind("@MainActor") == .attribute)
        #expect(kind("\"hi\"") == .string)
        #expect(tokens.map(\.text).joined() == "let x: Int = 42 // answer\n@MainActor func f() { print(\"hi\") }")
    }

    @Test func unterminatedStringAndCommentDoNotLoseText() {
        for code in ["let s = \"abc", "/* open", "x = \"a\\", "#", "@"] {
            #expect(SwiftHighlighter.tokenize(code).map(\.text).joined() == code)
        }
    }
}

struct DiagramGeometryTests {
    @Test func edgeLeavesTheRectangleOnTheSideFacingTheTarget() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        func close(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 0.0001 && abs(a.y - b.y) < 0.0001 }
        #expect(close(DiagramGeometry.exitPoint(of: rect, towards: CGPoint(x: 300, y: 20)), CGPoint(x: 100, y: 20)))
        #expect(close(DiagramGeometry.exitPoint(of: rect, towards: CGPoint(x: 50, y: -200)), CGPoint(x: 50, y: 0)))
        #expect(close(DiagramGeometry.exitPoint(of: rect, towards: CGPoint(x: 50, y: 20)), CGPoint(x: 50, y: 20)))
    }

    @Test func labelSitsOnTheLongestSegment() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 100)]
        #expect(DiagramGeometry.labelPoint(points) == CGPoint(x: 10, y: 50))
        #expect(DiagramGeometry.labelPoint([CGPoint.zero]) == nil)
    }
}
