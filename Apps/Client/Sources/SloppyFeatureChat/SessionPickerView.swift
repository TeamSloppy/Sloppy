import AdaEngine
import SloppyClientCore
import SloppyClientUI

public struct SessionPickerView: View {
    public let sessions: [ChatSessionSummary]
    public let selectedSessionId: String?
    public let isLoading: Bool
    public let onSelect: (ChatSessionSummary) -> Void
    public let onNewSession: () -> Void
    public let onDismiss: () -> Void

    public init(
        sessions: [ChatSessionSummary],
        selectedSessionId: String?,
        isLoading: Bool,
        onSelect: @escaping (ChatSessionSummary) -> Void,
        onNewSession: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.sessions = sessions
        self.selectedSessionId = selectedSessionId
        self.isLoading = isLoading
        self.onSelect = onSelect
        self.onNewSession = onNewSession
        self.onDismiss = onDismiss
    }

    @Environment(\.theme) private var theme

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
                    VStack(spacing: 0) {
                        ForEach(sessions) { session in
                            let isSelected = session.id == selectedSessionId
                            Button(action: { onSelect(session) }) {
                                HStack(spacing: sp.m) {
                                    VStack(alignment: .leading, spacing: sp.xs) {
                                        Text(session.title.isEmpty ? "Chat" : session.title)
                                            .font(.system(size: ty.body))
                                            .foregroundColor(isSelected ? c.accentCyan : c.textPrimary)
                                        Text("\(session.messageCount) messages")
                                            .font(.system(size: ty.micro))
                                            .foregroundColor(c.textMuted)
                                    }
                                    Spacer()
                                    if isSelected {
                                        Text("●")
                                            .font(.system(size: ty.caption))
                                            .foregroundColor(c.accentCyan)
                                    }
                                }
                                .padding(.horizontal, sp.l)
                                .padding(.vertical, sp.m)
                                .background(isSelected ? c.accentCyan.opacity(0.05 as Float) : Color.clear)
                            }
                            .border(c.border, lineWidth: bo.thin)
                        }
                    }
                }
            }
        }
        .background(c.surface)
    }
}
