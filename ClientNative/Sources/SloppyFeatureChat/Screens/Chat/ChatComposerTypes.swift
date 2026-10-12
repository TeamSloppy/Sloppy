import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

public enum ChatComposerDictationPhase: Sendable, Equatable {
    case idle
    case recording
    case transcribing
}

public struct ChatComposerAttachment: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let mimeType: String
    public let data: Data
    public var annotations: [ChatImageAnnotation]

    public init(
        id: UUID = UUID(),
        name: String,
        mimeType: String,
        data: Data,
        annotations: [ChatImageAnnotation] = []
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.data = data
        self.annotations = annotations
    }

    public var sizeBytes: Int {
        data.count
    }

    var upload: ChatAttachmentUpload {
        ChatAttachmentUpload(
            name: name,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            contentBase64: data.base64EncodedString()
        )
    }

    var messageAttachment: ChatAttachment {
        ChatAttachment(
            id: id.uuidString.lowercased(),
            name: name,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            previewData: mimeType.hasPrefix("image/") ? data : nil
        )
    }
}

public struct ChatComposerQuote: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let text: String
    public var comment: String

    public init(id: UUID = UUID(), text: String, comment: String = "") {
        self.id = id
        self.text = text
        self.comment = comment
    }

    static func messageContent(
        _ content: String, quotes: [Self], attachments: [ChatComposerAttachment] = []
    ) -> String {
        let quotedText = quotes.map { quote in
            let text = quote.text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .components(separatedBy: "\n")
                .map { "> \($0)" }
                .joined(separator: "\n")
            let comment = quote.comment.trimmingCharacters(in: .whitespacesAndNewlines)
            return comment.isEmpty ? text : "\(text)\nComment: \(comment)"
        }.joined(separator: "\n\n")
        let imageAnnotations = attachments.enumerated().compactMap { index, attachment -> String? in
            guard !attachment.annotations.isEmpty else { return nil }
            let notes = attachment.annotations.enumerated().map { number, annotation in
                "\(number + 1). (\(annotation.region.coordinateDescription)) \(annotation.comment)"
            }.joined(separator: "\n")
            return "Image annotations — attachment \(index + 1): \(attachment.name)\n"
                + "Coordinates are percentages of the original image; origin is top-left.\n\(notes)"
        }.joined(separator: "\n\n")
        return [quotedText, imageAnnotations, content].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

struct StoredComposerDraft {
    var text: String
    var attachments: [ChatComposerAttachment]
    var quotes: [ChatComposerQuote]
}

enum PendingComposerTextMutation {
    case append(String)
    case replace(String)
}
