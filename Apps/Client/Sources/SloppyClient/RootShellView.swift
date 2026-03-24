import AdaEngine
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureOverview
import SloppyFeatureProjects
import SloppyFeatureAgents

struct RootShellView: View {
    @State private var selectedRoute: AppRoute = .overview

    var body: some View {
        TabContainer(
            AppRoute.allCases.map { (label: $0.title, value: $0) },
            selection: $selectedRoute
        ) { route in
            routeDestination(route)
        }
        .background(Theme.bg)
    }

    @ViewBuilder
    private func routeDestination(_ route: AppRoute) -> some View {
        switch route {
        case .overview:
            OverviewScreen()
        case .projects:
            ProjectsScreen()
        case .agents:
            AgentsScreen()
        case .tasks:
            placeholderView(route)
        case .review:
            placeholderView(route)
        }
    }

    private func placeholderView(_ route: AppRoute) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(route.title.uppercased())
                .font(.system(size: 28))
                .foregroundColor(.fromHex(0xF0F0F0))
            Text("COMING SOON")
                .font(.system(size: 12))
                .foregroundColor(.fromHex(0x4A4A4A))
        }
        .padding(24)
        .border(.fromHex(0x2A2A2A), lineWidth: 1)
    }
}
