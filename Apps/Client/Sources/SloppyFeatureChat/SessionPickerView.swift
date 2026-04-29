import AdaEngine
import SloppyClientCore
import SloppyClientUI

public struct SessionPickerView: View {
    public let sessions: [ChatSessionSummary]
    public let selectedSessionId: String?
    public let isLoading: Bool
    public let actionStatus: String?
    public let onSelect: (ChatSessionSummary) -> Void
    public let onNewSession: () -> Void
    public let onDelete: (ChatSessionSummary) -> Void
    public let onDownloadDebug: ((ChatSessionSummary) -> Void)?
    public let onDismiss: () -> Void

    public init(
        sessions: [ChatSessionSummary],
        selectedSessionId: String?,
        isLoading: Bool,
        actionStatus: String? = nil,
        onSelect: @escaping (ChatSessionSummary) -> Void,
        onNewSession: @escaping () -> Void,
        onDelete: @escaping (ChatSessionSummary) -> Void,
        onDownloadDebug: ((ChatSessionSummary) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.sessions = sessions
        self.selectedSessionId = selectedSessionId
        self.isLoading = isLoading
        self.actionStatus = actionStatus
        self.onSelect = onSelect
        self.onNewSession = onNewSession
        self.onDelete = onDelete
        self.onDownloadDebug = onDownloadDebug
        self.onDismiss = onDismiss
    }

    @Environment(\.theme) private var theme
    @State private var pendingDeleteSession: ChatSessionSummary?
    @State private var isDeleteAlertPresented = false

    public var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SESSIONS")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
                Spacer()
                Button("NEW") { onNewSession() }
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.accentCyan)
                    .padding(.trailing, sp.m)
                Button("CLOSE") { onDismiss() }
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
            }
            .padding(.horizontal, sp.l)
            .padding(.vertical, sp.m)
            .border(c.border, lineWidth: bo.thin)

            if isLoading {
                VStack {
                    Text("Loading...")
                        .font(.system(size: ty.body))
                        .foregroundColor(c.textMuted)
                }
                .padding(sp.xl)
            } else if sessions.isEmpty {
                VStack {
                    Text("No previous sessions")
                        .font(.system(size: ty.body))
                        .foregroundColor(c.textMuted)
                }
                .padding(sp.xl)
            } else {
                ScrollView {
                    LazyVStack(
                        sessions,
                        alignment: .leading,
                        spacing: 0,
                        estimatedRowHeight: 64,
                        overscan: 14
                    ) { session in
                            let isSelected = session.id == selectedSessionId
                            SessionPickerRow(
                                session: session,
                                isSelected: isSelected,
                                colors: c,
                                spacing: sp,
                                borders: bo,
                                typography: ty,
                                onSelect: onSelect,
                                onDeleteRequest: { session in
                                    pendingDeleteSession = session
                                    isDeleteAlertPresented = true
                                },
                                onDownloadDebug: onDownloadDebug
                            )
                    }
                }
            }

            if let actionStatus {
                Text(actionStatus)
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
                    .lineLimit(2)
                    .padding(.horizontal, sp.l)
                    .padding(.vertical, sp.m)
            }
        }
        .background(c.surface)
        .alert(
            "Delete chat?",
            isPresented: $isDeleteAlertPresented,
            presenting: pendingDeleteSession
        ) { session in
            Button("Cancel", role: .cancel) {
                pendingDeleteSession = nil
            }
            Button("Delete", role: .destructive) {
                pendingDeleteSession = nil
                onDelete(session)
            }
        } message: { session in
            Text("This permanently deletes \(session.title.isEmpty ? "this chat" : session.title).")
        }
    }
}

private struct SessionPickerRow: View {
    let session: ChatSessionSummary
    let isSelected: Bool
    let colors: AppColors
    let spacing: AppSpacing
    let borders: AppBorders
    let typography: AppTypography
    let onSelect: (ChatSessionSummary) -> Void
    let onDeleteRequest: (ChatSessionSummary) -> Void
    let onDownloadDebug: ((ChatSessionSummary) -> Void)?

    @State private var isHovered = false

    var body: some View {
        let background = if isSelected {
            colors.accentCyan.opacity(0.14 as Float)
        } else if isHovered {
            colors.surfaceRaised.opacity(0.72 as Float)
        } else {
            Color.clear
        }

        return Button(action: { onSelect(session) }) {
            HStack(spacing: spacing.m) {
                Color.clear
                    .frame(width: borders.thick)
                    .background(isSelected ? colors.accentCyan : Color.clear)

                VStack(alignment: .leading, spacing: spacing.xs) {
                    Text(session.title.isEmpty ? "Chat" : session.title)
                        .font(.system(size: typography.body))
                        .foregroundColor(isSelected ? colors.accentCyan : colors.textPrimary)
                    Text("\(session.messageCount) messages")
                        .font(.system(size: typography.micro))
                        .foregroundColor(colors.textMuted)
                }

                Spacer()

                if isSelected {
                    Icons.symbol(.radioButtonChecked, size: typography.caption)
                        .foregroundColor(colors.accentCyan)
                }
            }
            .padding(.trailing, spacing.l)
            .padding(.vertical, spacing.m)
            .background(background)
        }
        .border(isSelected ? colors.accentCyan.opacity(0.62 as Float) : colors.border, lineWidth: borders.thin)
        .contextMenu {
            #if DEBUG
            if let onDownloadDebug {
                Button("Download Session") {
                    onDownloadDebug(session)
                }
            }
            #endif

            Button("Delete Chat", role: .destructive) {
                onDeleteRequest(session)
            }
        }
        .onHover { isHovered = $0 }
    }
}
