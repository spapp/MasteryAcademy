import Foundation
import SwiftUI

/// A small tokenizer that colours Swift (and similar C-style) code. It is for reading, not for parsing:
/// comments, strings, numbers, keywords, attributes and capitalised type names.
enum SwiftHighlighter {
    enum Kind: Equatable {
        case plain, comment, string, number, keyword, type, attribute
    }

    struct Token: Equatable {
        let kind: Kind
        let text: String
    }

    static let keywords: Set<String> = [
        "actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch", "class", "continue", "default", "defer",
        "deinit", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "final", "for", "func", "guard", "if",
        "import", "in", "indirect", "init", "inout", "internal", "is", "isolated", "lazy", "let", "mutating", "nil", "nonisolated",
        "open", "operator", "override", "private", "protocol", "public", "repeat", "rethrows", "return", "self", "Self", "some",
        "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias", "var", "weak", "unowned",
        "where", "while", "consuming", "borrowing", "sending", "macro",
    ]

    static func tokenize(_ code: String) -> [Token] {
        let chars = Array(code)
        var tokens: [Token] = []
        var plain = ""
        var i = 0

        func flush() {
            if !plain.isEmpty { tokens.append(Token(kind: .plain, text: plain)); plain = "" }
        }
        func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

        while i < chars.count {
            let c = chars[i]
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                flush()
                var j = i
                while j < chars.count, chars[j] != "\n" { j += 1 }
                tokens.append(Token(kind: .comment, text: String(chars[i..<j])))
                i = j
            } else if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                flush()
                var j = i + 2
                while j + 1 < chars.count, !(chars[j] == "*" && chars[j + 1] == "/") { j += 1 }
                j = min(j + 2, chars.count)
                tokens.append(Token(kind: .comment, text: String(chars[i..<j])))
                i = j
            } else if c == "\"" {
                flush()
                var j = i + 1
                while j < chars.count, chars[j] != "\"", chars[j] != "\n" {
                    if chars[j] == "\\" { j += 1 }
                    j += 1
                }
                j = min(j + 1, chars.count)
                tokens.append(Token(kind: .string, text: String(chars[i..<j])))
                i = j
            } else if c == "@" || c == "#", i + 1 < chars.count, chars[i + 1].isLetter {
                flush()
                var j = i + 1
                while j < chars.count, isWord(chars[j]) { j += 1 }
                tokens.append(Token(kind: .attribute, text: String(chars[i..<j])))
                i = j
            } else if c.isNumber, i == 0 || !isWord(chars[i - 1]) {
                flush()
                var j = i
                while j < chars.count, isWord(chars[j]) || (chars[j] == "." && j + 1 < chars.count && chars[j + 1].isNumber) { j += 1 }
                tokens.append(Token(kind: .number, text: String(chars[i..<j])))
                i = j
            } else if c.isLetter || c == "_" {
                var j = i
                while j < chars.count, isWord(chars[j]) { j += 1 }
                let word = String(chars[i..<j])
                if keywords.contains(word) {
                    flush(); tokens.append(Token(kind: .keyword, text: word))
                } else if let first = word.first, first.isUppercase {
                    flush(); tokens.append(Token(kind: .type, text: word))
                } else {
                    plain += word
                }
                i = j
            } else {
                plain.append(c)
                i += 1
            }
        }
        flush()
        return tokens
    }

    static func attributed(_ code: String) -> AttributedString {
        var result = AttributedString()
        for token in tokenize(code) {
            var part = AttributedString(token.text)
            switch token.kind {
            case .plain: break
            case .comment: part.swiftUI.foregroundColor = Color.secondary
            case .string: part.swiftUI.foregroundColor = Color(uiColor: .systemRed)
            case .number: part.swiftUI.foregroundColor = Color(uiColor: .systemOrange)
            case .keyword: part.swiftUI.foregroundColor = Color(uiColor: .systemPink)
            case .type: part.swiftUI.foregroundColor = Color(uiColor: .systemTeal)
            case .attribute: part.swiftUI.foregroundColor = Color(uiColor: .systemPurple)
            }
            result.append(part)
        }
        return result
    }
}
