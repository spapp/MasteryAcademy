import SwiftUI

/// A lesson task: the learner writes an answer and the tutor marks it against the task's rubric.
struct TaskBlockView: View {
    let task: TaskBlock
    let tint: Color

    @Environment(AccountModel.self) private var account
    @Environment(AttemptStore.self) private var attempts
    @Environment(\.lessonRef) private var lessonRef
    @State private var answer = ""
    @State private var result: MarkResult?
    @State private var failure: String?
    @State private var working = false
    @State private var showRubric = false
    @State private var showAnswer = false

    private var courseId: String { lessonRef?.courseId ?? "" }

    private var canMark: Bool {
        !working && lessonRef != nil && answer.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your task", systemImage: "pencil.and.list.clipboard").font(.subheadline.weight(.semibold)).foregroundStyle(tint)
            MarkupText(task.prompt)
            if !task.material.isEmpty {
                CodeBlockView(block: CodeBlock(code: task.material, language: "text", caption: "Start from this"))
                    .environment(\.explainAction, nil)
            }
            AnswerEditor(text: $answer)
            markButton
            if let failure { AIErrorText(message: failure) }
            resultView
            DisclosureGroup("What a good answer does", isExpanded: $showRubric) {
                ListBlockView(ordered: false, items: task.rubric).padding(.top, 6)
            }
            .font(.subheadline)
            if !task.answer.isEmpty {
                DisclosureGroup("Model answer", isExpanded: $showAnswer) {
                    Text(task.answer).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
                .font(.subheadline)
            }
        }
        .padding(14)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear(perform: restore)
    }

