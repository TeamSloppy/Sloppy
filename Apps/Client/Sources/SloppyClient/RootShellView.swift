import AdaEngine
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat
import SloppyFeatureSettings

@MainActor
struct RootShellView: View {
    @State private var viewModel = RootShellViewModel()

    var body: some View {
        RootShellContent(viewModel: viewModel)
            .environment(viewModel)
    }
}

@MainActor
private struct RootShellContent: View {
    @State var viewModel: RootShellViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        let rootViewModel = viewModel
        let c = theme.colors

        return ZStack(anchor: .topLeading) {
            c.background.ignoresSafeArea()

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
                ChatScreen(
                    apiClient: SloppyAPIClient(baseURL: url),
                    settings: rootViewModel.settings,
                    connectionMonitor: rootViewModel.connectionMonitor,
                    onOpenSettings: {
                        rootViewModel.appState = .settings
                    }
                )

            case .settings:
                SettingsScreen(
                    settings: rootViewModel.settings,
                    onDismiss: {
                        rootViewModel.appState = .chat(rootViewModel.settings.baseURL)
                    }
                )
            }

            if let banner = rootViewModel.activeBanner {
                NotificationBanner(item: banner)
                    .frame(width: Float(320))
                    .padding(theme.spacing.m)
            }
        }
        .onAppear {
            rootViewModel.startDeepLinkListener()
        }
        .background {
            theme.colors.background.ignoresSafeArea()
        }
    }
}
