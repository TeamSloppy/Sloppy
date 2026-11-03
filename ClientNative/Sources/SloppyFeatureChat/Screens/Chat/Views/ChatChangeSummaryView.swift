import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct ChatChangeSummaryView: View {
    let sourceControl: ProjectWorkingTreeSourceControlResponse

    @Environment(\.theme) private var theme
    @Environment(\.workingTreeReviewHandler) private var reviewHandler

    var body: some View {
        if sourceControl.hasChanges {
            Button {
                reviewHandler?(sourceControl, nil, nil)
            } label: {
                HStack(spacing: theme.spacing.m) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: theme.typography.heading, weight: .medium))
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(theme.colors.surfaceGlass, in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: theme.spacing.xs) {
                        Text(title)
                            .font(.system(size: theme.typography.body, weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                        HStack(spacing: theme.spacing.xs) {
                            if sourceControl.linesAdded > 0 {
                                Text("+\(sourceControl.linesAdded)")
                                    .foregroundStyle(theme.colors.statusDone)
                            }
                            if sourceControl.linesDeleted > 0 {
                                Text("-\(sourceControl.linesDeleted)")
                                    .foregroundStyle(theme.colors.statusBlocked)
                            }
                        }
                        .font(.system(size: theme.typography.caption, weight: .medium, design: .monospaced))
                    }
                    Spacer(minLength: theme.spacing.s)
                    Text("Review")
                        .font(.callout)
                        .foregroundStyle(theme.colors.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(theme.colors.textMuted)
                }
                .padding(theme.spacing.m)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(reviewHandler == nil)
            .background(theme.colors.surfaceRaised.opacity(0.72 as CGFloat))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(theme.colors.borderBold.opacity(0.8 as CGFloat), lineWidth: theme.borders.thin)
                    .allowsHitTesting(false)
            }
            .accessibilityLabel("\(title), review changes")
            .accessibilityIdentifier("chat.change-summary")
        }
    }

    private var title: String {
        let count = sourceControl.fileChanges.count
        guard count > 0 else { return "Edited files" }
        return "Edited \(count) \(count == 1 ? "file" : "files")"
    }
}

struct ChatComposerChangeSummaryView: View {
    let sourceControl: ProjectWorkingTreeSourceControlResponse

    @Environment(\.theme) private var theme

    var body: some View {
        let title = Self.title(fileCount: sourceControl.fileChanges.count)

        return Group {
            if sourceControl.hasChanges {
                summary(title: title)
            }
        }
    }

    private func summary(title: String) -> some View {
        HStack(spacing: theme.spacing.xs) {
            Text(title)
                .foregroundColor(theme.colors.textSecondary)

            if sourceControl.linesAdded > 0 {
                Text("+\(sourceControl.linesAdded)")
                    .foregroundColor(theme.colors.statusDone)
            }
            if sourceControl.linesDeleted > 0 {
                Text("-\(sourceControl.linesDeleted)")
                    .foregroundColor(theme.colors.statusBlocked)
            }
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
