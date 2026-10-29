import Foundation
import SloppyClientCore

/// A versioned message-content envelope keeps annotation snapshots in Core history,
/// including on servers that only accept plain text. Ordinary Markdown is never inferred
/// to be an annotation. Unknown or malformed envelopes remain visible as original text.
struct ChatSentAnnotations: Codable, Sendable, Equatable {
    struct Annotation: Codable, Sendable, Equatable {
        let selectedText: String
        let comment: String
        var source: String? = nil
    }

    let annotations: [Annotation]

    private static let prefix = "<sloppy-annotations version=\"1\">\n"
    private static let suffix = "\n</sloppy-annotations>\n\n"

    func attaching(to content: String) -> String? {
        guard !annotations.isEmpty else { return content }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self), let json = String(data: data, encoding: .utf8) else { return nil }
        return Self.prefix + json + Self.suffix + content
    }

    static func extract(from content: String) -> (annotations: [Annotation], content: String)? {
        guard content.hasPrefix(prefix),
              let end = content.range(of: suffix, range: content.index(content.startIndex, offsetBy: prefix.count)..<content.endIndex),
              let data = content[content.index(content.startIndex, offsetBy: prefix.count)..<end.lowerBound].data(using: .utf8),
              let payload = try? JSONDecoder().decode(Self.self, from: data),
              !payload.annotations.isEmpty else { return nil }
        return (payload.annotations, String(content[end.upperBound...]))
    }
}

struct ChatUserMessagePresentation {
    let segments: [ChatMessageSegment]
    let annotations: [ChatSentAnnotations.Annotation]

    init(message: ChatMessage) {
        guard message.role == .user else {
            self.segments = message.segments
            self.annotations = []
            return
        }
        var segments: [ChatMessageSegment] = []
        var annotations: [ChatSentAnnotations.Annotation] = []
        for var segment in message.segments {
            if segment.kind == .text, let text = segment.text,
               let extracted = ChatSentAnnotations.extract(from: text) {
                annotations += extracted.annotations
                guard !extracted.content.isEmpty else { continue }
                segment.text = extracted.content
            }
            segments.append(segment)
        }
        self.segments = segments
        self.annotations = annotations
    }
}
