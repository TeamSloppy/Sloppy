import SwiftUI
import SloppyClientUI

@MainActor
struct WorkspaceBrowserPanelView: View {
    @Bindable var viewModel: WorkspaceWebViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: viewModel.goBack) { Image(systemName: "chevron.left") }
                    .disabled(!viewModel.canGoBack)
                    .accessibilityLabel("Back")
                Button(action: viewModel.goForward) { Image(systemName: "chevron.right") }
                    .disabled(!viewModel.canGoForward)
                    .accessibilityLabel("Forward")
                Button(action: viewModel.reload) { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Reload")
                TextField("Open URL", text: $viewModel.addressText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(viewModel.openAddress)
                    .accessibilityIdentifier("workspace-browser-address")
            }
            .buttonStyle(.plain)
            .padding(10)
            if viewModel.isLoading { ProgressView().controlSize(.small) }
            if let error = viewModel.lastError {
                Text(error).font(.caption).foregroundStyle(.secondary).padding(8)
            }
            Divider()
            WorkspaceWebView(viewModel: viewModel)
                .id(ObjectIdentifier(viewModel))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("workspace-browser-page")
                .overlay {
                    if !viewModel.isLoading && (viewModel.currentURL == nil || viewModel.currentURL?.absoluteString == "about:blank") {
                        theme.colors.surface
                            .overlay {
                                VStack(spacing: 12) {
                                    Image(systemName: "globe").font(.system(size: 28, weight: .light))
                                    Text("Enter a URL above").font(.callout)
                                }
                                .foregroundStyle(theme.colors.textMuted)
                            }
                            .allowsHitTesting(false)
                    }
                }
        }
        .background(theme.colors.surface)
    }
}
