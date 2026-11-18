import SwiftUI

/// Keys of the reading settings kept in UserDefaults. Views read them with @AppStorage, so a change
/// in the settings sheet shows in the lesson behind it at once and stays for every later lesson.
enum ReadingKeys {
    static let textStep = "reading.textStep"
    static let lineSpacing = "reading.lineSpacing"
    static let width = "reading.width"
    static let theme = "reading.theme"
    static let codeWrap = "reading.codeWrap"
    static let wifiOnly = "downloads.wifiOnly"
}

enum ReadingTheme: String, CaseIterable, Identifiable {
    case system, light, dark, sepia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        case .sepia: return "Sepia"
        }
    }

    /// nil follows the device.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light, .sepia: return .light
        case .dark: return .dark
        }
    }

    var background: Color {
        switch self {
        case .system: return Color(uiColor: .systemBackground)
        case .light: return .white
        case .dark: return Color(red: 0.07, green: 0.07, blue: 0.08)
        case .sepia: return Color(red: 0.97, green: 0.94, blue: 0.87)
        }
    }
}

enum ReadingLineSpacing: String, CaseIterable, Identifiable {
    case compact, normal, relaxed

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var points: CGFloat {
        switch self {
        case .compact: return 1
        case .normal: return 4
        case .relaxed: return 9
        }
    }
}

enum ReadingWidth: String, CaseIterable, Identifiable {
    case narrow, normal, wide

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var maxWidth: CGFloat {
        switch self {
        case .narrow: return 560
        case .normal: return 760
        case .wide: return 1100
        }
    }

    /// Side margin on a phone, where the maximum width never applies.
    var margin: CGFloat {
        switch self {
        case .narrow: return 30
        case .normal: return 16
        case .wide: return 8
        }
    }
}

enum ReadingStyle {
    static let stepRange = -2...4

    /// The text size for a lesson: the device's size moved by `step` places, kept inside the sizes iOS has.
    static func dynamicTypeSize(base: DynamicTypeSize, step: Int) -> DynamicTypeSize {
        let all = Array(DynamicTypeSize.allCases)
        guard let index = all.firstIndex(of: base) else { return base }
        let target = min(max(index + step, 0), all.count - 1)
        return all[target]
    }

    /// Minutes still to read when `fraction` of the lesson is behind the reader.
    static func minutesLeft(total: Int, fraction: Double) -> Int {
        let clamped = min(max(fraction, 0), 1)
        return Int((Double(total) * (1 - clamped)).rounded(.up))
    }
}

extension View {
    /// Forces light or dark inside a lesson without touching the rest of the app.
    @ViewBuilder
    func readingColorScheme(_ scheme: ColorScheme?) -> some View {
        if let scheme {
            environment(\.colorScheme, scheme)
        } else {
            self
        }
    }
}
