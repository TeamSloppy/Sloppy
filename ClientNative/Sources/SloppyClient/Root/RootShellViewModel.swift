import Foundation
import Logging
import Observation
import SwiftUI
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat
import SloppyRemoteProtocol

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
    case pairing(URL)
    case chat(URL)
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

struct ProactivePresentation: Identifiable {
    let agentID: String
    let findingID: String?
    var id: String { agentID + ":" + (findingID ?? "") }
}

@Observable
@MainActor
final class RootShellViewModel {
    var settings = ClientSettings()
    let launchPreferences: ClientLaunchPreferences
    var showsStandaloneBrowser: Bool
    var connectionSetupRequested = false
    var lastConnectionError: String?
    var appState: AppState = .splash
    var autoConnectCloud = true
    var consoleConnectionCode: ConsoleConnectionCode?
    var connectionMonitor: ConnectionMonitor
    var activeBanner: NotificationBannerItem?
    var activeBannerURL: URL?
    var presentedProactivity: ProactivePresentation?
    private(set) var proactiveFindings: [ProactiveFinding] = []
    var menuBarQuickActionRequest: MenuBarQuickActionRequest?
    var appDeepLinkRequest: AppDeepLinkRequest?
    @ObservationIgnored lazy var browserWorkspace = BrowserWorkspaceState()
    #if os(iOS)
    @ObservationIgnored lazy var mobileBrowserLaunch = MobileBrowserLaunchState(browser: browserWorkspace)
    #endif
    var presentedSettings: ClientSettingsDestination?
    private(set) var pendingChatApprovalTracker = PendingChatApprovalTracker()

    var pendingApprovalSessionIDs: Set<String> {
        pendingChatApprovalTracker.sessionIDs
    }

    private var bannerDismissTask: Task<Void, Never>?
    private var notificationManager: NotificationSocketManager?
    private var notificationListenerTask: Task<Void, Never>?
    private var notificationBaseURL: URL?
    private var notificationConnectionRevision = UUID()
    private let logger: Logger
    private var mobileConnectionRevision = UUID()
    private var mobileConnectionRecovery = MobileConnectionRecovery()
    #if os(macOS)
    private let desktopOverlay = SloppyDesktopOverlay()
    private var openMainWindow: (@MainActor () -> Void)?
    #endif
    #if os(iOS)
    private let liveActivityCoordinator = SloppyLiveActivityCoordinator()
    #endif

    init(logger: Logger = Logger(label: "sloppy.root-shell"), launchPreferences: ClientLaunchPreferences? = nil) {
        self.logger = logger
        let preferences = launchPreferences ?? ClientLaunchPreferences()
        self.launchPreferences = preferences
        showsStandaloneBrowser = preferences.mode == .browser
        connectionMonitor = ConnectionMonitor(baseURL: URL(string: "http://localhost:25101")!)
        #if os(macOS)
        desktopOverlay.onOpenTask = { [weak self] projectID, taskID in
            self?.openTask(projectID: projectID, taskID: taskID)
        }
        desktopOverlay.onOpenSettings = { [weak self] destination in
            self?.presentedSettings = destination
            self?.desktopOverlay.presentMainWindow()
        }
        desktopOverlay.start(settings: settings)
        #endif
    }

