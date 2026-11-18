import Foundation

// Wire shapes of the Phase 2 routes in spec/api.json. The app sends ids; the server loads the lesson itself.

struct AiUsage: Decodable, Equatable {
    let enabled: Bool
    let requestsToday: Int
    let dailyLimit: Int
    let monthCostCents: Int
    let monthlyCapCents: Int

    var summary: String {
        if !enabled { return "The server is reachable, but it has no Claude API key, so AI is off." }
        let cost = String(format: "$%.2f", Double(monthCostCents) / 100)
        let cap = String(format: "$%.2f", Double(monthlyCapCents) / 100)
        return "AI is on. \(requestsToday) of \(dailyLimit) requests used today, \(cost) of \(cap) this month."
    }
}

struct SectionRef: Decodable, Equatable, Identifiable {
    let blockIndex: Int
    let title: String
    var id: Int { blockIndex }
}

struct AskResult: Decodable, Equatable {
    let answer: String
    let covered: Bool
    let sections: [SectionRef]
    let usage: AiUsage
}

struct QuizResult: Decodable {
    let questions: [String]
    let usage: AiUsage
}

struct MarkResult: Decodable, Equatable {
    let score: Int
    let verdict: String
    let strengths: [String]
    let gaps: [String]
    let feedback: String
    let usage: AiUsage
}

enum MarkKind: String, Codable {
    case quiz, task, interview
}

private struct AskBody: Encodable {
    let courseId: String
    let lessonId: String
    let mode: String
    let question: String?
    let blockIndex: Int?
    let depth: String?
}

private struct QuizBody: Encodable {
    let courseId: String
    let lessonId: String
    let count: Int
}

private struct MarkBody: Encodable {
    let courseId: String
    let kind: MarkKind
    let lessonId: String?
    let itemId: String?
    let question: String?
    let answer: String
}

extension APIClient {
    /// A question about a lesson, optionally about one of its blocks.
    func askTutor(courseId: String, lessonId: String, question: String, blockIndex: Int?) async throws -> AskResult {
        let body = AskBody(courseId: courseId, lessonId: lessonId, mode: "tutor", question: question, blockIndex: blockIndex, depth: nil)
        return try await send(.askLesson, body: body)
    }

    func explainCode(courseId: String, lessonId: String, blockIndex: Int, senior: Bool) async throws -> AskResult {
        let body = AskBody(courseId: courseId, lessonId: lessonId, mode: "explain", question: nil, blockIndex: blockIndex, depth: senior ? "senior" : "beginner")
        return try await send(.askLesson, body: body)
    }

    func quizQuestions(courseId: String, lessonId: String, count: Int) async throws -> QuizResult {
        try await send(.makeQuiz, body: QuizBody(courseId: courseId, lessonId: lessonId, count: count))
    }

    func mark(courseId: String, kind: MarkKind, lessonId: String?, itemId: String?, question: String?, answer: String) async throws -> MarkResult {
        let body = MarkBody(courseId: courseId, kind: kind, lessonId: lessonId, itemId: itemId, question: question, answer: answer)
        return try await send(.markAnswer, body: body)
    }

    func aiUsage() async throws -> AiUsage {
        try await send(.getAiUsage)
    }
}
