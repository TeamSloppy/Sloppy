import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

public struct AgentPickerView: View {
    public let agents: [APIAgentRecord]
    public let selectedAgent: APIAgentRecord?
    public let onSelect: (APIAgentRecord) -> Void
    public let onDismiss: () -> Void

    public init(
        agents: [APIAgentRecord],
        selectedAgent: APIAgentRecord?,
        onSelect: @escaping (APIAgentRecord) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.agents = agents
        self.selectedAgent = selectedAgent
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    @Environment(\.theme) private var theme

    public var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.s) {
            HStack {
                Text("SELECT AGENT")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
                Spacer()
                Button(action: onDismiss) {
                    HStack(spacing: sp.xs) {
                        Icons.symbol(.close, size: ty.caption)
                        Text("CLOSE")
                            .font(.system(size: ty.caption))
                    }
                    .foregroundColor(c.textSecondary)
                    .padding(.horizontal, sp.s)
                    .padding(.vertical, sp.xs)
                    .background {
                        Capsule()
                            .fill(c.surfaceRaised.opacity(0.82 as Float))
                    }
                    .glassEffect(.regular.tint(c.surfaceGlow.opacity(0.14 as Float)), in: Capsule())
                }
            }
            .padding(.horizontal, sp.l)
            .padding(.vertical, sp.m)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: sp.xs) {
                    ForEach(agents) { agent in
                        AgentPickerRow(
                            agent: agent,
                            isSelected: agent.id == selectedAgent?.id,
                            onSelect: onSelect,
                            colors: c,
                            spacing: sp,
                            typography: ty
                        )
                    }
                }
            }
            .padding(.horizontal, sp.s)
        }
        .padding(.vertical, sp.s)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(c.surfaceGlass.opacity(0.96 as Float))
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(c.border.opacity(0.82 as Float), lineWidth: theme.borders.thin)
                }
        }
        .glassEffect(.regular.tint(c.surfaceGlow.opacity(0.12 as Float)), in: RoundedRectangle(cornerRadius: 28))
    }
}

private struct AgentPickerRow: View {
    let agent: APIAgentRecord
    let isSelected: Bool
    let onSelect: (APIAgentRecord) -> Void
    let colors: AppColors
    let spacing: AppSpacing
    let typography: AppTypography

    var body: some View {
        Button(action: { onSelect(agent) }) {
            HStack(spacing: spacing.m) {
                Circle()
                    .fill(isSelected ? colors.accentAcid : colors.surfaceRaised)
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(isSelected ? 0.20 as Float : 0.08 as Float), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: spacing.xs) {
                    Text(agent.displayName)
                        .font(.system(size: typography.body))
                        .foregroundColor(isSelected ? colors.textPrimary : colors.textSecondary)
                    if !agent.role.isEmpty {
                        Text(agent.role.uppercased())
                            .font(.system(size: typography.micro))
                            .foregroundColor(colors.textMuted)
                    }
                }

                Spacer()

                if isSelected {
                    Icons.symbol(.radioButtonChecked, size: typography.caption)
                        .foregroundColor(colors.accentCyan)
                }
            }
            .padding(.horizontal, spacing.l)
            .padding(.vertical, spacing.m)
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(isSelected ? colors.accentCyan.opacity(0.12 as Float) : colors.surfaceRaised.opacity(0.52 as Float))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(
                                isSelected ? colors.accentCyan.opacity(0.42 as Float) : colors.border.opacity(0.72 as Float),
                                lineWidth: 1
                            )
                    }
            }
        }
        .glassEffect(
            .regular.tint(
                isSelected ? colors.accentCyan.opacity(0.06 as Float) : colors.surfaceGlow.opacity(0.08 as Float)
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }
}
