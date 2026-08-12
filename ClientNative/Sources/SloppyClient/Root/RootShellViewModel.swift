import Foundation
import Observation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

#if os(iOS)
import SloppyLiveActivity
#endif

#if os(macOS)
import AppKit
#endif

enum AppState: Equatable {
    case splash
    case connectionSetup
    case authentication(URL, AuthChallenge, String?)
    case chat(URL)
    case settings(ClientSettingsDestination)
}

enum MenuBarQuickAction: Sendable {
    case newChat
    case scheduledTasks
}

struct MenuBarQuickActionRequest: Equatable, Sendable {
    var id = UUID()
    var action: MenuBarQuickAction
}

struct AppDeepLinkRequest: Equatable, Sendable {
    var id = UUID()
    var deepLink: DeepLink
}

@Observable
@MainActor
final class RootShellViewModel {
    var settings = ClientSettings()
    var appState: AppState = .splash
    var connectionMonitor: ConnectionMonitor
    var activeBanner: NotificationBannerItem?
    var menuBarQuickActionRequest: MenuBarQuickActionRequest?
    var appDeepLinkRequest: AppDeepLinkRequest?

    private var bannerDismissTask: Task<Void, Never>?
    private var notificationManager: NotificationSocketManager?
    private var notificationListenerTask: Task<Void, Never>?
    private var notificationBaseURL: URL?
    #if os(macOS)
    private let desktopOverlay = SloppyDesktopOverlay()
    private var openMainWindow: (@MainActor () -> Void)?
    #endif
    #if os(iOS)
    private let liveActivityCoordinator = SloppyLiveActivityCoordinator()
    #endif

    init() {
        connectionMonitor = ConnectionMonitor(baseURL: URL(string: "http://localhost:25101")!)
        #if os(macOS)
        desktopOverlay.onOpenAgentRun = { [weak self] agentID, sessionID in
            self?.openAgentSession(agentID: agentID, sessionID: sessionID)
        }
        desktopOverlay.start(settings: settings)
        #endif
    }

    func handleDeepLink(_ url: URL) {
        guard let deepLink = DeepLink.parse(url) else { return }

        if case .connect = deepLink,
           let serverURL = deepLink.serverURL,
           let savedServer = deepLink.savedServer {
            settings.useServer(savedServer)
            connect(to: serverURL)
            return
        }

        if case .chat = appState {
            // Keep the current connected workspace.
        } else {
            connect(to: settings.baseURL)
        }
        appDeepLinkRequest = AppDeepLinkRequest(deepLink: deepLink)
    }

    func startDesktopWindowIntegration() {
        #if os(macOS)
        desktopOverlay.start(settings: settings)
        #endif
    }

    #if os(macOS)
    func configureMainWindowOpener(_ action: @escaping @MainActor () -> Void) {
        openMainWindow = action
    }

    func configureDesktopWindow(_ window: NSWindow) {
        desktopOverlay.attach(window: window)
    }

    private func openAgentSession(agentID: String, sessionID: String) {
        if case .chat = appState {
            // Keep the current connected workspace.
        } else {
            startConnected(url: settings.baseURL)
        }
        appDeepLinkRequest = AppDeepLinkRequest(
            deepLink: .session(agentId: agentID, sessionId: sessionID)
        )
        openMainWindow?()
        desktopOverlay.presentMainWindow()
    }
    #endif

    func applyDesktopWindowCloseBehavior() {
        #if os(macOS)
        desktopOverlay.applyCloseBehavior(settings.windowCloseBehavior)
        #endif
    }

    func startConnected(url: URL) {
        #if os(macOS)
        desktopOverlay.start(settings: settings, baseURL: url)
        #endif
        #if os(iOS)
        liveActivityCoordinator.start(baseURL: url)
        #endif
        connectionMonitor.start(baseURL: url)
        appState = .chat(url)
        startNotificationListener(baseURL: url)
    }

    func connect(to url: URL) {
        Task { @MainActor in
            await resolveConnection(to: url)
        }
    }

    func observeAuthenticationRequirements() async {
        let notifications = NotificationCenter.default.sloppyNotifications(
            named: AuthSessionNotifications.authenticationRequired
        )
        for await notification in notifications {
            guard !Task.isCancelled,
                  let rawURL = notification.rawValue.userInfo?[AuthSessionNotifications.baseURLUserInfoKey] as? String,
                  let baseURL = URL(string: rawURL) else {
                continue
            }
            await presentAuthentication(
                for: baseURL,
                message: "Your session has expired. Sign in again."
            )
        }
    }

