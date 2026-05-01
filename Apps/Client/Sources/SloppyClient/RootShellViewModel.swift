import AdaEngine
import Observation
import SloppyClientCore
import SloppyClientUI

enum AppState: Equatable {
    case splash
    case connectionSetup
    case chat(URL)
    case settings
}

@Observable
@MainActor
final class RootShellViewModel {
    var settings = ClientSettings()
    var appState: AppState = .splash
    var connectionMonitor: ConnectionMonitor
    var activeBanner: NotificationBannerItem?

    private var bannerDismissTask: Task<Void, Never>?
    private var notificationManager: NotificationSocketManager?
    private var notificationListenerStarted = false
    #if os(macOS)
    private let desktopOverlay = SloppyDesktopOverlay()
    #endif

    init() {
        connectionMonitor = ConnectionMonitor(baseURL: URL(string: "http://localhost:25101")!)
    }

    func startDeepLinkListener() {
        Task { @MainActor in
            let notifications = NotificationCenter.default.sloppyNotifications(named: .adaEngineOpenURL)
            for await notification in notifications {
                guard let url = notification.rawValue.object as? URL,
                      let deepLink = DeepLink.parse(url),
                      let serverURL = deepLink.serverURL else { continue }
                settings.useServer(deepLink.savedServer)
                startConnected(url: serverURL)
            }
        }
    }

    func startDesktopWindowIntegration() {
        #if os(macOS)
        desktopOverlay.start(settings: settings)
        #endif
    }

    func applyDesktopWindowCloseBehavior() {
        #if os(macOS)
        desktopOverlay.applyCloseBehavior(settings.windowCloseBehavior)
        #endif
    }

    func startConnected(url: URL) {
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
        let c = AppColors.dark
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
