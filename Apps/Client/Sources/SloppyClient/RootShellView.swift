import AdaEngine
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureOverview
import SloppyFeatureProjects
import SloppyFeatureAgents
import SloppyFeatureSettings

struct RootShellView: View {
    @State private var selectedRoute: AppRoute = .overview
    @State private var notificationManager = NotificationSocketManager()
    @State private var activeBanner: NotificationBannerItem?
    @State private var bannerDismissTask: Task<Void, Never>?
    @State private var notificationListenerStarted = false
    @Environment(\.safeAreaInsets) private var inset
    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing

        return TabView(selection: $selectedRoute) {
            Tab(AppRoute.overview.title, image: Icons.home, value: AppRoute.overview) {
                routeDestination(.overview)
            }
            Tab(AppRoute.projects.title, image: Icons.star, value: AppRoute.projects) {
                routeDestination(.projects)
            }
            Tab(AppRoute.agents.title, image: Icons.star, value: AppRoute.agents) {
                routeDestination(.agents)
            }
            Tab(AppRoute.settings.title, image: Icons.star, value: AppRoute.settings) {
                routeDestination(.settings)
            }
        }
        .background {
            c.background.ignoresSafeArea()
        }
        .tabViewPosition(idiom == .phone ? .bottom : .left)
        .overlay(anchor: .topTrailing) {
            if let banner = activeBanner {
                NotificationBanner(item: banner)
                    .frame(width: Float(320))
                    .padding(sp.m)
            }
        }
        .onAppear {
            startNotificationListener()
        }
        .overlay {
            VStack {
                HStack(spacing: 8) {
                    Text("Hello there")
                        .foregroundColor(.white)
                        .frame(width: 200, height: 200)
                        .glassEffect(.clear)

                    Text("AdaUI")
                        .foregroundColor(.white)
                        .frame(width: 200, height: 200)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                }

                HStack {
                    Color.clear
                        .frame(width: 200, height: 200)
                        .glassEffect(.regular.tint(.red), in: .rect(cornerRadius: 12))

                    Text("Hello there")
                        .foregroundColor(.white)
                        .frame(width: 200, height: 200)
                        .glassEffect(.clear.tint(.red))
                }

                Spacer()
            }
            .frame(width: 500, height: 400)
        }
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
        case .settings:
            SettingsScreen()
        }
    }

    private func placeholderView(_ route: AppRoute) -> some View {
        let c = theme.colors

        return VStack(alignment: .leading, spacing: 8) {
            Text(route.title.uppercased())
                .font(.system(size: 28))
                .foregroundColor(c.textPrimary)
            Text("COMING SOON")
                .font(.system(size: 12))
                .foregroundColor(c.textMuted)
        }
        .padding(24)
        .border(c.border, lineWidth: 1)
        .frame(height: 800)
    }

    private func startNotificationListener() {
        guard !notificationListenerStarted else { return }
        notificationListenerStarted = true
        Task { @MainActor in
            let stream = await notificationManager.connect()
            for await notification in stream {
                showBanner(for: notification)
            }
        }
    }

    private func showBanner(for notification: AppNotification) {
        let c = theme.colors
        let color: Color
        switch notification.type {
        case .agentError, .systemError:
            color = c.statusBlocked
        case .pendingApproval:
            color = c.statusWarning
        case .confirmation:
            color = c.statusDone
        }

        bannerDismissTask?.cancel()
        activeBanner = NotificationBannerItem(
            id: notification.id,
            title: notification.title,
            message: notification.message,
            accentColor: color
        )

        bannerDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled {
                activeBanner = nil
            }
        }
    }
}
