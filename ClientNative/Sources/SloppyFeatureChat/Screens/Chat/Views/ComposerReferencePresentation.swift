#if os(macOS)
import Foundation
import AppKit
import SloppyClientCore

@MainActor
final class ComposerReferenceAttachment: NSTextAttachment {
    let reference: ChatComposerReference

    init(reference: ChatComposerReference, style: AppKitComposerTextStyle) {
        self.reference = reference
        super.init(data: nil, ofType: nil)
        let font = style.font
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.linkColor, .paragraphStyle: paragraph,
        ]
        let label = reference.title as NSString
        let width = min(280, max(60, label.size(withAttributes: attributes).width + 30))
        let height = ceil(font.ascender - font.descender) + 6
        let image = NSImage(size: NSSize(width: width, height: height))
        image.accessibilityDescription = reference.title
        image.lockFocus()
        NSColor.linkColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height), xRadius: 4, yRadius: 4).fill()
        NSImage(systemSymbolName: reference.systemImage, accessibilityDescription: reference.title)?
            .withSymbolConfiguration(.init(hierarchicalColor: .linkColor))?
            .draw(in: NSRect(x: 5, y: (height - 14) / 2, width: 14, height: 14))
        label.draw(in: NSRect(x: 24, y: 3, width: width - 28, height: height - 4), withAttributes: attributes)
        image.unlockFocus()
        self.image = image
        bounds = NSRect(x: 0, y: -4, width: width, height: height)
    }

    required init?(coder: NSCoder) { return nil }
}

/// Converts the native attachment string to wire text without losing UTF-16 offsets.
struct ComposerReferenceProjection {
    struct Span {
        let displayRange: NSRange
        let rawLength: Int
    }
    let rawText: String
    let spans: [Span]

    init(_ display: NSAttributedString) {
        var raw = ""
        var spans: [Span] = []
        display.enumerateAttribute(.attachment, in: NSRange(location: 0, length: display.length)) { value, range, _ in
            if let attachment = value as? ComposerReferenceAttachment {
                raw += attachment.reference.rawText
                spans.append(.init(displayRange: range, rawLength: attachment.reference.rawText.utf16.count))
            } else {
                raw += (display.string as NSString).substring(with: range)
            }
        }
        rawText = raw
        self.spans = spans
    }

    func rawOffset(_ displayOffset: Int) -> Int {
        var delta = 0
        for span in spans {
            if displayOffset <= span.displayRange.location { break }
            delta += span.rawLength - span.displayRange.length
        }
        return displayOffset + delta
    }

    func displayOffset(_ rawOffset: Int, upperBound: Bool) -> Int {
        var delta = 0
        for span in spans {
            let start = span.displayRange.location + delta
            if rawOffset <= start { break }
            if rawOffset < start + span.rawLength {
                return span.displayRange.location + (upperBound ? span.displayRange.length : 0)
            }
            delta += span.rawLength - span.displayRange.length
        }
        return rawOffset - delta
    }

    func rawRange(_ range: NSRange) -> NSRange {
        let start = rawOffset(range.location)
        return NSRange(location: start, length: rawOffset(NSMaxRange(range)) - start)
    }

    func displayRange(_ range: NSRange) -> NSRange {
        let start = displayOffset(range.location, upperBound: range.length == 0)
        return NSRange(location: start, length: displayOffset(NSMaxRange(range), upperBound: true) - start)
    }
}

@MainActor
enum ComposerReferencePresentation {
    static func link(for reference: ChatComposerReference) -> String {
        switch reference.target {
        case .session(let agent, let session):
            DeepLink.session(agentId: agent, sessionId: session).url?.absoluteString ?? reference.rawText
        case .website(let url): url.absoluteString
        default: reference.rawText
        }
    }

    static func attributed(_ raw: String, references: [ChatComposerReference], style: AppKitComposerTextStyle) -> NSAttributedString {
        let source = raw as NSString
        var matches: [(NSRange, ChatComposerReference)] = []
        var codeRanges = ChatComposerCodeFence.ranges(in: raw)
        if let code = try? NSRegularExpression(pattern: #"`[^`\n]*`"#) {
            codeRanges += code.matches(in: raw, range: NSRange(location: 0, length: source.length)).map(\.range)
        }
        for reference in references where !reference.rawText.isEmpty {
            var search = NSRange(location: 0, length: source.length)
            while search.length > 0 {
                let range = source.range(of: reference.rawText, options: [], range: search)
                guard range.location != NSNotFound else { break }
                let before = range.location == 0 || UnicodeScalar(source.character(at: range.location - 1))
                    .map { CharacterSet.whitespacesAndNewlines.contains($0) } == true
                let end = NSMaxRange(range)
                let after = end == source.length || UnicodeScalar(source.character(at: end))
                    .map { CharacterSet.whitespacesAndNewlines.contains($0) } == true
                if before && after { matches.append((range, reference)) }
                search = NSRange(location: end, length: source.length - end)
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"\[((?:\\.|[^\]\\])*)\]\((sloppy://session\?[^\s)]+|https?://[^\s)]+)\)"#) {
            for match in regex.matches(in: raw, range: NSRange(location: 0, length: source.length)) {
                guard !matches.contains(where: { $0.0 == match.range }) else { continue }
                let address = source.substring(with: match.range(at: 2))
                guard let url = URL(string: address) else { continue }
                let label = source.substring(with: match.range(at: 1))
                    .replacingOccurrences(of: #"\\(.)"#, with: "$1", options: .regularExpression)
                let target: ChatComposerReference.Target
                if case .session(let agent, let session) = DeepLink.parse(url) {
                    target = .session(agentId: agent, sessionId: session)
                } else if url.scheme == "https" || url.scheme == "http" {
                    target = .website(url)
                } else { continue }
                matches.append((match.range, .init(rawText: source.substring(with: match.range),
                    title: label.hasPrefix("@") ? String(label.dropFirst()) : label, target: target)))
            }
        }
        let result = NSMutableAttributedString(string: "")
        var cursor = 0
        for (range, reference) in matches.sorted(by: {
            $0.0.location == $1.0.location ? $0.0.length > $1.0.length : $0.0.location < $1.0.location
        }) {
            guard range.location >= cursor, !codeRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) else { continue }
            result.append(NSAttributedString(string: source.substring(with: NSRange(location: cursor, length: range.location - cursor)), attributes: style.baseAttributes))
            let attachment = ComposerReferenceAttachment(reference: reference, style: style)
            let token = NSMutableAttributedString(attachment: attachment)
            token.addAttributes([.font: style.font, .toolTip: reference.rawText, .link: link(for: reference)], range: NSRange(location: 0, length: token.length))
            result.append(token)
            cursor = NSMaxRange(range)
        }
        result.append(NSAttributedString(string: source.substring(from: cursor), attributes: style.baseAttributes))
        return result
    }
}
#endif
