import SwiftUI

@main
struct MasteryAcademyApp: App {
    @State private var content: ContentRepository
    @State private var progress: ProgressStore
    @State private var account: AccountModel
    @State private var reading = AnnotationStore()
    @State private var attempts = AttemptStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let progress = ProgressStore()
        _content = State(initialValue: ContentRepository())
        _progress = State(initialValue: progress)
        _account = State(initialValue: AccountModel(client: APIClient(), progress: progress))
    }

    var body: some Scene {
        WindowGroup {
            SplashGate { RootView() }
                .environment(content)
                .environment(progress)
                .environment(account)
                .environment(reading)
                .environment(attempts)
                .task { await account.sync() }
                .onChange(of: scenePhase) { _, phase in
                    // Push what was learned in this visit when the app goes to the background.
                    if phase == .background {
                        reading.flush()
                        Task { await account.sync() }
                    }
                }
        }
    }
}
