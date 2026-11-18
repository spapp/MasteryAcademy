import SwiftUI

/// Interview questions grouped by topic, with search and a level filter.
struct QuestionsView: View {
    let courseId: String

    var body: some View {
        CourseLoader(courseId: courseId) { course in
            QuestionsContent(course: course)
        }
        .navigationTitle("Interview questions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct QuestionsContent: View {
    let course: Course
    @State private var query = ""
    @State private var level = ""
    @State private var open: Set<String> = []

    private var levels: [String] {
        var seen: [String] = []
        for question in course.questions where !question.level.isEmpty && !seen.contains(question.level) { seen.append(question.level) }
        return seen
    }

    private var sections: [(topic: String, items: [QAItem])] {
        let needle = SearchEngine.fold(query.trimmingCharacters(in: .whitespaces))
        var order: [String] = []
        var grouped: [String: [QAItem]] = [:]
        for question in course.questions {
            if !level.isEmpty && question.level != level { continue }
            if !needle.isEmpty && !SearchEngine.fold(question.q + " " + question.a + " " + question.topic).contains(needle) { continue }
            if grouped[question.topic] == nil { order.append(question.topic) }
            grouped[question.topic, default: []].append(question)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        let groups = sections
        List {
            if levels.count > 1 {
                Picker("Level", selection: $level) {
                    Text("All levels").tag("")
                    ForEach(levels, id: \.self) { Text($0).tag($0) }
                }
            }
            ForEach(groups, id: \.topic) { section in
                Section("\(section.topic) · \(section.items.count)") {
                    ForEach(section.items) { item in
                        QuestionRow(item: item, isOpen: open.contains(item.id)) {
                            if open.contains(item.id) { open.remove(item.id) } else { open.insert(item.id) }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search questions and answers")
        .overlay {
            if groups.isEmpty { ContentUnavailableView.search(text: query) }
        }
    }
}

struct QuestionRow: View {
    let item: QAItem
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline) {
                    MarkupText(item.q).font(.body.weight(.medium)).multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Hides the answer" : "Shows the answer")
            if isOpen {
                AnswerView(item: item)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The model answer plus any extra sections (reasoning, trade-offs, follow-ups).
struct AnswerView: View {
    let item: QAItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MarkupText(item.a).font(.subheadline).textSelection(.enabled)
            ForEach(Array(item.points.enumerated()), id: \.offset) { _, point in
                VStack(alignment: .leading, spacing: 4) {
                    Text(point.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if point.items.count == 1 {
                        MarkupText(point.items[0]).font(.subheadline)
                    } else {
                        ListBlockView(ordered: false, items: point.items).font(.subheadline)
                    }
                }
            }
        }
    }
}
