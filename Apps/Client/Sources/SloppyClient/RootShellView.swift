import AdaEngine
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat
import SloppyFeatureSettings

enum AppState {
    case splash
    case connectionSetup
    case chat(URL)
    case settings
}

@MainActor
struct RootShellView: View {
    @State private var settings = ClientSettings()
    @State private var appState: AppState = .splash
    @State private var connectionMonitor: ConnectionMonitor = ConnectionMonitor(baseURL: URL(string: "http://localhost:25101")!)
    @State private var activeBanner: NotificationBannerItem?
    @State private var bannerDismissTask: Task<Void, Never>?
    @State private var notificationManager: NotificationSocketManager?
    @State private var notificationListenerStarted = false

    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors

        return ZStack(anchor: .topLeading) {
            c.background.ignoresSafeArea()

            switch appState {
            case .splash:
                SplashScreen(settings: settings) { result in
                    switch result {
                    case .connected(let url):
                        startConnected(url: url)
                    case .needsSetup:
                        appState = .connectionSetup
                    }
                }

            case .connectionSetup:
                ConnectionSetupView(settings: settings) { url in
                    startConnected(url: url)
                }

            case .chat(let url):
                ChatScreen(
                    apiClient: SloppyAPIClient(baseURL: url),
                    settings: settings,
                    connectionMonitor: connectionMonitor,
                    onOpenSettings: { appState = .settings }
                )

            case .settings:
                SettingsScreen(
                    settings: settings,
                    onDismiss: { appState = .chat(settings.baseURL) }
                )
            }

            // Global notification banner
            if let banner = activeBanner {
                NotificationBanner(item: banner)
                    .frame(width: Float(320))
                    .padding(theme.spacing.m)
            }
        }
    }

    private func startConnected(url: URL) {
        connectionMonitor.start(baseURL: url)
        appState = .chat(url)
        startNotificationListener(baseURL: url)
    }

    private func startNotificationListener(baseURL: URL) {
        guard !notificationListenerStarted else { return }
        notificationListenerStarted = true
        let manager = NotificationSocketManager(baseURL: baseURL)
        notificationManager = manager
        Task { @MainActor in
            let stream = await manager.connect()
            for await notification in stream {
                showBanner(for: notification)
            }
        }
    }

    private func showBanner(for notification: AppNotification) {
        let c = theme.colors
        let color: Color = switch notification.type {
        case .agentError, .systemError: c.statusBlocked
        case .pendingApproval: c.statusWarning
        case .confirmation: c.statusDone
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
