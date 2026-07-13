import SwiftUI
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat
import SloppyFeatureSettings

@MainActor
struct RootShellView: View {
    @State var viewModel: RootShellViewModel
    #if os(macOS)
    @State private var backendInstallation = BackendInstallationModel()
    #endif

    init() {
        self._viewModel = State(initialValue: RootShellViewModel())
    }

    init(viewModel: RootShellViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            RootShellContent(viewModel: viewModel)
            #if os(macOS)
            if backendInstallation.blocksApp {
                BackendInstallationView(model: backendInstallation)
                    .transition(.opacity)
                    .zIndex(100)
            }
            #endif
        }
            .environment(viewModel)
        #if os(visionOS)
            .theme(.sloppyDark)
            .preferredColorScheme(.dark)
        #else
            .theme(viewModel.settings.colorScheme.appTheme)
            .preferredColorScheme(viewModel.settings.colorScheme.systemColorScheme)
        #endif
            .injectSafeAreaInsets()
            .background {
                #if os(macOS)
                TransparentWindowConfigurationView { window in
                    viewModel.configureDesktopWindow(window)
                }
                #endif
            }
            .onOpenURL { url in
                viewModel.handleDeepLink(url)
            }
            #if os(macOS)
            .task {
                backendInstallation.checkIfNeeded()
            }
            #endif
    }
}

@MainActor
private struct RootShellContent: View {
    @State var viewModel: RootShellViewModel
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @Environment(\.theme) private var theme

    var body: some View {
        let rootViewModel = viewModel

        return ZStack(alignment: .topLeading) {
            #if os(macOS)
            AppAtmosphericBackground()
                .ignoresSafeArea()
            #else
            theme.colors.background
                .ignoresSafeArea()
            #endif

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
                    },
                    menuBarQuickActionRequest: rootViewModel.menuBarQuickActionRequest,
                    onConsumeMenuBarQuickAction: rootViewModel.consumeMenuBarAction
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
                    .frame(width: 320)
                    .padding(theme.spacing.m)
            }

            #if os(macOS)
            WindowDragHandleStrip(height: max(0, safeAreaInsets.top))
                .frame(height: max(0, safeAreaInsets.top))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            rootViewModel.startDesktopWindowIntegration()
        }
        .onChange(of: rootViewModel.settings.windowCloseBehavior) { _, _ in
            rootViewModel.applyDesktopWindowCloseBehavior()
        }
    }
}

extension ClientColorScheme {
    fileprivate var appTheme: AppTheme {
        switch self {
        case .light:
            return .sloppyLight
        case .dark:
            return .sloppyDark
        }
    }

    fileprivate var systemColorScheme: ColorScheme {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

#Preview {
    @Previewable @State var viewModel = RootShellViewModel()
    return RootShellView(viewModel: viewModel)
}
