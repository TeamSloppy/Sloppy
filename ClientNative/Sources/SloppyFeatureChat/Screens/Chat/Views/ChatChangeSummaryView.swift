import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct ChatChangeSummaryView: View {
    let sourceControl: ProjectWorkingTreeSourceControlResponse

    @State private var isExpanded = true
    @Environment(\.theme) private var theme

    private var fileChanges: [ProjectSourceControlFileChange] {
        sourceControl.fileChanges
    }

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: sp.m) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: theme.typography.heading, weight: .medium))
                    .foregroundColor(c.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(c.surfaceGlass, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: sp.xs) {
                    Text(title)
                        .font(.system(size: theme.typography.body, weight: .semibold))
                        .foregroundColor(c.textPrimary)

                    changeCounts(added: sourceControl.linesAdded, deleted: sourceControl.linesDeleted)
                }

                Spacer(minLength: sp.s)

                if !fileChanges.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: sp.xs) {
                            Text("Review")
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: theme.typography.micro, weight: .semibold))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(isExpanded ? "Hide changed files" : "Review changed files")
                }
            }
            .padding(sp.m)

            if isExpanded, !fileChanges.isEmpty {
                Divider()
                    .overlay(c.border)

                VStack(alignment: .leading, spacing: sp.m) {
                    ForEach(fileChanges) { change in
                        fileRow(change)
                    }
                }
                .padding(sp.m)
            }
        }
        .background(c.surfaceRaised.opacity(0.72 as CGFloat))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(c.borderBold.opacity(0.8 as CGFloat), lineWidth: theme.borders.thin)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.change-summary")
    }

    private var title: String {
        guard !fileChanges.isEmpty else { return "Edited files" }
        return "Edited \(fileChanges.count) \(fileChanges.count == 1 ? "file" : "files")"
    }

    private func fileRow(_ change: ProjectSourceControlFileChange) -> some View {
        HStack(spacing: theme.spacing.s) {
            Text(change.path)
                .font(.system(size: theme.typography.caption, design: .monospaced))
                .foregroundColor(theme.colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: theme.spacing.s)

            changeCounts(added: change.linesAdded, deleted: change.linesDeleted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(change.path), \(change.linesAdded) additions, \(change.linesDeleted) deletions")
    }

    private func changeCounts(added: Int, deleted: Int) -> some View {
        HStack(spacing: theme.spacing.xs) {
            Text("+\(added)")
                .foregroundColor(theme.colors.statusDone)
            Text("-\(deleted)")
                .foregroundColor(theme.colors.statusBlocked)
        }
        .font(.system(size: theme.typography.caption, weight: .medium, design: .monospaced))
        .fixedSize()
    }
}

struct ChatComposerChangeSummaryView: View {
    let sourceControl: ProjectWorkingTreeSourceControlResponse

    @Environment(\.theme) private var theme

    var body: some View {
        let title = Self.title(fileCount: sourceControl.fileChanges.count)

        return HStack(spacing: theme.spacing.xs) {
            Text(title)
                .foregroundColor(theme.colors.textSecondary)

            Text("+\(sourceControl.linesAdded)")
                .foregroundColor(theme.colors.statusDone)

            Text("-\(sourceControl.linesDeleted)")
                .foregroundColor(theme.colors.statusBlocked)
        }
        .font(.system(size: theme.typography.body, weight: .medium))
        .padding(.horizontal, theme.spacing.m)
        .padding(.vertical, theme.spacing.s)
        .background(theme.colors.surfaceRaised.opacity(0.82 as CGFloat))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(
                    theme.colors.borderBold.opacity(0.8 as CGFloat),
                    lineWidth: theme.borders.thin
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(title), "
                + "\(sourceControl.linesAdded) additions, "
                + "\(sourceControl.linesDeleted) deletions"
        )
        .accessibilityIdentifier("chat.composer.change-summary")
    }

    static func title(fileCount: Int) -> String {
        guard fileCount > 0 else { return "Files changed" }
        return "\(fileCount) \(fileCount == 1 ? "file" : "files") changed"
    }
}

#Preview {
    ChatChangeSummaryView(
        sourceControl: ProjectWorkingTreeSourceControlResponse(
            providerId: "git",
            isRepository: true,
            branch: "main",
            linesAdded: 92,
            linesDeleted: 29,
            diff: """
            diff --git a/Sources/DebugPresetStore.swift b/Sources/DebugPresetStore.swift
            --- a/Sources/DebugPresetStore.swift
            +++ b/Sources/DebugPresetStore.swift
            @@ -1 +1,2 @@
            -let old = true
            +let new = true
            +let value = 42
            diff --git a/Tests/DebugPresetTests.swift b/Tests/DebugPresetTests.swift
            --- a/Tests/DebugPresetTests.swift
            +++ b/Tests/DebugPresetTests.swift
            @@ -0,0 +1 @@
            +#expect(true)
            """
        )
    )
    .padding()
    .frame(width: 760)
}
