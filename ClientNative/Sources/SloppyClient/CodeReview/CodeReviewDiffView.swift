import SloppyClientCore
import SwiftUI

private struct CodeReviewDiffRenderDocument: Sendable {
    struct Item: Identifiable, Sendable {
        enum Content: Sendable {
            case spacing
            case fileHeader(path: String, additions: Int, deletions: Int)
            case hunkHeader(String)
            case code(CodeReviewDiffRow)
        }

        let id: Int
        let filePath: String
        let content: Content
    }

    let items: [Item]
    let codeRowCount: Int

    init(diff: String, fallbackPath: String) {
        let files = CodeReviewDiffParser.parse(diff, fallbackPath: fallbackPath)
        var items: [Item] = []
        var nextID = 0
        var codeRowCount = 0

        for (fileIndex, file) in files.enumerated() {
            if fileIndex > 0 {
                items.append(Item(id: nextID, filePath: file.displayPath, content: .spacing))
                nextID += 1
            }
            items.append(
                Item(
                    id: nextID,
                    filePath: file.displayPath,
                    content: .fileHeader(
                        path: file.displayPath,
                        additions: file.additions,
                        deletions: file.deletions
                    )
                )
            )
            nextID += 1

            for hunk in file.hunks {
                items.append(Item(id: nextID, filePath: file.displayPath, content: .hunkHeader(hunk.header)))
                nextID += 1
                for row in hunk.rows {
                    items.append(Item(id: nextID, filePath: file.displayPath, content: .code(row)))
                    nextID += 1
                    codeRowCount += 1
                }
            }
        }

        self.items = items
        self.codeRowCount = codeRowCount
    }
}

struct CodeReviewSideBySideDiffView: View {
    let diff: String
    var fallbackPath = "Changes"
    var highlightedPath: String?
    var highlightedLine: Int?
    var maximumHeight: CGFloat?

    @State private var document: CodeReviewDiffRenderDocument?

    private let codeColumnWidth: CGFloat = 620
    private let lineHeight: CGFloat = 22

