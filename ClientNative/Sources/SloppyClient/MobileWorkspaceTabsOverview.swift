import SwiftUI
import SloppyClientUI

@MainActor
struct MobileWorkspaceTabsOverview: View {
    let tabs: [WorkspaceTab]
    let selectedTabID: WorkspaceTab.ID?
    let onSelect: @MainActor (WorkspaceTab.ID) -> Void
    let onClose: @MainActor (WorkspaceTab.ID) -> Void
    let onCreate: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void

    @Environment(\.theme) private var theme

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ZStack {
            theme.colors.surface.opacity(0.88 as CGFloat)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: theme.spacing.l) {
                HStack {
                    Text("Tabs")
                        .font(.system(size: theme.typography.heading))
                        .foregroundColor(theme.colors.textPrimary)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .foregroundColor(theme.colors.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(theme.colors.surfaceRaised))
                    }
                    .buttonStyle(.plain)
                }

                ScrollView {
                    LazyVGrid(columns: columns, spacing: theme.spacing.m) {
                        ForEach(tabs) { tab in
                            Button(action: { onSelect(tab.id) }) {
                                VStack(alignment: .leading, spacing: theme.spacing.s) {
                                    HStack(alignment: .top) {
                                        Text(tab.title)
                                            .font(.system(size: theme.typography.body))
                                            .foregroundColor(theme.colors.textPrimary)
                                            .lineLimit(2)
                                        Spacer(minLength: theme.spacing.s)
                                        Button(action: { onClose(tab.id) }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(theme.colors.textMuted)
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    Spacer(minLength: 0)

                                    Text(tab.kind.rawValue)
                                        .font(.system(size: theme.typography.caption))
                                        .foregroundColor(theme.colors.textSecondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                                .padding(theme.spacing.m)
                                .background(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .fill(
                                            selectedTabID == tab.id
                                                ? theme.colors.surfaceRaised
                                                : theme.colors.surface
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, theme.spacing.xs)
                }

                Button(action: onCreate) {
                    HStack(spacing: theme.spacing.xs) {
                        Image(systemName: "plus")
                        Text("New Tab")
                    }
                    .font(.system(size: theme.typography.body, weight: .semibold))
                    .foregroundColor(theme.colors.textPrimary)
                    .padding(.horizontal, theme.spacing.l)
                    .padding(.vertical, theme.spacing.m)
                    .background(Capsule().fill(theme.colors.surfaceRaised))
                }
                .buttonStyle(.plain)
            }
            .padding(theme.spacing.l)
        }
    }
}
