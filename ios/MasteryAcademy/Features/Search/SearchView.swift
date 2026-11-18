import SwiftUI

/// Search across every installed course: lessons and interview questions.
struct SearchView: View {
    @Environment(ContentRepository.self) private var repository
    @State private var query = ""
    @State private var engine: SearchEngine?
    @State private var hits: [SearchHit] = []
    @State private var opened: SearchHit?

    var body: some View {
        List {
            ForEach(hits) { hit in
                switch hit.kind {
                case .lesson:
                    NavigationLink(value: Route.lesson(courseId: hit.courseId, lessonId: hit.itemId)) { HitRow(hit: hit) }
                case .question:
                    Button { opened = hit } label: { HitRow(hit: hit) }.buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Lessons, problems, interview questions")
        .overlay {
            if engine == nil {
                ProgressView("Preparing search…")
            } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView("Search your courses", systemImage: "magnifyingglass",
                                       description: Text("Try a topic such as actor, sliding window or cache stampede."))
            } else if hits.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .task { await buildIndex() }
        .task(id: searchKey) {
            // Wait for a pause in typing; a newer keystroke cancels this task.
            // The key also changes when the index becomes ready, so a query typed while it was loading still runs.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let engine else { return }
            let text = query
            let found = await Task.detached(priority: .userInitiated) { engine.search(text) }.value
            if !Task.isCancelled { hits = found }
        }
        .sheet(item: $opened) { hit in
            QuestionSheet(hit: hit)
        }
    }

    private var searchKey: String {
        (engine == nil ? "0|" : "1|") + query
    }

    private func buildIndex() async {
        guard engine == nil else { return }
        var courses: [Course] = []
        for summary in repository.availableCourses {
            if let course = try? await repository.course(summary.id) { courses.append(course) }
        }
        let loaded = courses
        engine = await Task.detached(priority: .utility) { SearchEngine(courses: loaded) }.value
    }
}

private struct HitRow: View {
    let hit: SearchHit

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: hit.kind == .lesson ? "book" : "text.bubble").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title).lineLimit(3).multilineTextAlignment(.leading)
                Text("\(hit.courseTitle) · \(hit.detail)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

private struct QuestionSheet: View {
    let hit: SearchHit
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CourseLoader(courseId: hit.courseId) { course in
                ScrollView {
                    if let item = course.questions.first(where: { $0.id == hit.itemId }) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(item.topic.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            MarkupText(item.q).font(.title3.weight(.semibold))
                            AnswerView(item: item)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                }
            }
            .navigationTitle(hit.courseTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
