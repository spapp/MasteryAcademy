import SwiftUI

/// Every highlight and note in one course, with a way back to the lesson and a Markdown export.
struct NotesView: View {
    let courseId: String

    var body: some View {
        CourseLoader(courseId: courseId) { course in
            NotesContent(course: course)
        }
        .navigationTitle("Notes and highlights")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NotesContent: View {
    let course: Course
    @Environment(AnnotationStore.self) private var reading

    var body: some View {
        let items = reading.annotations(courseId: course.id)
        List {
            ForEach(items) { item in
                NavigationLink(value: Route.lesson(courseId: course.id, lessonId: item.lessonId)) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(InlineMarkup.plain(course.lesson(id: item.lessonId)?.title ?? "Lesson"))
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        HStack(alignment: .top, spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(item.highlighted ? Color.yellow : Color.secondary.opacity(0.35))
                                .frame(width: 3)
                            Text(item.excerpt).font(.subheadline).lineLimit(4)
                        }
                        if !item.note.isEmpty {
                            Label(item.note, systemImage: "note.text").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .onDelete { offsets in
                for index in offsets { reading.remove(items[index]) }
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("No notes yet", systemImage: "highlighter",
                                       description: Text("Touch and hold a paragraph in a lesson to highlight it or add a note."))
            }
        }
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: reading.markdown(for: course)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share notes as Markdown")
                }
            }
        }
    }
}
