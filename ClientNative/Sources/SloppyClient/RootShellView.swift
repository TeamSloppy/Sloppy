import SwiftUI
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat
import SloppyFeatureSettings

@MainActor
struct RootShellView: View {
    let viewModel: RootShellViewModel

    init() {
        self.viewModel = RootShellViewModel()
    }

    init(viewModel: RootShellViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        RootShellContent(viewModel: viewModel)
            .environment(viewModel)
            .theme(viewModel.settings.colorScheme.appTheme)
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
    }
}

@MainActor
private struct RootShellContent: View {
    let viewModel: RootShellViewModel
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @Environment(\.theme) private var theme

    var body: some View {
        let rootViewModel = viewModel

        return ZStack(alignment: .topLeading) {
            AppAtmosphericBackground()
                .ignoresSafeArea()

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
                    .frame(width: 320)
                    .padding(theme.spacing.m)
            }
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
}

#Preview {
    RootShellView()
}
