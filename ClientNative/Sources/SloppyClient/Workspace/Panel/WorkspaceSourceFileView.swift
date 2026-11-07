import SwiftUI
import SloppyClientUI

@MainActor
struct WorkspaceSourceFileView: View {
    let viewModel: WorkspaceSourceFileViewModel
    @Environment(\.theme) private var theme

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

            if let error = viewModel.errorMessage {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(error)
                        Button("Retry") { Task { await viewModel.loadIfNeeded(force: true) } }
                    }
                    .font(.system(size: 13))
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
                }
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
        .task(id: viewModel.navigationRevision) { await viewModel.loadIfNeeded() }
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
                                    Text(verbatim: viewModel.lines[index].isEmpty ? " " : viewModel.lines[index])
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

    private var gutterWidth: CGFloat { CGFloat(max(3, String(viewModel.lines.count).count)) * 8 }
}
