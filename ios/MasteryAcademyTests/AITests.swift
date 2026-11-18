import Foundation
import Testing
@testable import MasteryAcademy

@MainActor
struct AITests {
    @Test func promptEngineeringLessonsCarryATaskWithARubric() async throws {
        let course = try await ContentRepository().course("prompt-engineering")
        var tasks: [TaskBlock] = []
        for lesson in course.allLessons {
            for block in lesson.blocks {
                if case .task(let task) = block { tasks.append(task) }
            }
        }
        #expect(tasks.count == 17)
        #expect(Set(tasks.map(\.id)).count == tasks.count)
        for task in tasks {
            #expect(!task.prompt.isEmpty, "task without a prompt: \(task.id)")
            #expect(task.rubric.count >= 2, "task without a rubric: \(task.id)")
            #expect(!task.answer.isEmpty, "task without a model answer: \(task.id)")
        }
    }

    @Test func aiResultsDecodeFromTheWireShape() throws {
        let json = """
        {"data": {"score": 72, "verdict": "Good", "strengths": ["States the labels"], "gaps": [], "feedback": "Add a hard case.",
                  "usage": {"enabled": true, "requestsToday": 3, "dailyLimit": 100, "monthCostCents": 12, "monthlyCapCents": 500}}}
        """
        let result = try JSONCoding.decoder().decode(DataEnvelope<MarkResult>.self, from: Data(json.utf8)).data
        #expect(result.score == 72)
        #expect(result.usage.summary == "AI is on. 3 of 100 requests used today, $0.12 of $5.00 this month.")
        let ask = """
        {"data": {"answer": "Use `three` examples.", "covered": false, "sections": [{"blockIndex": 4, "title": "Strong prompt"}],
                  "usage": {"enabled": false, "requestsToday": 0, "dailyLimit": 100, "monthCostCents": 0, "monthlyCapCents": 500}}}
        """
        let answer = try JSONCoding.decoder().decode(DataEnvelope<AskResult>.self, from: Data(ask.utf8)).data
        #expect(answer.sections.first?.blockIndex == 4)
        #expect(answer.covered == false)
        #expect(answer.usage.summary.contains("no Claude API key"))
    }

    @Test func attemptsPersistAndKeepTheBestScore() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("attempts-\(UUID().uuidString).json")
        let usage = AiUsage(enabled: true, requestsToday: 1, dailyLimit: 100, monthCostCents: 0, monthlyCapCents: 500)
        let store = AttemptStore(fileURL: file)
        store.record(courseId: "pe", kind: .task, itemId: "t1", answer: "first", result: MarkResult(score: 40, verdict: "Not yet", strengths: [], gaps: ["x"], feedback: "f", usage: usage))
        store.record(courseId: "pe", kind: .task, itemId: "t1", answer: "second", result: MarkResult(score: 80, verdict: "Strong", strengths: [], gaps: [], feedback: "g", usage: usage))
        store.record(courseId: "pe", kind: .interview, itemId: "q1", answer: "a", result: MarkResult(score: 55, verdict: "Partly right", strengths: [], gaps: [], feedback: "h", usage: usage))

        let reopened = AttemptStore(fileURL: file)
        #expect(reopened.attempts.count == 3)
        #expect(reopened.latest(courseId: "pe", itemId: "t1")?.answer == "second")
        #expect(reopened.count(courseId: "pe", itemId: "t1") == 2)
        #expect(reopened.best(courseId: "pe", kind: .task) == ["t1": 80])
    }
}