    func logout() {
        let baseURL = currentBaseURL
        stopConnectedServices()
        Task { @MainActor in
            await SloppyAPIClient(baseURL: baseURL).logout()
            await presentAuthentication(for: baseURL, message: nil)
        }
    }

    func handleScenePhase(_ scenePhase: ScenePhase) {
        #if os(iOS)
        if scenePhase == .active {
            liveActivityCoordinator.applicationDidBecomeActive()
        }
        #endif
    }

    func requestMenuBarAction(_ action: MenuBarQuickAction) {
        if case .authentication = appState {
            return
        } else if case .chat = appState {
            // Keep the current connected workspace.
        } else {
            connect(to: settings.baseURL)
        }
        menuBarQuickActionRequest = MenuBarQuickActionRequest(action: action)
    }

    func consumeMenuBarAction(_ request: MenuBarQuickActionRequest) {
        guard menuBarQuickActionRequest?.id == request.id else { return }
        menuBarQuickActionRequest = nil
    }

    func consumeDeepLink(_ request: AppDeepLinkRequest) {
        guard appDeepLinkRequest?.id == request.id else { return }
        appDeepLinkRequest = nil
    }

    private func startNotificationListener(baseURL: URL) {
        guard notificationBaseURL != baseURL || notificationManager == nil else { return }

        notificationListenerTask?.cancel()
        if let notificationManager {
            Task { await notificationManager.disconnect() }
        }

        let manager = NotificationSocketManager(baseURL: baseURL)
        notificationManager = manager
        notificationBaseURL = baseURL
        notificationListenerTask = Task { @MainActor in
            let stream = await manager.connect()
            for await notification in stream {
                guard !Task.isCancelled else { return }
                showBanner(for: notification)
            }
        }
    }

    private var currentBaseURL: URL {
        switch appState {
        case .authentication(let url, _, _), .chat(let url):
            return url
        case .splash, .connectionSetup, .settings:
            return settings.baseURL
        }
    }

    private func presentAuthentication(for baseURL: URL, message: String?) async {
        if case .authentication(let currentURL, _, _) = appState,
           currentURL == baseURL {
            return
        }
        stopConnectedServices()
        let apiClient = SloppyAPIClient(baseURL: baseURL)
        guard let challenge = try? await apiClient.fetchAuthChallenge() else {
            appState = .connectionSetup
            return
        }
        if challenge.mode != "login_password",
           let status = try? await apiClient.fetchDashboardAuthStatus(),
           !status.enabled {
            appState = .splash
            return
        }
        appState = .authentication(baseURL, challenge, message)
    }

    private func resolveConnection(to baseURL: URL) async {
        let apiClient = SloppyAPIClient(baseURL: baseURL)
        guard let challenge = try? await apiClient.fetchAuthChallenge() else {
            startConnected(url: baseURL)
            return
        }

        if challenge.mode == "login_password" {
            guard await apiClient.hasStoredAuthSession() else {
                appState = .authentication(baseURL, challenge, nil)
                return
            }
            do {
                _ = try await apiClient.fetchCurrentAuthUser()
                startConnected(url: baseURL)
            } catch {
                await apiClient.logout()
                appState = .authentication(
                    baseURL,
                    challenge,
                    "Your saved session has expired. Sign in again."
                )
            }
            return
        }

        let dashboardAuthEnabled = (try? await apiClient.fetchDashboardAuthStatus().enabled) ?? false
        guard dashboardAuthEnabled else {
            startConnected(url: baseURL)
            return
        }
        if await apiClient.hasStoredAuthSession() {
            do {
                try await apiClient.validateCurrentAuthToken()
                startConnected(url: baseURL)
                return
            } catch {
                await apiClient.logout()
            }
        }
        appState = .authentication(baseURL, challenge, nil)
    }

    private func stopConnectedServices() {
        connectionMonitor.stop()
        notificationListenerTask?.cancel()
        notificationListenerTask = nil
        if let notificationManager {
            Task { await notificationManager.disconnect() }
        }
        notificationManager = nil
        notificationBaseURL = nil
    }

    private func showBanner(for notification: AppNotification) {
        let c = AppColors.dark
        let color: Color = switch notification.type {
        case .agentError, .systemError: c.statusBlocked
        case .pendingApproval, .toolApproval: c.statusWarning
        case .confirmation: c.statusDone
        }

        #if os(macOS)
        if notification.type == .toolApproval {
            desktopOverlay.updateToolApproval(notification)
        }
        #endif
        #if os(iOS)
        liveActivityCoordinator.apply(notification)
        #endif

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
