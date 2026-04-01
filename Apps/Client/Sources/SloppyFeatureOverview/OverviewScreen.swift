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
        _HeroSection()
    }

    private var statsGrid: some View {
        _StatsGrid()
    }

    private var projectsSection: some View {
        _ProjectsSection()
    }

    private var agentsSection: some View {
        _AgentsSection()
    }
}

private struct _HeroSection: View {
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.s) {
            Text("SLOPPY")
                .font(.system(size: ty.hero))
                .foregroundColor(c.textPrimary)

            Color.clear
                .frame(width: 60, height: bo.thick)
                .background(c.accent)

            Text("SYSTEM OVERVIEW")
                .font(.system(size: ty.caption))
                .foregroundColor(c.textMuted)
        }
        .padding(sp.l)
    }
}

private struct _StatsGrid: View {
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing

        return HStack(spacing: 0) {
            BrutalistStatCard(value: "0", label: "Projects", accentColor: c.accent)
            BrutalistStatCard(value: "0", label: "Agents", accentColor: c.accentCyan)
            BrutalistStatCard(value: "0", label: "Active", accentColor: c.accentAcid)
            BrutalistStatCard(value: "0", label: "Done", accentColor: c.statusDone)
        }
        .padding(.horizontal, sp.l)
    }
}

private struct _ProjectsSection: View {
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.m) {
            HStack {
                SectionHeader("Projects", accentColor: c.accent)
                Button("VIEW ALL") {}
                    .foregroundColor(c.textMuted)
                    .font(.system(size: ty.caption))
            }
            .padding(.horizontal, sp.l)

            EmptyStateView("No projects found")
                .padding(.horizontal, sp.l)
        }
        .padding(.top, sp.xl)
    }
}

private struct _AgentsSection: View {
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.m) {
            HStack {
                SectionHeader("Agents", accentColor: c.accentCyan)
                Button("VIEW ALL") {}
                    .foregroundColor(c.textMuted)
                    .font(.system(size: ty.caption))
            }
            .padding(.horizontal, sp.l)

            EmptyStateView("No agents registered")
                .padding(.horizontal, sp.l)
        }
        .padding(.top, sp.xl)
        .padding(.bottom, sp.xl)
    }
}

private struct BrutalistStatCard: View {
    let value: String
    let label: String
    let accentColor: Color

    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: bo.thick)
                .background(accentColor)

            VStack(alignment: .leading, spacing: sp.xs) {
                Text(value)
                    .font(.system(size: 36))
                    .foregroundColor(c.textPrimary)
                Text(label.uppercased())
                    .font(.system(size: ty.micro))
                    .foregroundColor(c.textSecondary)
            }
            .padding(sp.m)
        }
        .background(c.surface)
        .border(c.border, lineWidth: bo.thin)
    }
}
