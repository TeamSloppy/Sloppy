import AdaEngine
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureOverview
import SloppyFeatureProjects
import SloppyFeatureAgents

struct RootShellView: View {
    @State private var selectedRoute: AppRoute = .overview
    @State private var notificationManager = NotificationSocketManager()
    @State private var activeBanner: NotificationBannerItem?
    @State private var bannerDismissTask: Task<Void, Never>?
    @State private var notificationListenerStarted = false

    var body: some View {
        TabContainer(
            AppRoute.allCases.map { (label: $0.title, value: $0) },
            selection: $selectedRoute
        ) { route in
            routeDestination(route)
        }
        .background(Theme.bg)
        .overlay(anchor: .topTrailing) {
            if let banner = activeBanner {
                NotificationBanner(item: banner)
                    .frame(width: Float(320))
                    .padding(Theme.spacingM)
            }
        }
        .onAppear {
            startNotificationListener()
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
        let color: Color
        switch notification.type {
        case .agentError, .systemError:
            color = Theme.statusBlocked
        case .pendingApproval:
            color = Theme.statusWarning
        case .confirmation:
            color = Theme.statusDone
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
