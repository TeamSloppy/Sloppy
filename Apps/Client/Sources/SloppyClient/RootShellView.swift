import AdaEngine
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat
import SloppyFeatureSettings

@MainActor
struct RootShellView: View {

    @State private var debugOverlayMode: UIDebugOverlayMode?
    @State private var viewModel = RootShellViewModel()

    var body: some View {
        RootShellContent(viewModel: viewModel)
            .environment(viewModel)
            .theme(viewModel.settings.colorScheme.appTheme)
            .debugOverlay(debugOverlayMode ?? .off)
            .keyboardShortcuts([
                KeyboardShortcutAction(
                    .r, modifiers: [.command, .shift],
                    action: {
                        setDebugOverlayMode(.redraw)
                    }),
                KeyboardShortcutAction(
                    .h, modifiers: [.command, .shift],
                    action: {
                        setDebugOverlayMode(.hitTestTarget)
                    }),
                KeyboardShortcutAction(
                    .d, modifiers: [.command, .shift],
                    action: {
                        setDebugOverlayMode(.layoutBounds)
                    }),
                KeyboardShortcutAction(
                    .f, modifiers: [.command, .shift],
                    action: {
                        setDebugOverlayMode(.focusedNode)
                    }),
            ])
    }

    private func setDebugOverlayMode(_ mode: UIDebugOverlayMode) {
        debugOverlayMode = debugOverlayMode == mode ? .off : mode
    }
}

@MainActor
private struct RootShellContent: View {
    @State var viewModel: RootShellViewModel
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @Environment(\.theme) private var theme

    var body: some View {
        let rootViewModel = viewModel

        return ZStack(anchor: .topLeading) {
            AppAtmosphericBackground()

            switch rootViewModel.appState {
            case .splash:
                SplashScreen(settings: rootViewModel.settings) { result in
                    switch result {
                    case .connected(let url):
                        rootViewModel.startConnected(url: url)
                    case .needsSetup:
                        rootViewModel.appState = .connectionSetup
                    }
                }

            case .connectionSetup:
                ConnectionSetupView(settings: rootViewModel.settings) { url in
                    rootViewModel.startConnected(url: url)
                }

            case .chat(let url):
                MainView(
                    baseURL: url,
                    settings: rootViewModel.settings,
                    connectionMonitor: rootViewModel.connectionMonitor,
                    rootSafeAreaInsets: safeAreaInsets,
                    onOpenSettings: {
                        rootViewModel.appState = .settings
                    },
                    onOpenWorkspace: {
                        rootViewModel.appState = .connectionSetup
                    }
                )

            case .settings:
                SettingsScreen(
                    settings: rootViewModel.settings,
                    onDismiss: {
                        rootViewModel.startConnected(url: rootViewModel.settings.baseURL)
                    }
                )
            }

            if let banner = rootViewModel.activeBanner {
                NotificationBanner(item: banner)
                    .frame(width: Float(320))
                    .padding(theme.spacing.m)
            }
        }
        .frame(
            minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity,
            alignment: .topLeading
        )
        .onAppear {
            rootViewModel.startDeepLinkListener()
            rootViewModel.startDesktopWindowIntegration()
        }
        .onChange(of: rootViewModel.settings.windowCloseBehavior) { _, _ in
            rootViewModel.applyDesktopWindowCloseBehavior()
        }
        .background {
            theme.colors.background.ignoresSafeArea()
        }
    }
}

extension ClientColorScheme {
    fileprivate var appTheme: Theme {
        switch self {
        case .light:
            return .sloppyLight
        case .dark:
            return .sloppyDark
        }
    }
}
