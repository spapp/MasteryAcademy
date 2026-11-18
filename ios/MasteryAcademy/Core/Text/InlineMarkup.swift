import Foundation
import SwiftUI

/// The small inline markup used by course content: `code`, **bold** and *italic*. Nothing else is interpreted.
enum InlineMarkup {
    enum Span: Equatable {
        case plain(String)
        case bold(String)
        case italic(String)
        case code(String)
    }

    static func parse(_ source: String) -> [Span] {
        let chars = Array(source)
        var spans: [Span] = []
        var plain = ""
        var i = 0

        func flush() {
            if !plain.isEmpty { spans.append(.plain(plain)); plain = "" }
        }
        /// Index of the first occurrence of `marker` at or after `start`.
        func find(_ marker: [Character], from start: Int) -> Int? {
            guard marker.count <= chars.count else { return nil }
            var j = start
            while j + marker.count <= chars.count {
                if Array(chars[j..<(j + marker.count)]) == marker { return j }
                j += 1
            }
            return nil
        }

        while i < chars.count {
            let c = chars[i]
            if c == "`", let end = find(["`"], from: i + 1), end > i + 1 {
                flush()
                spans.append(.code(String(chars[(i + 1)..<end])))
                i = end + 1
            } else if c == "*", i + 1 < chars.count, chars[i + 1] == "*", let end = find(["*", "*"], from: i + 2), end > i + 2 {
                flush()
                spans.append(.bold(String(chars[(i + 2)..<end]).replacingOccurrences(of: "`", with: "")))
                i = end + 2
            } else if c == "*", i + 1 < chars.count, !chars[i + 1].isWhitespace, chars[i + 1] != "*",
                      let end = find(["*"], from: i + 1), end > i + 1, !chars[end - 1].isWhitespace {
                flush()
                spans.append(.italic(String(chars[(i + 1)..<end])))
                i = end + 1
            } else {
                plain.append(c)
                i += 1
            }
        }
        flush()
        return spans
    }

    static func attributed(_ source: String) -> AttributedString {
        var result = AttributedString()
        for span in parse(source) {
            switch span {
            case .plain(let text):
                result.append(AttributedString(text))
            case .bold(let text):
                var part = AttributedString(text)
                part.inlinePresentationIntent = .stronglyEmphasized
                result.append(part)
            case .italic(let text):
                var part = AttributedString(text)
                part.inlinePresentationIntent = .emphasized
                result.append(part)
            case .code(let text):
                var part = AttributedString(text)
                part.inlinePresentationIntent = .code
                part.swiftUI.foregroundColor = Color.accentColor
                result.append(part)
            }
        }
        return result
    }

    /// The text with markup removed, for search and accessibility.
    static func plain(_ source: String) -> String {
        parse(source).map { span -> String in
            switch span {
            case .plain(let t), .bold(let t), .italic(let t), .code(let t): return t
            }
        }.joined()
    }
}

/// Body text with inline markup.
struct MarkupText: View {
    let source: String

    init(_ source: String) { self.source = source }

    var body: some View {
        Text(InlineMarkup.attributed(source))
    }
}