    private var markButton: some View {
        Button {
            Task { await mark() }
        } label: {
            HStack {
                Label("Mark my answer", systemImage: "sparkles")
                if working { ProgressView().padding(.leading, 4) }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(!canMark)
    }

    @ViewBuilder
    private var resultView: some View {
        if let result {
            MarkResultView(result: result, tint: tint)
        } else if let last = attempts.latest(courseId: courseId, itemId: task.id) {
            MarkResultView(score: last.score, verdict: last.verdict, strengths: [], gaps: [], feedback: last.feedback, tint: tint)
        }
    }

    /// Brings back the last answer so the learner can improve it.
    private func restore() {
        if answer.isEmpty, let last = attempts.latest(courseId: courseId, itemId: task.id) { answer = last.answer }
    }

    private func mark() async {
        guard let lessonRef else { return }
        working = true
        failure = nil
        defer { working = false }
        do {
            let marked = try await account.client.mark(courseId: lessonRef.courseId, kind: .task, lessonId: lessonRef.lessonId, itemId: task.id, question: nil, answer: answer)
            result = marked
            attempts.record(courseId: lessonRef.courseId, kind: .task, itemId: task.id, answer: answer, result: marked)
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// One open question with a typed answer and its mark. Used by quiz-me and the mock interview.
struct MarkedQuestionView: View {
    let courseId: String
    let kind: MarkKind
    let lessonId: String?
    let itemId: String?
    let question: String
    let tint: Color
    var onMarked: (MarkResult) -> Void = { _ in }

    @Environment(AccountModel.self) private var account
    @Environment(AttemptStore.self) private var attempts
    @State private var answer = ""
    @State private var result: MarkResult?
    @State private var failure: String?
    @State private var working = false

    private var canMark: Bool {
        !working && result == nil && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MarkupText(question).font(.headline)
            AnswerEditor(text: $answer, minHeight: 100)
                .disabled(result != nil)
            if result == nil {
                Button {
                    Task { await mark() }
                } label: {
                    HStack {
                        Label("Mark my answer", systemImage: "sparkles")
                        if working { ProgressView().padding(.leading, 4) }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .disabled(!canMark)
            }
            if let failure { AIErrorText(message: failure) }
            if let result { MarkResultView(result: result, tint: tint) }
        }
    }

    private func mark() async {
        working = true
        failure = nil
        defer { working = false }
        do {
            let marked = try await account.client.mark(courseId: courseId, kind: kind, lessonId: lessonId, itemId: itemId, question: question, answer: answer)
            result = marked
            attempts.record(courseId: courseId, kind: kind, itemId: itemId ?? question, answer: answer, result: marked)
            onMarked(marked)
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// Fresh open questions on one lesson, written and marked by the tutor.
struct QuizMeSheet: View {
    let courseId: String
    let lessonId: String
    let lessonTitle: String
    let tint: Color

    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var questions: [String] = []
    @State private var failure: String?
    @State private var working = false
    @State private var round = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(lessonTitle).font(.headline)
                    if working { ProgressView("Writing questions…") }
                    if let failure { AIErrorText(message: failure) }
                    ForEach(Array(questions.enumerated()), id: \.offset) { _, question in
                        MarkedQuestionView(courseId: courseId, kind: .quiz, lessonId: lessonId, itemId: nil, question: question, tint: tint)
                    }
                    if !questions.isEmpty || failure != nil {
                        Button("New questions") { round += 1 }.disabled(working)
                    }
                }
                .padding()
                .id(round)
            }
            .navigationTitle("Quiz me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task(id: round) { await load() }
        }
    }

    private func load() async {
        working = true
        questions = []
        failure = nil
        defer { working = false }
        do {
            questions = try await account.client.quizQuestions(courseId: courseId, lessonId: lessonId, count: 3).questions
        } catch is CancellationError {
            return
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// Five questions from the course's question bank, one at a time, each answer marked against the model answer.
struct MockInterviewView: View {
    let courseId: String
    @Environment(ContentRepository.self) private var repository

    var body: some View {
        CourseLoader(courseId: courseId) { course in
            MockInterviewContent(course: course, tint: repository.summary(courseId)?.tintColor ?? .accentColor)
        }
        .navigationTitle("Mock interview")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MockInterviewContent: View {
    let course: Course
    let tint: Color

    @State private var questions: [QAItem] = []
    @State private var index = 0
    @State private var scores: [Int] = []
    @State private var marked = false
    @State private var showModel = false
    static let length = 5

    private var finished: Bool { !questions.isEmpty && index >= questions.count }

    private var nextTitle: String { marked ? "Next question" : "Skip this question" }

    private var average: Int {
        scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if questions.isEmpty {
                    ContentUnavailableView("No interview questions", systemImage: "text.bubble", description: Text("This course has no question bank."))
                } else if finished {
                    summary
                } else {
                    current(questions[index])
                }
            }
            .padding()
        }
        .onAppear { if questions.isEmpty { start() } }
    }

    private func current(_ item: QAItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Question \(index + 1) of \(questions.count)").font(.caption).foregroundStyle(.secondary)
            if !item.topic.isEmpty {
                Text(item.topic.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(tint)
            }
            MarkedQuestionView(courseId: course.id, kind: .interview, lessonId: nil, itemId: item.id, question: item.q, tint: tint) { result in
                scores.append(result.score)
                marked = true
            }
            .id(item.id)
            if marked {
                DisclosureGroup("Model answer", isExpanded: $showModel) {
                    MarkupText(item.a).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
                .font(.subheadline)
            }
            Button(nextTitle) { next() }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interview finished").font(.title2.weight(.bold))
            Text("\(scores.count) of \(questions.count) answered. Average score \(average) out of 100.")
                .foregroundStyle(.secondary)
            Button("Start another interview") { start() }
                .buttonStyle(.borderedProminent)
                .tint(tint)
        }
    }

    private func start() {
        questions = Array(course.questions.shuffled().prefix(MockInterviewContent.length))
        index = 0
        scores = []
        marked = false
        showModel = false
    }

    private func next() {
        index += 1
        marked = false
        showModel = false
    }
}
