import Foundation

public enum AIJSON {
    /// Pull a JSON object out of a model reply (raw, fenced, or wrapped in prose).
    public static func extractObject(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return trimmed }

        if let start = trimmed.range(of: "```json"),
           let end = trimmed.range(of: "```", range: start.upperBound..<trimmed.endIndex) {
            return String(trimmed[start.upperBound..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }

        return trimmed
    }

    public static func decode<T: Decodable>(_ type: T.Type, from content: String) throws -> T {
        let jsonString = extractObject(from: content)
        guard let data = jsonString.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "AI JSON is not UTF-8")
            )
        }
        return try JSONDecoder().decode(type, from: data)
    }
}

public enum OpenAIChatContent {
    public struct Message: Equatable, Sendable {
        public var text: String
        public var finishReason: String?

        public init(text: String, finishReason: String? = nil) {
            self.text = text
            self.finishReason = finishReason
        }

        public var isTruncated: Bool { finishReason == "length" }
    }

    public static func parse(_ data: Data) throws -> Message {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw OpenAIChatContentError.invalidResponse
        }
        return Message(text: content, finishReason: first["finish_reason"] as? String)
    }

    public static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        if let message = json["error"] as? String { return message }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return String(data: data, encoding: .utf8)
    }
}

public enum OpenAIChatContentError: Error, Equatable {
    case invalidResponse
}
