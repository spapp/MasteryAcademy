import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                LearnView().routeDestinations()
            }
            .tabItem { Label("Learn", systemImage: "book") }

            NavigationStack {
                PracticeView().routeDestinations()
            }
            .tabItem { Label("Practice", systemImage: "checklist") }

            NavigationStack {
                SearchView().routeDestinations()
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }

            NavigationStack {
                ProfileView().routeDestinations()
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}

extension View {
    /// One place that maps a `Route` to its screen, shared by every tab's stack.
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .course(let id):
                CourseView(courseId: id)
            case .lesson(let courseId, let lessonId):
                LessonView(courseId: courseId, lessonId: lessonId)
            case .questions(let courseId):
                QuestionsView(courseId: courseId)
            case .flashcards(let courseId):
                FlashcardsView(courseId: courseId)
            case .quiz(let courseId):
                MixedQuizView(courseId: courseId)
            case .web(let courseId):
                InteractivePageView(courseId: courseId)
            case .notes(let courseId):
                NotesView(courseId: courseId)
            case .downloads:
                DownloadsView()
            case .interview(let courseId):
                MockInterviewView(courseId: courseId)
            }
        }
    }
}
