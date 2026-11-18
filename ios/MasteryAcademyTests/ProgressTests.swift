import Foundation
import Testing
@testable import MasteryAcademy

@MainActor
struct ProgressStoreTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID().uuidString).json")
    }

    private func date(_ text: String) -> Date { JSONCoding.parseDate(text)! }

    @Test func completionPersistsAcrossLaunches() {
        let file = temporaryFile()
        let store = ProgressStore(fileURL: file)
        store.setLessonDone("swiftui", "m01-1", true)
        store.toggleBookmark("swiftui", "m01-2")
        store.setQuizResult("swift-dsa", "two-sum", score: 1, total: 1)

        let reopened = ProgressStore(fileURL: file)
        #expect(reopened.isLessonDone("swiftui", "m01-1"))
        #expect(reopened.isBookmarked("swiftui", "m01-2"))
        #expect(reopened.quizResult("swift-dsa", "two-sum")?.score == 1)
        #expect(reopened.count("swiftui", .lesson) == 1)
        #expect(reopened.dirtyRecords.count == 3)
    }

    @Test func streakCountsConsecutiveDaysEndingTodayOrYesterday() {
        var clock = date("2026-11-10T08:00:00Z")
        let store = ProgressStore(fileURL: temporaryFile(), now: { clock })
        #expect(store.streak == 0)
        for day in 0..<3 {
            clock = date("2026-11-10T08:00:00Z").addingTimeInterval(Double(day) * 86_400)
            store.setLessonDone("c", "l\(day)", true)
        }
        #expect(store.streak == 3)
        clock = clock.addingTimeInterval(86_400)      // next day, nothing done yet: streak still stands
        #expect(store.streak == 3)
        clock = clock.addingTimeInterval(86_400)      // a full day missed
        #expect(store.streak == 0)
    }

    @Test func mergeKeepsTheNewerRecord() {
        var clock = date("2026-11-17T10:00:00Z")
        let store = ProgressStore(fileURL: temporaryFile(), now: { clock })
        store.setLessonDone("c", "kept-local", true)
        store.setLessonDone("c", "replaced", true)
        clock = date("2026-11-17T12:00:00Z")

        let remote = [
            ProgressRecord(courseId: "c", kind: .lesson, itemId: "kept-local", done: false, updatedAt: date("2026-11-17T09:00:00Z")),
            ProgressRecord(courseId: "c", kind: .lesson, itemId: "replaced", done: false, updatedAt: date("2026-11-17T11:00:00Z")),
            ProgressRecord(courseId: "c", kind: .card, itemId: "new", done: true, updatedAt: date("2026-11-17T11:00:00Z")),
        ]
        let applied = store.merge(remote: remote, cursor: 7, userId: "u1")
        #expect(applied == 2)
        #expect(store.isLessonDone("c", "kept-local"))
        #expect(!store.isLessonDone("c", "replaced"))
        #expect(store.isCardKnown("c", "new"))
        #expect(store.cursor(for: "u1") == 7)
        #expect(store.cursor(for: "someone-else") == 0)
        #expect(store.dirtyRecords.map(\.itemId) == ["kept-local"])
    }

    @Test func markSyncedSkipsRecordsThatChangedDuringTheRequest() {
        var clock = date("2026-11-17T10:00:00Z")
        let store = ProgressStore(fileURL: temporaryFile(), now: { clock })
        store.setLessonDone("c", "a", true)
        store.setLessonDone("c", "b", true)
        let sent = store.dirtyRecords
        clock = date("2026-11-17T10:05:00Z")
        store.setLessonDone("c", "b", false)          // edited while the push was in flight
        store.markSynced(sent)
        #expect(store.dirtyRecords.map(\.itemId) == ["b"])
    }

    @Test func signingInAsANewUserMarksEverythingForUpload() {
        let store = ProgressStore(fileURL: temporaryFile())
        store.setLessonDone("c", "a", true)
        store.markSynced(store.dirtyRecords)
        #expect(store.dirtyRecords.isEmpty)
        store.prepareForAccount(userId: "u2")
        #expect(store.dirtyRecords.count == 1)
    }

    @Test func wireDatesRoundTrip() throws {
        let record = ProgressRecord(courseId: "c", kind: .quiz, itemId: "q", done: true, score: 3, total: 4, updatedAt: date("2026-11-17T10:00:00Z"))
        let data = try JSONCoding.encoder().encode(record)
        #expect(try JSONCoding.decoder().decode(ProgressRecord.self, from: data) == record)
        #expect(JSONCoding.parseDate("2026-11-17T10:00:00.123456Z") != nil)
    }
}

struct SearchEngineTests {
    private func course() throws -> Course {
        let json = #"""
        {"schemaVersion":1,"id":"c","title":"Course","subtitle":"","version":"v","resources":[],
         "modules":[{"id":"m","title":"Concurrency","summary":"","tag":"","lessons":[
           {"id":"l1","title":"Actors and isolation","minutes":5,"level":0,"quiz":[],"blocks":[{"type":"text","text":"An actor protects its state."}]},
           {"id":"l2","title":"Structured tasks","minutes":5,"level":0,"quiz":[],"blocks":[{"type":"code","code":"actor Cache {}","language":"swift"}]}]}],
         "questions":[{"id":"q1","topic":"Concurrency","level":"Senior","q":"What is actor reentrancy?","a":"Suspension points let other work run.","points":[]}]}
        """#
        return try JSONCoding.decoder().decode(Course.self, from: Data(json.utf8))
    }

    @Test func titleMatchesRankAboveBodyMatches() throws {
        let hits = SearchEngine(courses: [try course()]).search("actor")
        #expect(hits.map(\.itemId) == ["l1", "q1", "l2"])
    }

    @Test func everyWordMustMatchAndCaseIsIgnored() throws {
        let engine = SearchEngine(courses: [try course()])
        #expect(engine.search("ACTOR reentrancy").map(\.itemId) == ["q1"])
        #expect(engine.search("actor kubernetes").isEmpty)
        #expect(engine.search("   ").isEmpty)
    }
}
