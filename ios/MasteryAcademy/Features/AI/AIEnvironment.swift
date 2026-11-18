import SwiftUI

/// Which lesson the blocks on screen belong to, so a block can ask the server about itself.
struct LessonRef: Equatable {
    let courseId: String
    let lessonId: String
}

private struct LessonRefKey: EnvironmentKey {
    static let defaultValue: LessonRef? = nil
}

private struct BlockIndexKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

/// Set by the lesson screen; a code block calls it with its own index to open the explanation.
struct ExplainAction {
    let run: (Int) -> Void
}

private struct ExplainActionKey: EnvironmentKey {
    static let defaultValue: ExplainAction? = nil
}

extension EnvironmentValues {
    var lessonRef: LessonRef? {
        get { self[LessonRefKey.self] }
        set { self[LessonRefKey.self] = newValue }
    }

    var blockIndex: Int? {
        get { self[BlockIndexKey.self] }
        set { self[BlockIndexKey.self] = newValue }
    }

    var explainAction: ExplainAction? {
        get { self[ExplainActionKey.self] }
        set { self[ExplainActionKey.self] = newValue }
    }
}

/// The result of marking: score, verdict, what was good, what is missing, what to change.
struct MarkResultView: View {
    let score: Int
    let verdict: String
    let strengths: [String]
    let gaps: [String]
    let feedback: String
    let tint: Color

    private var color: Color {
        if score >= 75 { return .green }
        if score >= 50 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    ProgressRing(fraction: Double(score) / 100, tint: color, lineWidth: 5)
                    Text("\(score)").font(.headline).monospacedDigit()
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verdict).font(.headline)
                    Text("Marked by AI against the course's criteria").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !feedback.isEmpty {
                MarkupText(feedback).font(.subheadline)
            }
            pointList(title: "What worked", symbol: "checkmark.circle", color: .green, items: strengths)
            pointList(title: "What is missing", symbol: "exclamationmark.circle", color: .orange, items: gaps)
        }
        .card()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func pointList(title: String, symbol: String, color: Color, items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: symbol).foregroundStyle(color).font(.caption)
                        MarkupText(item).font(.subheadline)
                    }
                }
            }
        }
    }
}

extension MarkResultView {
    init(result: MarkResult, tint: Color) {
        self.init(score: result.score, verdict: result.verdict, strengths: result.strengths, gaps: result.gaps, feedback: result.feedback, tint: tint)
    }
}

/// Shown when an AI call fails: the server's own message, which says what to do.
struct AIErrorText: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.red)
    }
}

/// A plain multi-line answer box with a border, used by tasks, quiz-me and the mock interview.
struct AnswerEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 120

    var body: some View {
        TextEditor(text: $text)
            .frame(minHeight: minHeight)
            .padding(6)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityLabel("Your answer")
    }
}
