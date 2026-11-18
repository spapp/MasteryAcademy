import SwiftUI

private struct TutorExchange: Identifiable {
    let id = UUID()
    let question: String
    var result: AskResult?
    var failure: String?
}

/// Ask a question about the open lesson, or about one paragraph of it. Answers come from the lesson only.
struct TutorSheet: View {
    let courseId: String
    let lessonId: String
    let lessonTitle: String
    /// Set when the learner asked about one block.
    let blockIndex: Int?
    let excerpt: String?
    let tint: Color
    /// Called with a block index when the learner taps a section the answer used.
    let onJump: (Int) -> Void

    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var exchanges: [TutorExchange] = []
    @State private var working = false

    private var canAsk: Bool {
        !working && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    intro
                    ForEach(exchanges) { exchange in
                        exchangeView(exchange)
                    }
                    if working { ProgressView("Reading the lesson…") }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("Ask about this lesson")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lessonTitle).font(.headline)
            if let excerpt, !excerpt.isEmpty {
                Text(excerpt).font(.footnote).foregroundStyle(.secondary).lineLimit(4)
                    .padding(8)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Text("The tutor answers from this lesson only and says so when the lesson does not cover your question.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Your question", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
            Button {
                Task { await ask() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .tint(tint)
            .disabled(!canAsk)
            .accessibilityLabel("Ask")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private func exchangeView(_ exchange: TutorExchange) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(exchange.question).font(.subheadline.weight(.semibold))
            if let failure = exchange.failure {
                AIErrorText(message: failure)
            }
            if let result = exchange.result {
                answerView(result)
            }
        }
        .card()
    }

    @ViewBuilder
    private func answerView(_ result: AskResult) -> some View {
        MarkupText(result.answer).font(.subheadline)
        if !result.covered {
            Label("Not covered in this lesson", systemImage: "questionmark.circle").font(.caption).foregroundStyle(.orange)
        }
        if !result.sections.isEmpty {
            Text("From this lesson").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(result.sections) { section in
                Button {
                    onJump(section.blockIndex)
                    dismiss()
                } label: {
                    Label(section.title.isEmpty ? "Go to this part" : section.title, systemImage: "arrow.turn.down.right")
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                }
                .tint(tint)
            }
        }
    }

    private func ask() async {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        question = ""
        working = true
        defer { working = false }
        var exchange = TutorExchange(question: text)
        do {
            exchange.result = try await account.client.askTutor(courseId: courseId, lessonId: lessonId, question: text, blockIndex: blockIndex)
        } catch {
            exchange.failure = error.localizedDescription
        }
        exchanges.append(exchange)
    }
}

/// Line-by-line explanation of one code block, at beginner or senior depth.
struct ExplainSheet: View {
    let courseId: String
    let lessonId: String
    let blockIndex: Int
    let code: CodeBlock
    let tint: Color

    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var senior = false
    @State private var result: AskResult?
    @State private var failure: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Depth", selection: $senior) {
                        Text("Beginner").tag(false)
                        Text("Senior").tag(true)
                    }
                    .pickerStyle(.segmented)
                    CodeBlockView(block: code).environment(\.explainAction, nil)
                    if working { ProgressView("Explaining…") }
                    if let failure { AIErrorText(message: failure) }
                    if let result {
                        MarkupText(result.answer).font(.subheadline).card()
                    }
                }
                .padding()
            }
            .navigationTitle("Explain this code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task(id: senior) { await load() }
        }
    }

    private func load() async {
        working = true
        result = nil
        failure = nil
        defer { working = false }
        do {
            result = try await account.client.explainCode(courseId: courseId, lessonId: lessonId, blockIndex: blockIndex, senior: senior)
        } catch is CancellationError {
            return
        } catch {
            failure = error.localizedDescription
        }
    }
}
