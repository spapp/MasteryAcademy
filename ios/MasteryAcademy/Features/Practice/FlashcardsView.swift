import SwiftUI

struct FlashcardsView: View {
    let courseId: String
    @Environment(ContentRepository.self) private var repository

    var body: some View {
        CourseLoader(courseId: courseId) { course in
            FlashcardsContent(course: course, tint: repository.summary(courseId)?.tintColor ?? .accentColor)
        }
        .navigationTitle("Flashcards")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Question on the front, answer on the back. Cards you do not know yet come first.
private struct FlashcardsContent: View {
    let course: Course
    let tint: Color

    @Environment(ProgressStore.self) private var progress
    @State private var topic = ""
    @State private var deck: [QAItem] = []
    @State private var position = 0
    @State private var showAnswer = false

    private var topics: [String] {
        var seen: [String] = []
        for question in course.questions where !seen.contains(question.topic) { seen.append(question.topic) }
        return seen
    }

    var body: some View {
        VStack(spacing: 14) {
            Picker("Topic", selection: $topic) {
                Text("All topics").tag("")
                ForEach(topics, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)

            if deck.indices.contains(position) {
                let card = deck[position]
                Text("Card \(position + 1) of \(deck.count)" + (progress.isCardKnown(course.id, card.id) ? " · known" : ""))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(card.topic.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(tint)
                        MarkupText(card.q).font(.title3.weight(.semibold))
                        if showAnswer {
                            Divider()
                            AnswerView(item: card)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showAnswer = true } }
                .accessibilityHint(showAnswer ? "" : "Double tap to show the answer")

                if showAnswer {
                    HStack(spacing: 12) {
                        Button {
                            answer(card, known: false)
                        } label: { Label("Again", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered)
                        Button {
                            answer(card, known: true)
                        } label: { Label("Know it", systemImage: "checkmark").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).tint(tint)
                    }
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAnswer = true }
                    } label: { Text("Show answer").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(tint)
                }
            } else if deck.isEmpty {
                ContentUnavailableView("No cards", systemImage: "rectangle.on.rectangle", description: Text("This topic has no questions."))
            } else {
                ContentUnavailableView {
                    Label("Deck finished", systemImage: "checkmark.seal")
                } description: {
                    Text("\(deck.filter { progress.isCardKnown(course.id, $0.id) }.count) of \(deck.count) known.")
                } actions: {
                    Button("Go again") { buildDeck() }.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear { if deck.isEmpty { buildDeck() } }
        .onChange(of: topic) { _, _ in buildDeck() }
    }

    private func answer(_ card: QAItem, known: Bool) {
        progress.setCardKnown(course.id, card.id, known)
        showAnswer = false
        position += 1
    }

    private func buildDeck() {
        let pool = course.questions.filter { topic.isEmpty || $0.topic == topic }
        let unknown = pool.filter { !progress.isCardKnown(course.id, $0.id) }.shuffled()
        let known = pool.filter { progress.isCardKnown(course.id, $0.id) }.shuffled()
        deck = unknown + known
        position = 0
        showAnswer = false
    }
}
