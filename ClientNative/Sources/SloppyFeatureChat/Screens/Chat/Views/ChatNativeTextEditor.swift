import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum ChatComposerPasteboard {
    static func containsAttachmentType(_ typeIdentifiers: [String]) -> Bool {
        typeIdentifiers.compactMap(UTType.init).contains(where: isAttachmentType)
    }

    static func isAttachmentType(_ type: UTType) -> Bool {
        if type.conforms(to: .fileURL) || type.conforms(to: .directory) {
            return true
        }
        return type.conforms(to: .data)
            && !type.conforms(to: .text)
            && !type.conforms(to: .url)
    }
}

enum ChatComposerNativeSelection {
    static func nativeRange(
        from selection: TextSelection?,
        in text: String
    ) -> NSRange? {
        guard let selection else { return nil }

        let range: Range<String.Index>?
        switch selection.indices {
        case .selection(let selectedRange):
            range = selectedRange
        case .multiSelection(let selectedRanges):
            range = selectedRanges.ranges.first
        @unknown default:
            range = nil
        }

        guard let range else { return nil }
        return NSRange(range, in: text)
    }

    static func textSelection(
        from range: NSRange,
        in text: String
    ) -> TextSelection? {
        guard let stringRange = Range(range, in: text) else { return nil }
        if range.length == 0 {
            return TextSelection(insertionPoint: stringRange.lowerBound)
        }
        return TextSelection(range: stringRange)
    }

    static func characterOffset(
        forUTF16Location location: Int,
        in text: String
    ) -> Int? {
        guard location >= 0,
              location <= text.utf16.count,
              let range = Range(NSRange(location: location, length: 0), in: text) else {
            return nil
        }
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }
}

enum ChatComposerCodeFence {
    static func ranges(in text: String) -> [NSRange] {
        let source = text as NSString
        guard source.length > 0 else { return [] }

        var ranges: [NSRange] = []
        var openLocation: Int?
        var openingMarker: Character?
        var openingCount = 0

        source.enumerateSubstrings(
            in: NSRange(location: 0, length: source.length),
            options: .byLines
        ) { line, lineRange, enclosingRange, _ in
            guard let line else { return }
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            guard leadingSpaces <= 3 else { return }
            let markerText = line.dropFirst(leadingSpaces)
            guard let marker = markerText.first, marker == "`" || marker == "~" else { return }
            let count = markerText.prefix(while: { $0 == marker }).count
            guard count >= 3 else { return }

            if let start = openLocation {
                guard marker == openingMarker,
                      count >= openingCount,
                      markerText.dropFirst(count).allSatisfy(\.isWhitespace) else { return }
                ranges.append(NSRange(
                    location: start,
                    length: NSMaxRange(enclosingRange) - start
                ))
                openingMarker = nil
                openingCount = 0
                openLocation = nil
            } else {
                openLocation = lineRange.location
                openingMarker = marker
                openingCount = count
            }
        }

        if let openLocation {
            ranges.append(NSRange(location: openLocation, length: source.length - openLocation))
        }
        return ranges
    }
}
