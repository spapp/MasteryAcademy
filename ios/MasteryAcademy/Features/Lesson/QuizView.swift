import SwiftUI

/// A run of multiple-choice questions, one at a time, with the explanation after each answer.
struct QuizView: View {
    let questions: [QuizQuestion]
    let tint: Color
    var previous: ProgressRecord?
    let onFinish: (_ score: Int, _ total: Int) -> Void

    @State private var index = 0
    @State private var chosen: Int?
    @State private var score = 0
    @State private var finished = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if finished {
                result
            } else if questions.indices.contains(index) {
                question(questions[index])
            }
        }
        .card()
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(score) of \(questions.count) correct").font(.headline).monospacedDigit()
            Text(score == questions.count ? "All correct." : "Read the explanations for the ones you missed, then try again.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Try again") {
                index = 0; chosen = nil; score = 0; finished = false
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func question(_ item: QuizQuestion) -> some View {
        HStack {
            Text("Question \(index + 1) of \(questions.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            if let previous, let best = previous.score, let total = previous.total, index == 0, chosen == nil {
                Text("Last time: \(best)/\(total)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        MarkupText(item.q).font(.body.weight(.medium))
        ForEach(Array(item.options.enumerated()), id: \.offset) { optionIndex, option in
            Button {
                guard chosen == nil else { return }
                chosen = optionIndex
                if optionIndex == item.answer { score += 1 }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    MarkupText(option).multilineTextAlignment(.leading)
                    Spacer()
                    if let chosen {
                        if optionIndex == item.answer {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Correct answer")
                        } else if optionIndex == chosen {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red).accessibilityLabel("Your answer, incorrect")
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(optionBackground(optionIndex, answer: item.answer), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(chosen != nil)
        }
        if chosen != nil {
            if !item.why.isEmpty {
                MarkupText(item.why).font(.subheadline).foregroundStyle(.secondary)
            }
            Button(index + 1 < questions.count ? "Next question" : "See result") {
                if index + 1 < questions.count {
                    index += 1
                    chosen = nil
                } else {
                    finished = true
                    onFinish(score, questions.count)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
        }
    }

    private func optionBackground(_ optionIndex: Int, answer: Int) -> Color {
        guard let chosen else { return Color(uiColor: .tertiarySystemFill) }
        if optionIndex == answer { return Color.green.opacity(0.18) }
        if optionIndex == chosen { return Color.red.opacity(0.18) }
        return Color(uiColor: .tertiarySystemFill)
    }
}
