import SwiftUI
import SloppyClientUI

struct BrowserNotePreviewPart: Identifiable {
    var id: Int
    var markdown: String?
    var checkbox: BrowserNoteChecklist?

    static func parts(in markdown: String) -> [Self] {
        let checks = Dictionary(uniqueKeysWithValues: BrowserNoteChecklist.items(in: markdown).map { ($0.line, $0) })
        var parts: [Self] = []
        var buffer: [String] = []
        var start = 0
        func flush() {
            let source = buffer.joined(separator: "\n")
            if !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(.init(id: start, markdown: source))
            }
            buffer = []
        }
        for (index, line) in markdown.components(separatedBy: "\n").enumerated() {
            if let check = checks[index] {
                flush()
                parts.append(.init(id: index, checkbox: check))
                start = index + 1
            } else {
                if buffer.isEmpty { start = index }
                buffer.append(line)
            }
        }
        flush()
        return parts
    }
}

@MainActor
struct BrowserNotePreview: View {
    let markdown: String
    let onToggle: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(BrowserNotePreviewPart.parts(in: markdown)) { part in
                if let source = part.markdown {
                    MarkdownDocumentView(source: source)
                } else if let item = part.checkbox {
                    Button { onToggle(item.line) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                            Text((try? AttributedString(markdown: item.title)) ?? AttributedString(item.title))
                                .strikethrough(item.isComplete)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 4).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.isComplete ? "Reopen" : "Complete"): \(item.title)")
                    .accessibilityIdentifier("browser-note-check-\(item.line)")
                }
            }
        }
    }
}
