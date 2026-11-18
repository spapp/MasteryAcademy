import SwiftUI

struct CourseView: View {
    let courseId: String
    @Environment(ContentRepository.self) private var repository

    var body: some View {
        CourseLoader(courseId: courseId) { course in
            CourseContentView(course: course, summary: repository.summary(courseId))
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CourseContentView: View {
    let course: Course
    let summary: CourseSummary?

    @Environment(ProgressStore.self) private var progress
    @Environment(AnnotationStore.self) private var reading
    @Environment(\.openURL) private var openURL
    @State private var expanded: Set<String> = []
    @State private var didExpand = false

    private var tint: Color { summary?.tintColor ?? .accentColor }

    var body: some View {
        List {
            Section {
                header
                if let next = nextLesson {
                    NavigationLink(value: Route.lesson(courseId: course.id, lessonId: next.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(startLabel).font(.caption.weight(.semibold)).foregroundStyle(tint)
                            MarkupText(next.title).font(.headline)
                            Text(formatMinutes(next.minutes)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Practice") {
                if !course.questions.isEmpty {
                    NavigationLink(value: Route.flashcards(courseId: course.id)) {
                        Label("Flashcards", systemImage: "rectangle.on.rectangle")
                            .badge("\(progress.count(course.id, .card))/\(course.questions.count)")
                    }
                    NavigationLink(value: Route.questions(courseId: course.id)) {
                        Label("Interview questions", systemImage: "text.bubble").badge(course.questions.count)
                    }
                    NavigationLink(value: Route.interview(courseId: course.id)) {
                        Label("Mock interview, marked by AI", systemImage: "sparkles")
                    }
                }
                if (summary?.quizCount ?? 0) > 0 {
                    NavigationLink(value: Route.quiz(courseId: course.id)) {
                        Label("Quick quiz, 10 questions", systemImage: "checklist")
                    }
                }
                if summary?.web != nil {
                    NavigationLink(value: Route.web(courseId: course.id)) {
                        Label("Simulators and playgrounds", systemImage: "play.rectangle")
                    }
                } else if let link = summary?.artifactURL, let url = URL(string: link) {
                    Button { openURL(url) } label: { Label("Open the original course page", systemImage: "safari") }
                }
                NavigationLink(value: Route.notes(courseId: course.id)) {
                    Label("Notes and highlights", systemImage: "note.text").badge(reading.count(courseId: course.id))
                }
            }
            let bookmarks = progress.bookmarks(course.id).compactMap { course.lesson(id: $0) }
            if !bookmarks.isEmpty {
                Section("Bookmarks") {
                    ForEach(bookmarks) { lesson in LessonRow(courseId: course.id, lesson: lesson, tint: tint) }
                }
            }
            ForEach(course.modules) { module in
                Section {
                    DisclosureGroup(isExpanded: binding(for: module.id)) {
                        ForEach(module.lessons) { lesson in LessonRow(courseId: course.id, lesson: lesson, tint: tint) }
                    } label: {
                        ModuleHeader(module: module, done: module.lessons.filter { progress.isLessonDone(course.id, $0.id) }.count)
                    }
                }
            }
            if !course.resources.isEmpty {
                Section("Resources") {
                    ForEach(Array(course.resources.enumerated()), id: \.offset) { _, link in LinkRow(link: link) }
                }
            }
        }
        .navigationTitle(course.title)
        .onAppear {
            guard !didExpand else { return }
            didExpand = true
            // Open the module the learner is in: the first one with an unfinished lesson.
            if let current = course.modules.first(where: { module in module.lessons.contains { !progress.isLessonDone(course.id, $0.id) } }) {
                expanded.insert(current.id)
            }
        }
    }

    /// The first lesson that is not done yet, in course order.
    private var nextLesson: Lesson? {
        course.allLessons.first { !progress.isLessonDone(course.id, $0.id) }
    }

    private var startLabel: String {
        progress.count(course.id, .lesson) == 0 ? "Start here" : "Continue"
    }

    private var minutesLeft: Int {
        course.allLessons.reduce(0) { $0 + (progress.isLessonDone(course.id, $1.id) ? 0 : $1.minutes) }
    }

    private var header: some View {
        let done = progress.count(course.id, .lesson)
        let total = course.allLessons.count
        return HStack(spacing: 14) {
            ProgressRing(fraction: total == 0 ? 0 : Double(done) / Double(total), tint: tint, lineWidth: 6)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(course.subtitle).font(.subheadline)
                Text("\(done) of \(total) lessons · \(formatMinutes(minutesLeft)) left")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }

    private func binding(for moduleId: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(moduleId) },
                set: { open in
                    if open { expanded.insert(moduleId) } else { expanded.remove(moduleId) }
                })
    }
}

private struct ModuleHeader: View {
    let module: CourseModule
    let done: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(module.title).font(.headline)
            if !module.summary.isEmpty {
                MarkupText(module.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Text("\(done) of \(module.lessons.count) done").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

struct LessonRow: View {
    let courseId: String
    let lesson: Lesson
    let tint: Color
    @Environment(ProgressStore.self) private var progress

    var body: some View {
        NavigationLink(value: Route.lesson(courseId: courseId, lessonId: lesson.id)) {
            HStack(spacing: 10) {
                let done = progress.isLessonDone(courseId, lesson.id)
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? tint : Color.secondary)
                    .accessibilityLabel(done ? "Done" : "Not done")
                VStack(alignment: .leading, spacing: 2) {
                    MarkupText(lesson.title)
                    HStack(spacing: 8) {
                        Text(formatMinutes(lesson.minutes))
                        if !lesson.quiz.isEmpty { Label("Quiz", systemImage: "checklist") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct LinkRow: View {
    let link: LinkItem
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = URL(string: link.url) { openURL(url) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.title).multilineTextAlignment(.leading)
                    Text(link.kind).font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityHint("Opens in the browser")
    }
}
