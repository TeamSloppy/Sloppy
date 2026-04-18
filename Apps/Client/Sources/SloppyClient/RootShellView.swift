import AdaEngine
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat
import SloppyFeatureSettings

@MainActor
struct RootShellView: View {
    @State private var viewModel = RootShellViewModel()

    var body: some View {
        RootShellContent()
            .environment(viewModel)
    }
}

@MainActor
private struct RootShellContent: View {
    @Environment(RootShellViewModel.self) private var viewModel
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors

        return ZStack(anchor: .topLeading) {
            c.background.ignoresSafeArea()

            switch viewModel.appState {

            case .splash:
                SplashScreen(settings: viewModel.settings) { result in
                    switch result {
                    case .connected(let url):
                        viewModel.startConnected(url: url)
                    case .needsSetup:
                        viewModel.appState = .connectionSetup
                    }
                }

            case .connectionSetup:
                ConnectionSetupView(settings: viewModel.settings) { url in
                    viewModel.startConnected(url: url)
                }

            case .chat(let url):
                ChatScreen(
                    apiClient: SloppyAPIClient(baseURL: url),
                    settings: viewModel.settings,
                    connectionMonitor: viewModel.connectionMonitor,
                    onOpenSettings: { viewModel.appState = .settings }
                )

            case .settings:
                SettingsScreen(
                    settings: viewModel.settings,
                    onDismiss: { viewModel.appState = .chat(viewModel.settings.baseURL) }
                )
            }

            if let banner = viewModel.activeBanner {
                NotificationBanner(item: banner)
                    .frame(width: Float(320))
                    .padding(theme.spacing.m)
            }
        }
        .onAppear {
            viewModel.startDeepLinkListener()
        }
        .background {
            theme.colors.background.ignoresSafeArea()
        }
    }
}
