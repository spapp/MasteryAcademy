import Foundation
import SwiftUI
import Testing
@testable import MasteryAcademy

@MainActor
struct ReadingTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("reading-\(UUID().uuidString).json")
    }

    @Test func highlightsNotesAndPositionsPersist() {
        let file = temporaryFile()
        let store = AnnotationStore(fileURL: file)
        store.toggleHighlight("kmp", "l1", 2, excerpt: "Shared code")
        store.setNote("kmp", "l1", 4, excerpt: "expect and actual", note: "  ask about this  ")
        store.setPosition("kmp", "l1", 7)
        store.flush()

        let reopened = AnnotationStore(fileURL: file)
        #expect(reopened.annotation("kmp", "l1", 2)?.highlighted == true)
        #expect(reopened.annotation("kmp", "l1", 4)?.note == "ask about this")
        #expect(reopened.position("kmp", "l1") == 7)
        #expect(reopened.count(courseId: "kmp") == 2)
        #expect(reopened.count(courseId: "sql") == 0)
    }

    @Test func removingTheHighlightAndTheNoteRemovesTheAnnotation() {
        let store = AnnotationStore(fileURL: temporaryFile())
        store.toggleHighlight("c", "l", 0, excerpt: "x")
        store.setNote("c", "l", 0, excerpt: "x", note: "keep")
        store.toggleHighlight("c", "l", 0, excerpt: "x")
        #expect(store.annotation("c", "l", 0)?.note == "keep")
        #expect(store.annotation("c", "l", 0)?.highlighted == false)
        store.setNote("c", "l", 0, excerpt: "x", note: "")
        #expect(store.annotation("c", "l", 0) == nil)
    }

    @Test func notesExportAsMarkdownInCourseOrder() async throws {
        let course = try await ContentRepository().course("kmp")
        let lessons = course.allLessons
        let store = AnnotationStore(fileURL: temporaryFile())
        store.setNote("kmp", lessons[1].id, 0, excerpt: "second lesson", note: "note B")
        store.toggleHighlight("kmp", lessons[0].id, 0, excerpt: "first lesson")
        let text = store.markdown(for: course)
        let first = try #require(text.range(of: "> first lesson"))
        let second = try #require(text.range(of: "> second lesson"))
        #expect(first.lowerBound < second.lowerBound)
        #expect(text.contains("note B"))
        #expect(text.hasPrefix("# Kotlin Multiplatform"))
    }

    @Test func textSizeStepStaysInsideTheSystemSizes() {
        #expect(ReadingStyle.dynamicTypeSize(base: .large, step: 0) == .large)
        #expect(ReadingStyle.dynamicTypeSize(base: .large, step: 1) == .xLarge)
        #expect(ReadingStyle.dynamicTypeSize(base: .xSmall, step: -2) == .xSmall)
        #expect(ReadingStyle.dynamicTypeSize(base: .accessibility5, step: 4) == .accessibility5)
    }

    @Test func minutesLeftFollowTheReadingPosition() {
        #expect(ReadingStyle.minutesLeft(total: 10, fraction: 0) == 10)
        #expect(ReadingStyle.minutesLeft(total: 10, fraction: 0.55) == 5)
        #expect(ReadingStyle.minutesLeft(total: 10, fraction: 1) == 0)
        #expect(ReadingStyle.minutesLeft(total: 10, fraction: 3) == 0)
    }

    @Test func lessonExportEscapesHTMLAndMakesAPDF() async throws {
        #expect(LessonExport.inline("a < b and `x>y` **bold**") == "a &lt; b and <code>x&gt;y</code> <b>bold</b>")
        let course = try await ContentRepository().course("kmp")
        let lesson = try #require(course.allLessons.first)
        let html = LessonExport.html(courseTitle: course.title, lesson: lesson)
        #expect(html.contains("<h1>"))
        let data = LessonExport.pdfData(courseTitle: course.title, lesson: lesson)
        #expect(data.starts(with: Array("%PDF".utf8)))
    }

    @Test func bundledCourseReportsItsSourceAndSize() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("content-\(UUID().uuidString)", isDirectory: true)
        let repository = ContentRepository(cacheDirectory: directory)
        let info = repository.installed("swiftui")
        #expect(info.source == .bundled)
        #expect(info.bytes > 1000)
        #expect(repository.installed("no-such-course").source == .missing)
        #expect(repository.downloads.isEmpty)
        repository.deleteAllDownloads()
        #expect(repository.installed("swiftui").source == .bundled)
        #expect(repository.summary("swiftui") != nil)
    }
}
