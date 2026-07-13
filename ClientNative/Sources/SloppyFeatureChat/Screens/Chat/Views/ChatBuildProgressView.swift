import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct ChatBuildProgressView: View {
    let progress: ChatBuildProgress

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 0) {
                progressCard
                    .overlay(alignment: .bottom) {
                        stepBadge
                            .offset(y: 23)
                    }
                    .padding(.bottom, 23)
            }
            .frame(maxWidth: 640)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(progress.title)
    }

    private var progressCard: some View {
        let c = theme.colors
        let sp = theme.spacing

        return VStack(alignment: .leading, spacing: sp.m) {
            if !progress.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(progress.title)
                    .font(.system(size: theme.typography.caption, weight: .semibold))
                    .foregroundStyle(c.textMuted)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .padding(.bottom, sp.xs)
            }

            ForEach(progress.items) { item in
                progressRow(item)
            }
        }
        .padding(.horizontal, sp.m)
        .padding(.top, sp.m)
        .padding(.bottom, sp.l)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(c.surfaceRaised.opacity(0.96))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(c.borderBold.opacity(0.75), lineWidth: theme.borders.thin)
                }
        }
        .shadow(color: Color.black.opacity(0.22), radius: 18, y: 10)
    }

    private func progressRow(_ item: ChatBuildProgressItem) -> some View {
        HStack(alignment: .top, spacing: theme.spacing.s) {
            statusMarker(for: item.status)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text(item.title)
                    .font(.system(size: theme.typography.body, weight: item.status == .inProgress ? .semibold : .regular))
                    .foregroundStyle(titleColor(for: item.status))
                    .strikethrough(item.status == .done || item.status == .skipped)
                    .fixedSize(horizontal: false, vertical: true)

                if item.status == .blocked,
                   let details = item.details?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !details.isEmpty {
                    Text(details)
                        .font(.system(size: theme.typography.caption))
                        .foregroundStyle(theme.colors.statusBlocked)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        .accessibilityValue(statusLabel(for: item.status))
        .accessibilityHint(item.definitionOfDone)
    }

    @ViewBuilder
    private func statusMarker(for status: ChatBuildProgressStatus) -> some View {
        switch status {
        case .pending:
            Circle()
                .stroke(theme.colors.textSecondary, lineWidth: 1.5)
                .padding(2)
        case .inProgress:
            ZStack {
                Circle()
                    .stroke(theme.colors.statusActive.opacity(0.4), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(
                        theme.colors.statusActive,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .padding(2)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(theme.colors.statusDone)
        case .blocked:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(theme.colors.statusBlocked)
        case .skipped:
            Image(systemName: "minus.circle")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(theme.colors.textMuted)
        }
    }

    private var stepBadge: some View {
        let c = theme.colors

        return HStack(spacing: theme.spacing.s) {
            Circle()
                .stroke(stepAccentColor, lineWidth: 3)
                .frame(width: 18, height: 18)

            Text("Step \(progress.currentStepNumber) / \(progress.items.count)")
                .font(.system(size: theme.typography.body, weight: .medium))
                .foregroundStyle(c.textSecondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, theme.spacing.m)
        .frame(height: 46)
        .background {
            Capsule()
                .fill(c.surfaceRaised)
                .overlay {
                    Capsule()
                        .stroke(c.borderBold.opacity(0.8), lineWidth: theme.borders.thin)
                }
        }
        .shadow(color: Color.black.opacity(0.16), radius: 9, y: 5)
        .accessibilityElement(children: .combine)
    }

    private var stepAccentColor: Color {
        if progress.items.allSatisfy({ $0.status == .done || $0.status == .skipped }) {
            return theme.colors.statusDone
        }
        if progress.items.contains(where: { $0.status == .blocked }) {
            return theme.colors.statusBlocked
        }
        return theme.colors.statusActive
    }

    private func titleColor(for status: ChatBuildProgressStatus) -> Color {
        switch status {
        case .inProgress:
            theme.colors.textPrimary
        case .blocked:
            theme.colors.statusBlocked
        case .pending:
            theme.colors.textSecondary
        case .done, .skipped:
            theme.colors.textMuted
        }
    }

    private func statusLabel(for status: ChatBuildProgressStatus) -> String {
        switch status {
        case .pending: "Pending"
        case .inProgress: "In progress"
        case .done: "Done"
        case .blocked: "Blocked"
        case .skipped: "Skipped"
        }
    }
}

#Preview("Build progress") {
    ChatBuildProgressView(
        progress: ChatBuildProgress(
            title: "Implementation plan",
            items: [
                ChatBuildProgressItem(
                    id: "inspect",
                    title: "Inspect the existing event and chat rendering pipeline",
                    status: .done,
                    definitionOfDone: "The data path is understood."
                ),
                ChatBuildProgressItem(
                    id: "model",
                    title: "Decode structured progress events in the client",
                    status: .inProgress,
                    definitionOfDone: "History and live updates decode."
                ),
                ChatBuildProgressItem(
                    id: "view",
                    title: "Render the current checklist in the transcript",
                    status: .pending,
                    definitionOfDone: "The checklist is visible."
                ),
                ChatBuildProgressItem(
                    id: "verify",
                    title: "Run focused tests and build the package",
                    status: .pending,
                    definitionOfDone: "All relevant checks pass."
                ),
            ]
        )
    )
    .padding(32)
    .background(AppColors.dark.background)
}
