import Foundation

/// Shared JSON settings. Dates are ISO 8601 UTC; fractional seconds are accepted when reading.
enum JSONCoding {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let text = try d.singleValueContainer().decode(String.self)
            if let date = parseDate(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "Not an ISO 8601 date: \(text)"))
        }
        return decoder
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func parseDate(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}
