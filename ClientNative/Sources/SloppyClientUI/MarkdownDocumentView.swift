import SwiftUI
import Textual

/// Shared full Markdown renderer for locally authored documents.
public struct MarkdownDocumentView: View {
    private let source: String
    @Environment(\.theme) private var theme

    public init(source: String) { self.source = source }

    public var body: some View {
        StructuredText(markdown: source)
            .textual.structuredTextStyle(.gitHub)
            .textual.textSelection(.enabled)
            .font(.body)
            .foregroundStyle(theme.colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