    var body: some View {
        Group {
            if let document {
                if document.items.isEmpty {
                    ContentUnavailableView("No Code Changes", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    diffContent(document)
                }
            } else {
                CodeReviewDiffSkeletonView(totalWidth: totalWidth, isCompact: maximumHeight != nil)
            }
        }
        .frame(
            minHeight: maximumHeight == nil ? nil : 90,
            idealHeight: resolvedHeight,
            maxHeight: resolvedHeight
        )
        .task { await prepareDiff() }
        .accessibilityIdentifier(document == nil ? "code-review-diff-skeleton" : "code-review-diff")
    }

    private func diffContent(_ document: CodeReviewDiffRenderDocument) -> some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(document.items) { item in
                    render(item)
                }
            }
            .padding(16)
        }
        .background(.background)
    }

    @ViewBuilder
    private func render(_ item: CodeReviewDiffRenderDocument.Item) -> some View {
        switch item.content {
        case .spacing:
            Color.clear
                .frame(width: totalWidth, height: 18)
        case .fileHeader(let path, let additions, let deletions):
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(path)
                    .font(.callout.monospaced().weight(.semibold))
                    .lineLimit(1)
                Text("+\(additions)")
                    .foregroundStyle(.green)
                Text("−\(deletions)")
                    .foregroundStyle(.red)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .frame(width: totalWidth, height: 38)
            .background(.quaternary.opacity(0.5))
            .overlay {
                Rectangle().stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            }
        case .hunkHeader(let header):
            HStack(spacing: 0) {
                Text(header)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                Spacer(minLength: 0)
            }
            .frame(width: totalWidth, height: 26)
            .background(Color.accentColor.opacity(0.08))
        case .code(let row):
            HStack(spacing: 0) {
                diffCell(row.old, isOldSide: true, filePath: item.filePath)
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1, height: lineHeight)
                diffCell(row.new, isOldSide: false, filePath: item.filePath)
            }
        }
    }

    private func diffCell(_ cell: CodeReviewDiffCell, isOldSide: Bool, filePath: String) -> some View {
        HStack(spacing: 0) {
            Text(cell.lineNumber.map(String.init) ?? "")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 46, alignment: .trailing)
                .padding(.trailing, 8)

            Text(cellPrefix(cell.kind))
                .font(.caption.monospaced())
                .foregroundStyle(prefixColor(cell.kind))
                .frame(width: 16, alignment: .center)

            Text(verbatim: cell.text)
                .font(.caption.monospaced())
                .foregroundStyle(cell.kind == .empty ? .tertiary : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.trailing, 8)
        .frame(width: codeColumnWidth, height: lineHeight)
        .background(cellBackground(cell, isOldSide: isOldSide, filePath: filePath))
    }

    private func cellPrefix(_ kind: CodeReviewDiffLineKind) -> String {
        switch kind {
        case .deletion: "−"
        case .insertion: "+"
        case .context, .empty: ""
        }
    }

    private func prefixColor(_ kind: CodeReviewDiffLineKind) -> Color {
        switch kind {
        case .deletion: .red
        case .insertion: .green
        case .context, .empty: .secondary
        }
    }

    private func cellBackground(_ cell: CodeReviewDiffCell, isOldSide: Bool, filePath: String) -> Color {
        if isHighlighted(filePath), cell.lineNumber == highlightedLine {
            return Color.accentColor.opacity(0.24)
        }
        switch cell.kind {
        case .deletion:
            return Color.red.opacity(0.16)
        case .insertion:
            return Color.green.opacity(0.16)
        case .empty:
            return Color.secondary.opacity(0.04)
        case .context:
            return isOldSide ? Color.secondary.opacity(0.015) : .clear
        }
    }

    private var totalWidth: CGFloat {
        codeColumnWidth * 2 + 1
    }

    private var resolvedHeight: CGFloat? {
        guard let maximumHeight else { return nil }
        guard let document else { return min(180, maximumHeight) }
        let structuralRows = document.items.count - document.codeRowCount
        let contentHeight = CGFloat(document.codeRowCount) * lineHeight
            + CGFloat(structuralRows) * 30
            + 32
        return min(maximumHeight, max(90, contentHeight))
    }

    private func isHighlighted(_ filePath: String) -> Bool {
        guard let highlightedPath else { return true }
        return normalizedPath(filePath) == normalizedPath(highlightedPath)
    }

    private func normalizedPath(_ value: String) -> String {
        value
            .replacingOccurrences(of: "a/", with: "", options: [.anchored])
            .replacingOccurrences(of: "b/", with: "", options: [.anchored])
    }

    private func prepareDiff() async {
        let source = diff
        let path = fallbackPath
        let worker = Task.detached(priority: .userInitiated) {
            CodeReviewDiffRenderDocument(diff: source, fallbackPath: path)
        }
        let prepared = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard !Task.isCancelled else { return }
        document = prepared
    }
}

private struct CodeReviewDiffSkeletonView: View {
    let totalWidth: CGFloat
    let isCompact: Bool

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                skeletonBar(width: totalWidth, height: 38, opacity: 0.16)
                skeletonBar(width: totalWidth, height: 26, opacity: 0.1)
                ForEach(0..<(isCompact ? 5 : 18), id: \.self) { index in
                    HStack(spacing: 1) {
                        skeletonLine(seed: index)
                        skeletonLine(seed: index + 3)
                    }
                }
            }
            .padding(16)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preparing code diff")
    }

    private func skeletonLine(seed: Int) -> some View {
        HStack(spacing: 10) {
            skeletonBar(width: 38, height: 8, opacity: 0.12)
            skeletonBar(width: CGFloat(180 + (seed % 5) * 58), height: 9, opacity: 0.15)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(width: (totalWidth - 1) / 2, height: 22)
        .background(Color.secondary.opacity(seed.isMultiple(of: 4) ? 0.035 : 0.015))
    }

    private func skeletonBar(width: CGFloat, height: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: min(5, height / 2), style: .continuous)
            .fill(Color.secondary.opacity(opacity))
            .frame(width: width, height: height)
    }
}

struct CodeReviewInlineDiffView: View {
    let diff: String
    let filePath: String
    let highlightedLine: Int?

    var body: some View {
        CodeReviewSideBySideDiffView(
            diff: diff,
            fallbackPath: filePath,
            highlightedPath: filePath,
            highlightedLine: highlightedLine,
            maximumHeight: 280
        )
    }
}
