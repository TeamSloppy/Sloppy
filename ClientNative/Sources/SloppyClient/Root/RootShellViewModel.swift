import Foundation
import Observation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

#if os(macOS)
import AppKit
#endif

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
    private var notificationListenerTask: Task<Void, Never>?
    private var notificationBaseURL: URL?
    #if os(macOS)
    private let desktopOverlay = SloppyDesktopOverlay()
    #endif

    init() {
        connectionMonitor = ConnectionMonitor(baseURL: URL(string: "http://localhost:25101")!)
    }

    func handleDeepLink(_ url: URL) {
        guard let deepLink = DeepLink.parse(url),
              let serverURL = deepLink.serverURL else { return }
        settings.useServer(deepLink.savedServer)
        startConnected(url: serverURL)
    }

    func startDesktopWindowIntegration() {
        #if os(macOS)
        desktopOverlay.start(settings: settings)
        #endif
    }

    #if os(macOS)
    func configureDesktopWindow(_ window: NSWindow) {
        desktopOverlay.attach(window: window)
    }
    #endif

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
