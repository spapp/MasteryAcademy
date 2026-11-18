import SwiftUI

extension Color {
    /// "#RRGGBB" from the catalog. Falls back to the accent colour for anything else.
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .accentColor
            return
        }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

extension CourseSummary {
    var tintColor: Color { Color(hex: tint) }
}

/// Rounded panel used for cards across the app.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

struct ProgressRing: View {
    let fraction: Double
    var tint: Color = .accentColor
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

/// Loads a course and shows loading and failure states around the content.
struct CourseLoader<Content: View>: View {
    let courseId: String
    @ViewBuilder let content: (Course) -> Content

    @Environment(ContentRepository.self) private var repository
    @State private var course: Course?
    @State private var failure: String?

    var body: some View {
        Group {
            if let course {
                content(course)
            } else if let failure {
                ContentUnavailableView("Can't open this course", systemImage: "exclamationmark.triangle", description: Text(failure))
            } else {
                ProgressView("Loading…")
            }
        }
        .task(id: courseId) {
            do {
                course = try await repository.course(courseId)
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

func formatMinutes(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes) min" }
    let hours = minutes / 60, rest = minutes % 60
    return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
}
