import SwiftUI
import UIKit

/// Numbers, account and sync, server address, content updates.
struct ProfileView: View {
    @Environment(ContentRepository.self) private var repository
    @Environment(ProgressStore.self) private var progress
    @Environment(AccountModel.self) private var account
    @Environment(AnnotationStore.self) private var reading
    @Environment(AttemptStore.self) private var attempts

    @AppStorage(APIClient.serverURLKey) private var serverURL = APIClient.defaultServerURL
    @AppStorage(APIClient.appKeyKey) private var appKey = ""
    @State private var aiMessage: String?
    @State private var checkingAI = false
    @State private var showSignIn = false
    @State private var showReading = false
    @State private var contentMessage: String?
    @State private var checkingContent = false
    @State private var confirmReset = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section("Progress") {
                LabeledContent("Day streak", value: "\(progress.streak)")
                LabeledContent("Lessons completed", value: "\(progress.totalDone(.lesson))")
                LabeledContent("Quizzes taken", value: "\(progress.totalDone(.quiz))")
                LabeledContent("Flashcards known", value: "\(progress.totalDone(.card))")
            }
            if !started.isEmpty {
                Section("Courses in progress") {
                    ForEach(started) { course in
                        NavigationLink(value: Route.course(course.id)) {
                            HStack(spacing: 12) {
                                ProgressRing(fraction: lessonFraction(course), tint: course.tintColor, lineWidth: 4)
                                    .frame(width: 26, height: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(course.title)
                                    Text(progressText(course)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }
            Section("Library") {
                NavigationLink(value: Route.downloads) {
                    Label("Downloads", systemImage: "arrow.down.circle")
                        .badge(repository.updatesAvailable.count)
                }
                Button {
                    showReading = true
                } label: {
                    Label("Reading settings", systemImage: "textformat.size")
                }
            }
            accountSection
            Section {
                TextField("Server address", text: $serverURL)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("App key for AI", text: $appKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button {
                    Task { await checkAI() }
                } label: {
                    HStack {
                        Text("Check AI")
                        if checkingAI { Spacer(); ProgressView() }
                    }
                }
                .disabled(checkingAI)
                if let aiMessage { Text(aiMessage).font(.footnote).foregroundStyle(.secondary) }
                Button {
                    Task { await checkContent() }
                } label: {
                    HStack {
                        Text("Check for course updates")
                        if checkingContent { Spacer(); ProgressView() }
                    }
                }
                .disabled(checkingContent)
                if let contentMessage { Text(contentMessage).font(.footnote).foregroundStyle(.secondary) }
            } header: {
                Text("Server")
            } footer: {
                Text("The app works without a server. A server adds the AI tutor and marking, sync between devices, and course updates without an app release. The app key is the APP_KEY set on your server. On an iPhone, localhost means the phone itself: enter your Mac's address on the same Wi-Fi instead, for example http://192.168.1.20:8000.")
            }
            Section {
                Button("Reset progress on this device", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle("Profile")
        .sheet(isPresented: $showSignIn) { SignInSheet() }
        .sheet(isPresented: $showReading) { ReadingSettingsSheet().presentationDetents([.medium, .large]) }
        .confirmationDialog("Reset all progress on this device?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset progress", role: .destructive) {
                progress.resetAll()
                reading.resetAll()
                attempts.resetAll()
            }
        } message: {
            Text("Completed lessons, quiz results, known cards, bookmarks, notes and highlights are removed from this device. Progress already synced to your account stays on the server.")
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await account.deleteAccount() } }
        } message: {
            Text("Your account and its synced progress are deleted from the server. Progress on this device stays.")
        }
    }

    private var started: [CourseSummary] {
        repository.availableCourses.filter { course in
            progress.count(course.id, .lesson) > 0 || progress.count(course.id, .card) > 0
        }
    }

    private func lessonFraction(_ course: CourseSummary) -> Double {
        if course.lessonCount == 0 { return 0 }
        return Double(progress.count(course.id, .lesson)) / Double(course.lessonCount)
    }

    private func progressText(_ course: CourseSummary) -> String {
        let lessons = "\(progress.count(course.id, .lesson)) of \(course.lessonCount) lessons"
        if course.questionCount == 0 { return lessons }
        let cards = "\(progress.count(course.id, .card)) of \(course.questionCount) cards"
        return lessons + " · " + cards
    }

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if let user = account.user {
                LabeledContent(user.displayName, value: user.email)
                HStack {
                    Text(syncText).font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button("Sync now") { Task { await account.sync() } }
                        .disabled(account.syncState == .syncing)
                }
                Button("Sign out") { Task { await account.signOut() } }
                Button("Delete account", role: .destructive) { confirmDelete = true }
            } else {
                Button("Sign in or create an account") { showSignIn = true }
            }
        } header: {
            Text("Account")
        } footer: {
            if !account.isSignedIn { Text("Progress is kept on this device. Sign in to keep it on your other devices too.") }
        }
    }

    private var syncText: String {
        switch account.syncState {
        case .idle: return "Not synced yet"
        case .syncing: return "Syncing…"
        case .synced(let date): return "Synced \(date.formatted(date: .omitted, time: .shortened))"
        case .failed(let reason): return reason
        }
    }

    private func checkAI() async {
        checkingAI = true
        defer { checkingAI = false }
        do {
            let usage = try await account.client.aiUsage()
            aiMessage = usage.summary
        } catch {
            aiMessage = error.localizedDescription
        }
    }

    private func checkContent() async {
        checkingContent = true
        defer { checkingContent = false }
        do {
            let updated = try await repository.refresh(using: account.client)
            contentMessage = updated.isEmpty ? "Courses are up to date." : "Updated: \(updated.joined(separator: ", "))."
        } catch {
            contentMessage = error.localizedDescription
        }
    }
}

private struct SignInSheet: View {
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""

    private var canSubmit: Bool {
        email.contains("@") && password.count >= (creating ? 8 : 1) && (!creating || !name.trimmingCharacters(in: .whitespaces).isEmpty) && !account.isWorking
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $creating) {
                    Text("Sign in").tag(false)
                    Text("Create account").tag(true)
                }
                .pickerStyle(.segmented)
                Section {
                    if creating { TextField("Name", text: $name).textContentType(.name) }
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(creating ? "Password, at least 8 characters" : "Password", text: $password)
                        .textContentType(creating ? .newPassword : .password)
                } footer: {
                    if let message = account.errorMessage { Text(message).foregroundStyle(.red) }
                }
                Button {
                    Task {
                        if creating {
                            await account.register(email: email, password: password, displayName: name.trimmingCharacters(in: .whitespaces))
                        } else {
                            await account.signIn(email: email, password: password, deviceName: UIDevice.current.name)
                        }
                        if account.isSignedIn { dismiss() }
                    }
                } label: {
                    HStack {
                        Text(creating ? "Create account" : "Sign in")
                        if account.isWorking { Spacer(); ProgressView() }
                    }
                }
                .disabled(!canSubmit)
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
