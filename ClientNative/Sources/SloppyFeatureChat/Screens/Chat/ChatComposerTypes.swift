import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import Textual
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
    public var markup: ChatImageMarkup? = nil

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
        uploadData.count
    }

    var uploadData: Data { markup?.pngData ?? data }
    var uploadMIMEType: String { markup == nil ? mimeType : "image/png" }
    var uploadName: String { markup == nil ? name : (name as NSString).deletingPathExtension + ".png" }

    var upload: ChatAttachmentUpload {
        ChatAttachmentUpload(
            name: uploadName,
            mimeType: uploadMIMEType,
            sizeBytes: sizeBytes,
            contentBase64: uploadData.base64EncodedString()
        )
    }

    var messageAttachment: ChatAttachment {
        ChatAttachment(
            id: id.uuidString.lowercased(),
            name: uploadName,
            mimeType: uploadMIMEType,
            sizeBytes: sizeBytes,
            previewData: uploadMIMEType.hasPrefix("image/") ? uploadData : nil
        )
    }
}

public struct ChatComposerQuote: Identifiable, Sendable, Equatable {
    public struct Source: Sendable, Equatable {
        public let messageID: String
        public let segmentIndex: Int
        public let location: TextAnnotationLocation
    }

    public let id: UUID
    public let text: String
    public var comment: String
    public let source: Source?
    public let browserSource: ChatImageAnnotation.BrowserSource?

    public init(id: UUID = UUID(), text: String, comment: String = "", source: Source? = nil,
                browserSource: ChatImageAnnotation.BrowserSource? = nil) {
        self.id = id
        self.text = text
        self.comment = comment
        self.source = source
        self.browserSource = browserSource
    }

    static func messageContent(
        _ content: String, quotes: [Self], attachments: [ChatComposerAttachment] = []
    ) -> String {
        let textAnnotations = quotes.map {
            ChatSentAnnotations.Annotation(
                selectedText: $0.text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"),
                comment: $0.comment.trimmingCharacters(in: .whitespacesAndNewlines),
                source: $0.browserSource.map { "Page URL: \($0.url.absoluteString)\nPage title: \($0.title)" }
            )
        }
        let imageAnnotations = attachments.enumerated().flatMap { index, attachment in
            attachment.annotations.map { annotation in
                ChatSentAnnotations.Annotation(
                    selectedText: "Image attachment \(index + 1): \(attachment.uploadName)\n"
                        + "Coordinates are percentages of the original image; origin is top-left.\n"
                        + annotation.region.coordinateDescription,
                    comment: annotation.comment,
                    source: annotation.browserSource.map {
                        "Page URL: \($0.url.absoluteString)\nPage title: \($0.title)"
                            + ($0.selector.map { "\nCSS selector: \($0)" } ?? "")
                    }
                )
            }
        }
        return ChatSentAnnotations(annotations: textAnnotations + imageAnnotations).attaching(to: content)
            ?? legacyMessageContent(content, quotes: quotes, attachments: attachments)
    }

    private static func legacyMessageContent(
        _ content: String, quotes: [Self], attachments: [ChatComposerAttachment]
    ) -> String {
        let quotedText = quotes.map { quote in
            let text = quote.text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .components(separatedBy: "\n")
                .map { "> \($0)" }
                .joined(separator: "\n")
            let comment = quote.comment.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = comment.isEmpty ? text : "\(text)\nComment: \(comment)"
            guard let source = quote.browserSource else { return note }
            return note + "\nPage URL: \(source.url.absoluteString)\nPage title: \(source.title)"
        }.joined(separator: "\n\n")
        let imageAnnotations = attachments.enumerated().compactMap { index, attachment -> String? in
            guard !attachment.annotations.isEmpty else { return nil }
            let notes = attachment.annotations.enumerated().map { number, annotation in
                let note = "\(number + 1). (\(annotation.region.coordinateDescription)) \(annotation.comment)"
                guard let source = annotation.browserSource else { return note }
                return note + "\nPage URL: \(source.url.absoluteString)\nPage title: \(source.title)"
                    + (source.selector.map { "\nCSS selector: \($0)" } ?? "")
            }.joined(separator: "\n")
            return "Image annotations — attachment \(index + 1): \(attachment.uploadName)\n"
                + "Coordinates are percentages of the original image; origin is top-left.\n\(notes)"
        }.joined(separator: "\n\n")
        return [quotedText, imageAnnotations, content].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

struct StoredComposerDraft {
    var text: String
    var attachments: [ChatComposerAttachment]
    var quotes: [ChatComposerQuote]
    var references: [ChatComposerReference] = []
}

enum PendingComposerTextMutation {
    case append(String)
    case replace(String)
}
