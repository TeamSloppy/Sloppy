import AdaEngine
import SloppyClientCore
import SloppyClientUI

public struct OverviewScreen: View {

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                statsGrid
                projectsSection
                agentsSection
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            Text("SLOPPY")
                .font(.system(size: Theme.fontHero))
                .foregroundColor(Theme.textPrimary)

            Color.clear
                .frame(width: 60, height: Theme.borderThick)
                .background(Theme.accent)

            Text("SYSTEM OVERVIEW")
                .font(.system(size: Theme.fontCaption))
                .foregroundColor(Theme.textMuted)
        }
        .padding(Theme.spacingL)
    }

    private var statsGrid: some View {
        HStack(spacing: 0) {
            BrutalistStatCard(
                value: "0",
                label: "Projects",
                accentColor: Theme.accent
            )
            BrutalistStatCard(
                value: "0",
                label: "Agents",
                accentColor: Theme.accentCyan
            )
            BrutalistStatCard(
                value: "0",
                label: "Active",
                accentColor: Theme.accentAcid
            )
            BrutalistStatCard(
                value: "0",
                label: "Done",
                accentColor: Theme.statusDone
            )
        }
        .padding(.horizontal, Theme.spacingL)
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            HStack {
                SectionHeader("Projects", accentColor: Theme.accent)
                Button("VIEW ALL") {}
                    .foregroundColor(Theme.textMuted)
            }
            .padding(.horizontal, Theme.spacingL)

            EmptyStateView("No projects found")
                .padding(.horizontal, Theme.spacingL)
        }
        .padding(.top, Theme.spacingXL)
    }

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            HStack {
                SectionHeader("Agents", accentColor: Theme.accentCyan)
                Button("VIEW ALL") {}
                    .foregroundColor(Theme.textMuted)
            }
            .padding(.horizontal, Theme.spacingL)

            EmptyStateView("No agents registered")
                .padding(.horizontal, Theme.spacingL)
        }
        .padding(.top, Theme.spacingXL)
        .padding(.bottom, Theme.spacingXL)
    }
}

private struct BrutalistStatCard: View {
    let value: String
    let label: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: Theme.borderThick)
                .background(accentColor)

            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                Text(value)
                    .font(.system(size: 36))
                    .foregroundColor(Theme.textPrimary)
                Text(label.uppercased())
                    .font(.system(size: Theme.fontMicro))
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(Theme.spacingM)
        }
        .background(Theme.surface)
        .border(Theme.border, lineWidth: Theme.borderThin)
    }
}
