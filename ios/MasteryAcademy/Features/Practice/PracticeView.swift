import SwiftUI

/// Flashcards, interview questions and quizzes for every installed course.
struct PracticeView: View {
    @Environment(ContentRepository.self) private var repository
    @Environment(ProgressStore.self) private var progress

    var body: some View {
        List {
            ForEach(repository.availableCourses) { course in
                Section(course.title) {
                    if course.questionCount > 0 {
                        NavigationLink(value: Route.flashcards(courseId: course.id)) {
                            Label("Flashcards", systemImage: "rectangle.on.rectangle")
                                .badge("\(progress.count(course.id, .card))/\(course.questionCount)")
                        }
                        NavigationLink(value: Route.questions(courseId: course.id)) {
                            Label("Interview questions", systemImage: "text.bubble").badge(course.questionCount)
                        }
                    }
                    if course.quizCount > 0 {
                        NavigationLink(value: Route.quiz(courseId: course.id)) {
                            Label("Quick quiz, 10 questions", systemImage: "checklist")
                        }
                    }
                }
            }
        }
        .navigationTitle("Practice")
        .overlay {
            if repository.availableCourses.isEmpty {
                ContentUnavailableView("Nothing to practise yet", systemImage: "checklist", description: Text("Install a course first."))
            }
        }
    }
}

/// Ten quiz questions drawn from the whole course.
struct MixedQuizView: View {
    let courseId: String
    @Environment(ContentRepository.self) private var repository
    @Environment(ProgressStore.self) private var progress

    var body: some View {
        CourseLoader(courseId: courseId) { course in
            MixedQuizContent(course: course, tint: repository.summary(courseId)?.tintColor ?? .accentColor) { score, total in
                progress.setQuizResult(courseId, "mixed", score: score, total: total)
            }
        }
        .navigationTitle("Quick quiz")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MixedQuizContent: View {
    let course: Course
    let tint: Color
    let onFinish: (Int, Int) -> Void
    @State private var questions: [QuizQuestion] = []
    @State private var round = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if questions.isEmpty {
                    ContentUnavailableView("No quiz questions", systemImage: "checklist", description: Text("This course has no quiz questions yet."))
                } else {
                    QuizView(questions: questions, tint: tint, onFinish: onFinish).id(round)
                    Button("New set of questions") { draw() }
                }
            }
            .padding()
        }
        .onAppear { if questions.isEmpty { draw() } }
    }

    private func draw() {
        questions = Array(course.allLessons.flatMap { $0.quiz }.shuffled().prefix(10))
        round += 1
    }
}