    func handleDeepLink(_ url: URL) {
        if let webURL = BrowserSearchEngine.websiteURL(url) {
            if !launchPreferences.hasCompletedWelcome {
                launchPreferences.completeWelcome(mode: .browser)
            }
            presentedSettings = nil
            presentedProactivity = nil
            consoleConnectionCode = nil
            appDeepLinkRequest = nil
            connectionSetupRequested = false
            if case .chat = appState {
                // The connected workspace shares the same local browser.
            } else {
                showsStandaloneBrowser = true
            }
            browserWorkspace.isSearchPresented = false
            browserWorkspace.open(webURL, inNewTab: true)
            #if os(macOS)
            presentMainWindow()
            #endif
            return
        }
        if let code = ConsoleConnectionCode.parse(url) {
            prepareForInstanceLink()
            presentedSettings = nil
            consoleConnectionCode = code
            return
        }
        if let code = try? RemotePairingCode.decode(url) {
            prepareForInstanceLink()
            claimManagedRemote(code)
            return
        }
        if let pairing = DevicePairingLink.parse(url) {
            prepareForInstanceLink()
            redeemDevicePairing(pairing)
            return
        }

        guard let deepLink = DeepLink.parse(url) else { return }
        prepareForInstanceLink()

        if case .proactivity(let agentID, let findingID) = deepLink {
            presentedSettings = nil
            presentedProactivity = .init(agentID: agentID, findingID: findingID)
            return
        }
        presentedProactivity = nil
        if case .session = deepLink { presentedSettings = nil }

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

    private func prepareForInstanceLink() {
        if !launchPreferences.hasCompletedWelcome {
            launchPreferences.completeWelcome(mode: .instance)
        }
        showsStandaloneBrowser = false
    }

    func connectManagedRemote() {
        mobileConnectionRevision = UUID()
        let revision = mobileConnectionRevision
        guard let credential = ManagedRemoteCredentialStore.load(),
              credential.device.kind == .mobile else {
            showConnectionSetup()
            return
        }
        appState = .pairing(credential.relayURL)
        Task { @MainActor in
            do {
                let client = ManagedRemoteClient(relayURL: credential.relayURL)
                let hosts = try await client.hosts()
                guard acceptsConnectionResult(revision) else { return }
                settings.installManagedHosts(hosts, relayURL: credential.relayURL)
                try await ManagedRemoteConnection.shared.connect()
                guard acceptsConnectionResult(revision) else { return }
                connectionMonitor.start(baseURL: credential.relayURL)
                didConnectInstance()
                appState = .chat(credential.relayURL)
            } catch {
                guard acceptsConnectionResult(revision) else { return }
                connectionFailed(error)
                showBanner(for: AppNotification(
                    type: .systemError,
                    title: "Remote unavailable",
                    message: Self.errorDescription(error)
                ))
            }
        }
    }

    private func claimManagedRemote(_ code: RemotePairingCode) {
        let priorState = appState
        appState = .pairing(code.relayURL)
        Task { @MainActor in
            do {
                let client = ManagedRemoteClient(relayURL: code.relayURL)
                #if os(iOS)
                let name = UIDevice.current.name
                _ = try await client.claimPhonePairing(code, name: name)
                connectManagedRemote()
                #else
                let name = Host.current().localizedName ?? "Sloppy Mac"
                _ = try await client.claimHostPairing(code, name: name)
                await ManagedRemoteHostManager.shared.startIfNeeded(localCoreURL: settings.baseURL)
                appState = priorState
                #endif
            } catch {
                showConnectionSetup()
                showBanner(for: AppNotification(
                    type: .systemError,
                    title: "Pairing failed",
                    message: Self.errorDescription(error)
                ))
            }
        }
    }

    func startDesktopWindowIntegration() {
        #if os(macOS)
        desktopOverlay.start(settings: settings)
        #endif
    }

    func makeBrowserTextAnnotationReceiver() -> BrowserTextAnnotationReceiver? {
#if os(macOS)
        desktopOverlay.makeBrowserTextAnnotationReceiver()
#else
        nil
#endif
    }

    #if os(macOS)
    func configureMainWindowOpener(_ action: @escaping @MainActor () -> Void) {
        openMainWindow = action
    }

    func configureDesktopWindow(_ window: NSWindow) {
        desktopOverlay.attach(window: window)
    }

    func presentMainWindow() {
        openMainWindow?()
        desktopOverlay.presentMainWindow()
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
        presentMainWindow()
    }

    private func openTask(projectID: String, taskID: String) {
        if case .chat = appState {
            // Keep the current connected workspace.
        } else {
            startConnected(url: settings.baseURL)
        }
        appDeepLinkRequest = AppDeepLinkRequest(
            deepLink: .task(projectId: projectID, taskId: taskID)
        )
        presentMainWindow()
    }
    #endif

    func applyDesktopWindowCloseBehavior() {
        #if os(macOS)
        desktopOverlay.applyCloseBehavior(settings.windowCloseBehavior)
        #endif
    }

    func startConnected(url: URL) {
        didConnectInstance()
        mobileConnectionRevision = UUID()
        logger.info(
            "app.connection.connected",
            metadata: ["server": .string(Self.serverDescription(url))]
        )
        #if os(macOS)
        desktopOverlay.start(settings: settings, baseURL: url)
        #endif
        #if os(iOS)
        liveActivityCoordinator.start(baseURL: url)
        #endif
        connectionMonitor.start(baseURL: url)
        appState = .chat(url)
        startNotificationListener(baseURL: url)
        settings.installLocalInstance(baseURL: url)
        Task { @MainActor in
            do {
                let topology = try await SloppyAPIClient(baseURL: url).fetchMeshTopology()
                guard !Task.isCancelled else { return }
                settings.installMeshTopology(topology, coordinatorBaseURL: url)
            } catch {
                logger.warning(
                    "app.instances.discovery-failed",
                    metadata: ["error": .string(String(describing: error))]
                )
            }
        }
    }

    func startCloudConnected(url: URL) {
        didConnectInstance()
        mobileConnectionRevision = UUID()
        logger.info("app.connection.cloud-connected")
        connectionMonitor.start(endpoint: settings.activeInstanceEndpoint)
        appState = .chat(url)
    }

    func connect(to url: URL) {
        lastConnectionError = nil
        launchPreferences.hasConfiguredInstance = true
        appState = .pairing(url)
        mobileConnectionRevision = UUID()
        let revision = mobileConnectionRevision
        logger.info(
            "app.connection.requested",
            metadata: ["server": .string(Self.serverDescription(url))]
        )
        Task { @MainActor in
            await resolveConnection(to: url, revision: revision)
        }
    }

    func showConnectionSetup() {
        mobileConnectionRevision = UUID()
        stopConnectedServices()
        autoConnectCloud = false
        connectionSetupRequested = true
        showsStandaloneBrowser = false
        appState = .connectionSetup
    }

    var hasConfiguredInstance: Bool {
        launchPreferences.hasConfiguredInstance || !settings.savedServers.isEmpty
            || ManagedRemoteCredentialStore.load() != nil || ConsoleDeviceCredential.load() != nil
    }

    var agentConnectionStatus: AgentConnectionStatus {
        let connected: Bool
        let failure: String?
        if case .chat = appState {
            connected = connectionMonitor.state == .connected
            failure = connectionMonitor.state == .disconnected ? connectionMonitor.lastFailureMessage : nil
        } else {
            connected = false
            failure = lastConnectionError
        }
        return .resolve(configured: hasConfiguredInstance, connected: connected, failure: failure)
    }

    func completeWelcome(mode: ClientLaunchMode) {
        launchPreferences.completeWelcome(mode: mode)
        if mode == .browser {
            useAsBrowser()
        } else {
            showConnectionSetup()
        }
    }

    func useAsBrowser() {
        launchPreferences.completeWelcome(mode: .browser)
        mobileConnectionRevision = UUID()
        connectionSetupRequested = false
        showsStandaloneBrowser = true
        appState = .connectionSetup
    }

    func retryInstanceConnection() async {
        guard hasConfiguredInstance else { showConnectionSetup(); return }
        lastConnectionError = nil
        if case .chat = appState {
            await resetRemoteTransportIfNeeded()
            guard !Task.isCancelled else { return }
            connectionMonitor.start(endpoint: settings.activeInstanceEndpoint)
            return
        }
        mobileConnectionRevision = UUID()
        let revision = mobileConnectionRevision
        do { try await restoreSavedConnection(revision: revision) }
        catch {
            guard acceptsConnectionResult(revision) else { return }
            connectionFailed(error)
        }
    }

    private func resetRemoteTransportIfNeeded() async {
        guard case .managed(_, let hostID) = settings.activeInstanceEndpoint else { return }
        if await ConsoleRemoteClientRegistry.shared.contains(hostID: hostID) {
            await ConsoleRemoteClientRegistry.shared.disconnectAll()
        } else {
            await ManagedRemoteConnection.shared.disconnect()
        }
    }

    private func didConnectInstance() {
        launchPreferences.hasConfiguredInstance = true
        lastConnectionError = nil
        connectionSetupRequested = false
        showsStandaloneBrowser = false
    }

    private func connectionFailed(_ error: Error) {
        logger.error("app.connection.failed", metadata: ["error": .string(Self.errorDescription(error))])
        stopConnectedServices()
        connectionSetupRequested = false
        lastConnectionError = Self.errorDescription(error)
        appState = .connectionSetup
    }

    func presentSettings(_ destination: ClientSettingsDestination) {
        presentedSettings = destination
    }

    func dismissSettings() {
        presentedSettings = nil
    }

    func openUsageSession(_ session: ChatSessionSummary) {
        guard let url = DeepLink.session(agentId: session.agentId, sessionId: session.id).url else { return }
        handleDeepLink(url)
        #if os(macOS)
        presentMainWindow()
        #endif
    }

    func changeServer() {
        let baseURL = currentBaseURL
        stopConnectedServices()
        Task { @MainActor in
            await SloppyAPIClient(baseURL: baseURL).logout()
            showConnectionSetup()
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
            guard acceptsAuthenticationRequirement(for: baseURL) else {
                logger.info(
                    "app.authentication.requirement-ignored",
                    metadata: ["server": .string(Self.serverDescription(baseURL))]
                )
                continue
            }
            logger.warning(
                "app.authentication.required",
                metadata: ["server": .string(Self.serverDescription(baseURL))]
            )
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
        logger.info("app.lifecycle.phase", metadata: ["phase": .string(String(describing: scenePhase))])
        if scenePhase == .background {
            mobileConnectionRecovery.didEnterBackground()
            connectionMonitor.stop()
        }
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

        let revision = UUID()
        notificationConnectionRevision = revision
        let manager = NotificationSocketManager(baseURL: baseURL, onConnect: { [weak self] in
            await self?.reloadNotificationHistory(baseURL: baseURL, revision: revision)
        })
        notificationManager = manager
        notificationBaseURL = baseURL
        pendingChatApprovalTracker = PendingChatApprovalTracker()
        notificationListenerTask = Task { @MainActor in
            // Restore pending requests (and refresh HTTP credentials) even if
            // the notification socket cannot complete its first handshake yet.
            await reloadPendingToolApprovals(baseURL: baseURL, revision: revision)
            guard !Task.isCancelled, notificationConnectionRevision == revision else { return }
            let stream = await manager.connect()
            for await notification in stream {
                guard !Task.isCancelled, notificationConnectionRevision == revision else { return }
                var tracker = pendingChatApprovalTracker
                tracker.apply(notification)
                pendingChatApprovalTracker = tracker
                showBanner(for: notification)
                Task {
                    guard notificationConnectionRevision == revision else { return }
                    await LocalAgentResponseNotificationScheduler.shared.updateToolApproval(notification)
                }
            }
        }
    }

    private func reloadNotificationHistory(baseURL: URL, revision: UUID) async {
        await reloadPendingToolApprovals(baseURL: baseURL, revision: revision)
        guard notificationConnectionRevision == revision else { return }
        await reloadProactiveHistory(baseURL: baseURL)
    }

    private func reloadPendingToolApprovals(baseURL: URL, revision: UUID) async {
        let fetchedAt = Date()
        do {
            let pending = try await SloppyAPIClient(baseURL: baseURL).fetchPendingToolApprovals()
            guard notificationConnectionRevision == revision else { return }
            let previousIDs = pendingChatApprovalTracker.approvalIDs
            pendingChatApprovalTracker.reconcilePending(pending, fetchedAt: fetchedAt)
            let currentIDs = pendingChatApprovalTracker.approvalIDs
            for id in previousIDs.subtracting(currentIDs) {
                LocalAgentResponseNotificationScheduler.shared.dismissApproval(id: id)
            }
            for approval in pending where currentIDs.contains(approval.id) {
                if let notification = AgentToolApprovalNotification(approval: approval) {
                    Task {
                        guard notificationConnectionRevision == revision else { return }
                        await LocalAgentResponseNotificationScheduler.shared.scheduleApproval(notification)
                    }
                }
            }
        } catch {
            logger.warning("app.notifications.pending-approvals-load-failed",
                metadata: ["error": .string(String(describing: error))])
        }
    }

    private var currentBaseURL: URL {
        switch appState {
        case .authentication(let url, _, _), .pairing(let url), .chat(let url):
            return url
        case .splash, .connectionSetup:
            return settings.baseURL
        }
    }

    private func reloadProactiveHistory(baseURL: URL) async {
        do {
            let findings = try await SloppyAPIClient(baseURL: baseURL).fetchAllProactiveFindings()
            guard notificationBaseURL == baseURL else { return }
            proactiveFindings = findings
        } catch { logger.warning("Could not reload attention history: \(error)") }
    }

    func openActiveNotification() {
        guard let url = activeBannerURL else { return }
        activeBanner = nil
        handleDeepLink(url)
    }

    private func presentAuthentication(for baseURL: URL, message: String?) async {
        if case .authentication(let currentURL, _, _) = appState,
           currentURL == baseURL {
            return
        }
        guard acceptsAuthenticationRequirement(for: baseURL) else { return }
        stopConnectedServices()
        let apiClient = SloppyAPIClient(baseURL: baseURL)
        let challenge: AuthChallenge
        do {
            challenge = try await apiClient.fetchConnectionAuthChallenge()
        } catch {
            guard acceptsAuthenticationRequirement(for: baseURL) else { return }
            logger.error(
                "app.authentication.challenge-failed",
                metadata: [
                    "error": .string(Self.errorDescription(error)),
                    "server": .string(Self.serverDescription(baseURL)),
                ]
            )
            connectionFailed(error)
            return
        }
        guard acceptsAuthenticationRequirement(for: baseURL) else {
            logger.info(
                "app.authentication.requirement-ignored",
                metadata: ["server": .string(Self.serverDescription(baseURL))]
            )
            return
        }
        if challenge.mode != "login_password",
           let status = try? await apiClient.fetchDashboardAuthStatus(),
           !status.enabled {
            appState = .splash
            return
        }
        logger.info(
            "app.authentication.presented",
            metadata: [
                "mode": .string(challenge.mode),
                "server": .string(Self.serverDescription(baseURL)),
            ]
        )
        appState = .authentication(baseURL, challenge, message)
    }

    private func acceptsAuthenticationRequirement(for baseURL: URL) -> Bool {
        switch appState {
        case .authentication(let activeURL, _, _), .chat(let activeURL):
            return activeURL == baseURL
        case .splash, .connectionSetup, .pairing:
            return false
        }
    }

    private func resolveConnection(to baseURL: URL, revision: UUID? = nil) async {
        let apiClient = SloppyAPIClient(baseURL: baseURL)
        let challenge: AuthChallenge
        do {
            challenge = try await apiClient.fetchConnectionAuthChallenge()
        } catch let error as APIError where error.statusCode == 404 {
            guard acceptsConnectionResult(revision) else { return }
            logger.info(
                "app.authentication.unsupported-by-server",
                metadata: ["server": .string(Self.serverDescription(baseURL))]
            )
            startConnected(url: baseURL)
            return
        } catch {
            guard acceptsConnectionResult(revision) else { return }
            logger.error(
                "app.connection.auth-resolution-failed",
                metadata: [
                    "error": .string(Self.errorDescription(error)),
                    "server": .string(Self.serverDescription(baseURL)),
                ]
            )
            connectionFailed(error)
            return
        }

        guard acceptsConnectionResult(revision) else { return }
        logger.info(
            "app.authentication.resolved",
            metadata: [
                "mode": .string(challenge.mode),
                "server": .string(Self.serverDescription(baseURL)),
            ]
        )

        if challenge.mode == "login_password" {
            var message: String?
            if await apiClient.hasStoredAuthSession() {
                do {
                    _ = try await apiClient.fetchCurrentAuthUser()
                    guard acceptsConnectionResult(revision) else { return }
                    startConnected(url: baseURL)
                    return
                } catch {
                    guard acceptsConnectionResult(revision) else { return }
#if os(iOS)
                    guard MobileConnectionFailure.invalidatesSavedSession(error) else {
                        connectionFailed(error)
                        return
                    }
#endif
                    logger.warning(
                        "app.authentication.saved-session-rejected",
                        metadata: ["server": .string(Self.serverDescription(baseURL))]
                    )
                    await apiClient.logout()
                    message = "Your saved session has expired. Sign in again."
                }
            }
            #if os(macOS)
            do {
                if try await LocalOwnerAuthentication.restore(baseURL: baseURL) {
                    logger.info("app.authentication.local-owner-connected")
                    startConnected(url: baseURL)
                    return
                }
            } catch {
                logger.warning("app.authentication.local-owner-unavailable")
            }
            #endif
            logger.info(
                "app.authentication.presented",
                metadata: ["mode": .string(challenge.mode), "server": .string(Self.serverDescription(baseURL))]
            )
            guard acceptsConnectionResult(revision) else { return }
            appState = .authentication(baseURL, challenge, message)
            return
        }

        let dashboardAuthEnabled = (try? await apiClient.fetchDashboardAuthStatus().enabled) ?? false
        guard acceptsConnectionResult(revision) else { return }
        guard dashboardAuthEnabled else {
            startConnected(url: baseURL)
            return
        }
        if await apiClient.hasStoredAuthSession() {
            do {
                try await apiClient.validateCurrentAuthToken()
                guard acceptsConnectionResult(revision) else { return }
                startConnected(url: baseURL)
                return
            } catch {
                guard acceptsConnectionResult(revision) else { return }
#if os(iOS)
                guard MobileConnectionFailure.invalidatesSavedSession(error) else {
                    connectionFailed(error)
                    return
                }
#endif
                logger.warning(
                    "app.authentication.saved-token-rejected",
                    metadata: ["server": .string(Self.serverDescription(baseURL))]
                )
                await apiClient.logout()
            }
        }
        logger.info(
            "app.authentication.presented",
            metadata: [
                "mode": .string(challenge.mode),
                "server": .string(Self.serverDescription(baseURL)),
            ]
        )
        guard acceptsConnectionResult(revision) else { return }
        appState = .authentication(baseURL, challenge, nil)
    }

    private func acceptsConnectionResult(_ revision: UUID?) -> Bool {
        !Task.isCancelled && (revision == nil || revision == mobileConnectionRevision)
    }

#if os(iOS)
    /// The view's task owns this loop; backgrounding cancels it, foregrounding retries.
    func restoreMobileConnectionInBackground() async {
        guard launchPreferences.hasCompletedWelcome else { return }
        if mobileConnectionRecovery.consumeForegroundRecovery(), case .chat = appState {
            let startedAt = Date()
            logger.info("app.connection.foreground-recovery-started")
            defer {
                if Task.isCancelled { mobileConnectionRecovery.didEnterBackground() }
                logger.info("app.connection.foreground-recovery-finished", metadata: [
                    "duration_ms": .stringConvertible(Int(Date().timeIntervalSince(startedAt) * 1_000)),
                ])
            }
            // iOS may suspend a socket without delivering its close until the
            // next write. Keep the workspace mounted, but negotiate fresh transport.
            await resetRemoteTransportIfNeeded()
            guard !Task.isCancelled else { return }
            connectionMonitor.start(endpoint: settings.activeInstanceEndpoint)
        }
        await MobileConnectionRetryLoop.run {
            guard hasConfiguredInstance else { return .idle }
            if MobileConnectionRecovery.shouldRestore(state: appState, setupRequested: connectionSetupRequested) {
                let revision = mobileConnectionRevision
                do {
                    try await restoreSavedConnection(revision: revision)
                } catch {
                    guard acceptsConnectionResult(revision) else { return .idle }
                    connectionFailed(error)
                }
                return MobileConnectionRecovery.shouldRestore(state: appState, setupRequested: connectionSetupRequested)
                    ? .retry : .idle
            }
            return .idle
        }
    }
#endif

    private func restoreSavedConnection(revision: UUID) async throws {
        let startedAt = Date()
        logger.info("app.connection.restore-started")
        defer {
            logger.info("app.connection.restore-finished", metadata: [
                "duration_ms": .stringConvertible(Int(Date().timeIntervalSince(startedAt) * 1_000)),
            ])
        }
        let signedIn = await ConsoleAccountClient.shared.isSignedIn()
        guard acceptsConnectionResult(revision) else { return }
        if signedIn {
            logger.info("app.connection.restore-route", metadata: ["route": "console"])
            let snapshot = try await ConsoleAccountClient.shared.snapshot()
            guard acceptsConnectionResult(revision) else { return }
            let unverified = await ConsoleRemoteClientRegistry.shared.installDirectory(snapshot)
            guard acceptsConnectionResult(revision) else { return }
            settings.installConsoleInstances(snapshot.instances, unverifiedHostIDs: unverified,
                relayURL: ManagedRemoteClient.productionURL)
            let servers = CloudServerSelection.activeInstances(snapshot.instances)
            let preferred = servers.first {
                settings.instanceSelection.instanceID == "managed:\($0.spaceID):\($0.hostDeviceID)"
            }?.hostDeviceID
            for instance in CloudServerSelection.orderedInstances(servers, preferredHostID: preferred) {
                guard await ConsoleRemoteClientRegistry.shared.hasTrustedPin(for: instance),
                      let host = snapshot.devices.first(where: { $0.id == instance.hostDeviceID && $0.status == .active }),
                      let deviceID = ConsoleDeviceCredential.load()?.deviceID,
                      snapshot.devices.contains(where: { $0.id == deviceID && $0.status == .active }),
                      let grant = snapshot.grants.first(where: {
                          $0.instanceID == instance.id && $0.deviceID == deviceID && $0.status == .active
                      }) else { continue }
                guard acceptsConnectionResult(revision) else { return }
                try await ConsoleRemoteClientRegistry.shared.connect(instance: instance, hostCertificate: host.certificateDER,
                    expectedFingerprint: instance.hostCertificateFingerprint, organizationID: grant.organizationID)
                guard acceptsConnectionResult(revision) else { return }
                if let selected = settings.discoveredInstances.first(where: {
                    if case .managed(_, let id) = $0.endpoint { id == instance.hostDeviceID } else { false }
                }) { settings.instanceSelection = .instance(selected.id) }
                startCloudConnected(url: ManagedRemoteClient.productionURL)
                return
            }
            appState = .connectionSetup
        } else if let credential = ManagedRemoteCredentialStore.load(), credential.device.kind == .mobile {
            logger.info("app.connection.restore-route", metadata: ["route": "managed-remote"])
            let hosts = try await ManagedRemoteClient(relayURL: credential.relayURL).hosts()
            guard acceptsConnectionResult(revision) else { return }
            try await ManagedRemoteConnection.shared.connect()
            guard acceptsConnectionResult(revision) else { return }
            settings.installManagedHosts(hosts, relayURL: credential.relayURL)
            connectionMonitor.start(endpoint: settings.activeInstanceEndpoint)
            didConnectInstance()
            appState = .chat(credential.relayURL)
        } else if !settings.savedServers.isEmpty || launchPreferences.hasConfiguredInstance {
            logger.info("app.connection.restore-route", metadata: ["route": "direct"])
            await resolveConnection(to: settings.baseURL, revision: revision)
        } else {
            appState = .connectionSetup
        }
    }

    private func redeemDevicePairing(_ pairing: DevicePairingLink) {
        let baseURL = pairing.serverURL
        stopConnectedServices()
        appState = .pairing(baseURL)
        logger.info(
            "app.authentication.device-pairing-started",
            metadata: ["server": .string(Self.serverDescription(baseURL))]
        )

        Task { @MainActor in
            var lastError: Error?
            for candidateURL in pairing.serverURLs {
                let apiClient = SloppyAPIClient(
                    baseURL: candidateURL,
                    tlsFingerprint: pairing.tlsFingerprint
                )
                do {
                    _ = try await apiClient.redeemDevicePairing(token: pairing.token)
                    ClientTLSFingerprintStore.set(pairing.tlsFingerprint, for: candidateURL)
                    if let host = candidateURL.host {
                        settings.useServer(
                            SavedServer(
                                label: pairing.label ?? "Sloppy @ \(host)",
                                scheme: candidateURL.scheme ?? "http",
                                host: host,
                                port: candidateURL.port ?? (candidateURL.scheme == "https" ? 443 : 25101),
                                tlsFingerprint: pairing.tlsFingerprint
                            )
                        )
                    }
                    logger.info(
                        "app.authentication.device-pairing-succeeded",
                        metadata: ["server": .string(Self.serverDescription(candidateURL))]
                    )
                    startConnected(url: candidateURL)
                    return
                } catch {
                    lastError = error
                }
            }
            if let lastError {
                logger.warning(
                    "app.authentication.device-pairing-failed",
                    metadata: [
                        "error": .string(Self.errorDescription(lastError)),
                        "server": .string(Self.serverDescription(baseURL)),
                    ]
                )
                let fallbackClient = SloppyAPIClient(
                    baseURL: baseURL,
                    tlsFingerprint: pairing.tlsFingerprint
                )
                let challenge = (try? await fallbackClient.fetchConnectionAuthChallenge())
                    ?? AuthChallenge(mode: "login_password", bootstrapRequired: false)
                appState = .authentication(
                    baseURL,
                    challenge,
                    "Could not use this QR code. It may have expired or already been used. Generate a new code in Dashboard."
                )
            }
        }
    }

    private nonisolated static func serverDescription(_ url: URL) -> String {
        guard let host = url.host else { return "unknown-server" }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }

    private nonisolated static func errorDescription(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.diagnosticDescription
        }
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
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
        notificationConnectionRevision = UUID()
        pendingChatApprovalTracker = PendingChatApprovalTracker()
    }

    private func showBanner(for notification: AppNotification) {
        let c = AppColors.dark
        let color: Color = switch notification.type {
        case .agentError, .systemError: c.statusBlocked
        case .pendingApproval, .toolApproval: c.statusWarning
        case .confirmation: c.statusDone
        case .proactiveAttention: c.statusWarning
        }

        #if os(macOS)
        if notification.type == .toolApproval {
            desktopOverlay.updateToolApproval(notification)
            return
        }
        #endif
        #if os(iOS)
        liveActivityCoordinator.apply(notification)
        #endif

        bannerDismissTask?.cancel()
        if notification.type == .proactiveAttention, let agentID = notification.metadata["agentId"] {
            activeBannerURL = DeepLink.proactivity(agentId: agentID, findingId: notification.metadata["findingId"]).url
            Task { await reloadProactiveHistory(baseURL: currentBaseURL) }
        } else { activeBannerURL = nil }
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
