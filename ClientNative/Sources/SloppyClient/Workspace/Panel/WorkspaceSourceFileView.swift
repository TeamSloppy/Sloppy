import SwiftUI
import SloppyClientUI

@MainActor
struct WorkspaceSourceFileView: View {
    let viewModel: WorkspaceSourceFileViewModel
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var foreground: Color { theme.colors.textPrimary }
    private var background: Color { theme.colors.background }
    private var muted: Color { theme.colors.textMuted }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                Text(viewModel.reference.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(viewModel.reference.path)
                Spacer(minLength: 0)
                if let line = viewModel.reference.line {
                    Text("Line \(line)").fixedSize()
                }
#if !os(iOS)
                Button(action: viewModel.reload) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Reload file")
                .accessibilityLabel("Reload file")
#endif
            }
            .font(.system(size: 12))
            .foregroundStyle(muted)
            .padding(12)
            Divider()

            if viewModel.isLoading {
                ProgressView("Loading file…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("workspace.source-file.loading")
            } else if let error = viewModel.errorMessage {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(error)
                        Button("Retry") { Task { await viewModel.loadIfNeeded(force: true) } }
                    }
                    .font(.system(size: 13))
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
                }
            } else if let image = viewModel.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(viewModel.title)
                    .accessibilityIdentifier("workspace.source-file.image")
            } else if viewModel.content != nil {
                sourceContent
            } else {
                ScrollView {
                    ProgressView("Loading file…")
                        .frame(maxWidth: .infinity, minHeight: 360)
                }
            }
        }
        .foregroundStyle(foreground)
        .background(background)
        .mobileRefreshable(id: viewModel.reference.path) { await viewModel.loadIfNeeded(force: true) }
        .task(id: viewModel.loadRevision) { await viewModel.loadIfNeeded() }
        .accessibilityIdentifier("workspace.source-file")
    }

    private var sourceContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.isLineOutsideFile {
                Text("Line \(viewModel.reference.line ?? 1) is beyond this file (\(viewModel.lines.count) lines). Showing the last line.")
                    .font(.system(size: 12))
                    .foregroundStyle(muted)
                    .padding(12)
            }
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(viewModel.lines.indices, id: \.self) { index in
                                HStack(alignment: .top, spacing: 16) {
                                    Text("\(index + 1)")
                                        .foregroundStyle(muted)
                                        .frame(width: gutterWidth, alignment: .trailing)
                                        .accessibilityHidden(true)
                                    Text(highlightedLine(index))
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 3)
                                .frame(minWidth: geometry.size.width, alignment: .leading)
                                .background(index + 1 == viewModel.targetLine && viewModel.reference.line != nil
                                    ? theme.colors.surfaceRaised : .clear)
                                .id(index + 1)
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("workspace.source-file.line.\(index + 1)")
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .task(id: viewModel.navigationRevision) {
                        // Runs after the loaded content has entered the view hierarchy.
                        proxy.scrollTo(viewModel.targetLine, anchor: .center)
                    }
                }
            }
        }
    }

    private func highlightedLine(_ index: Int) -> AttributedString {
        guard viewModel.syntaxLines.indices.contains(index) else {
            return AttributedString(viewModel.lines[index].isEmpty ? " " : viewModel.lines[index])
        }
        var result = AttributedString()
        for run in viewModel.syntaxLines[index] {
            var part = AttributedString(run.text)
            part.foregroundColor = syntaxColor(run.kind)
            result.append(part)
        }
        return result.characters.isEmpty ? AttributedString(" ") : result
    }

    private func syntaxColor(_ kind: String) -> Color {
        let dark = colorScheme == .dark
        switch kind {
        case "keyword", "atrule", "boolean": return dark ? Color(red: 0.94, green: 0.55, blue: 0.76) : Color(red: 0.60, green: 0.16, blue: 0.40)
        case "string", "char", "attr-value": return dark ? Color(red: 0.78, green: 0.89, blue: 0.65) : Color(red: 0.22, green: 0.40, blue: 0.16)
        case "number", "constant": return dark ? Color(red: 0.91, green: 0.72, blue: 0.48) : Color(red: 0.52, green: 0.28, blue: 0.10)
        case "function", "class-name", "builtin": return dark ? Color(red: 0.52, green: 0.79, blue: 0.92) : Color(red: 0.12, green: 0.34, blue: 0.56)
        case "comment", "prolog": return muted
        default: return foreground
        }
    }

    private var gutterWidth: CGFloat { CGFloat(max(3, String(viewModel.lines.count).count)) * 8 }
}
