import SwiftUI

/// Home: where you left off, your numbers, and every course grouped by area.
struct LearnView: View {
    @Environment(ContentRepository.self) private var repository
    @Environment(ProgressStore.self) private var progress
    @State private var planned: CourseSummary?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let message = repository.loadError {
                    ContentUnavailableView("No courses", systemImage: "books.vertical", description: Text(message))
                }
                continueCard
                statsRow
                ForEach(repository.groups, id: \.name) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.name).font(.title3.weight(.semibold))
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(group.courses) { course in
                                if course.isAvailable {
                                    NavigationLink(value: Route.course(course.id)) { CourseCard(course: course) }
                                        .buttonStyle(.plain)
                                } else {
                                    Button { planned = course } label: { CourseCard(course: course) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Mastery Academy")
        .sheet(item: $planned) { course in
            PlannedCourseSheet(course: course)
                .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var continueCard: some View {
        if let courseId = progress.lastCourseId, let lessonId = progress.lastLessonId, let course = repository.summary(courseId), course.isAvailable {
            NavigationLink(value: Route.lesson(courseId: courseId, lessonId: lessonId)) {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(course.tintColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Continue").font(.caption).foregroundStyle(.secondary)
                        Text(course.title).font(.headline)
                        Text("Pick up the lesson you opened last").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .card()
            }
            .buttonStyle(.plain)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatTile(value: "\(progress.streak)", label: progress.streak == 1 ? "day streak" : "days streak", symbol: "flame")
            StatTile(value: "\(progress.totalDone(.lesson))", label: "lessons done", symbol: "checkmark.circle")
            StatTile(value: "\(progress.totalDone(.card))", label: "cards known", symbol: "rectangle.on.rectangle")
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

struct CourseCard: View {
    let course: CourseSummary
    @Environment(ProgressStore.self) private var progress
    @Environment(ContentRepository.self) private var repository

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: course.icon)
                    .font(.title2)
                    .foregroundStyle(course.isAvailable ? course.tintColor : Color.secondary)
                    .frame(width: 36, height: 36, alignment: .leading)
                Spacer()
                if course.isAvailable {
                    ProgressRing(fraction: fraction, tint: course.tintColor, lineWidth: 4).frame(width: 28, height: 28)
                } else {
                    Text("Soon").font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                }
            }
            Text(course.title).font(.headline).multilineTextAlignment(.leading)
            Text(course.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if course.isAvailable {
                HStack(spacing: 4) {
                    Text(countText).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    if repository.updatesAvailable.contains(course.id) {
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.down.circle.fill").font(.caption).foregroundStyle(.orange)
                            .accessibilityLabel("Update available")
                    }
                }
            }
        }
        .frame(minHeight: 150, alignment: .top)
        .card()
        .opacity(course.isAvailable ? 1 : 0.75)
        .accessibilityElement(children: .combine)
        .accessibilityHint(course.isAvailable ? "Opens the course" : "Not converted yet")
    }

    private var countText: String {
        "\(progress.count(course.id, .lesson)) of \(course.lessonCount) lessons · " + formatMinutes(course.minutes)
    }

    private var fraction: Double {
        course.lessonCount == 0 ? 0 : Double(progress.count(course.id, .lesson)) / Double(course.lessonCount)
    }
}

/// A course that is listed in the catalog but not converted to native lessons yet.
struct PlannedCourseSheet: View {
    let course: CourseSummary
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Label(course.title, systemImage: course.icon).font(.title2.weight(.semibold))
                Text(course.subtitle).foregroundStyle(.secondary)
                Text("This course is not in the app yet. Until it is converted you can read the original interactive version in the browser.")
                if let note = course.note {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
                if let link = course.artifactURL, let url = URL(string: link) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Open the original course", systemImage: "safari").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
