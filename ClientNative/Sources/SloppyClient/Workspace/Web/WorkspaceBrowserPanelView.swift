import SwiftUI
import SloppyClientUI
import SloppyFeatureChat

@MainActor
struct WorkspaceBrowserPanelView: View {
    @Bindable var viewModel: WorkspaceWebViewModel
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    var onOpenTool: (@MainActor (WorkspaceSidePanelItem) -> Void)? = nil
    var allowsProjectTools = false
    var onAnnotate: (@MainActor () -> (@MainActor (ChatComposerAttachment) -> Bool))? = nil
    @FocusState private var isAddressFocused: Bool

    var body: some View {
#if os(macOS)
        desktopBrowser
#else
        compactBrowser
#endif
    }

#if os(macOS)
    private var desktopBrowser: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    navigationButton("arrow.left", title: "Back", enabled: viewModel.canGoBack, action: viewModel.goBack)
                    navigationButton("arrow.right", title: "Forward", enabled: viewModel.canGoForward, action: viewModel.goForward)
                    Rectangle().fill(theme.colors.borderBold).frame(width: 1, height: 16).padding(.horizontal, 3)
                    navigationButton("arrow.clockwise", title: "Reload", action: viewModel.reload)
                }
                .padding(.horizontal, 4)
                .background(theme.colors.surfaceRaised, in: Capsule())

                annotationButton

                HStack(spacing: 4) {
                    TextField("Enter a URL", text: $viewModel.addressText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.colors.textPrimary)
                        .focused($isAddressFocused)
                        .onSubmit {
                            viewModel.openAddress()
                            isAddressFocused = false
                        }
                        .accessibilityLabel("Browser address")
                        .accessibilityIdentifier("workspace-browser-address")

                    navigationButton("arrow.up.right", title: "Open in default browser", enabled: externalBrowserURL != nil) {
                        if let url = externalBrowserURL {
                            openURL(url)
                        }
                    }
                    .accessibilityIdentifier("workspace-browser-open-external")
                }
                .padding(.leading, 16)
                .padding(.trailing, 6)
                .frame(minWidth: 60, minHeight: 36)
                .background(theme.colors.surfaceRaised, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(isAddressFocused ? theme.colors.borderBold : theme.colors.border, lineWidth: 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.colors.surface)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.colors.border).frame(height: 1)
            }

            if viewModel.isLoading {
                ProgressView().controlSize(.small).padding(.vertical, 6)
            }
            if let error = viewModel.lastError {
                Text(error).font(.caption).foregroundStyle(theme.colors.statusBlocked)
                    .textSelection(.enabled).padding(10)
            }
            if let error = viewModel.annotations.errorMessage {
                Text(error).font(.caption).foregroundStyle(theme.colors.statusBlocked).padding(10)
            }
            WorkspaceWebView(viewModel: viewModel)
                .id(ObjectIdentifier(viewModel))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("workspace-browser-page")
                .overlay {
                    if viewModel.annotations.isSelecting || viewModel.annotations.isCapturing {
                        WorkspaceBrowserAnnotationPicker(model: viewModel.annotations)
                    } else if let draft = viewModel.annotations.draft {
                        WorkspaceBrowserAnnotationOverlay(model: viewModel.annotations, draft: draft)
                    }
                }
                .overlay {
                    if !viewModel.isLoading && (viewModel.currentURL == nil || viewModel.currentURL?.absoluteString == "about:blank") {
                        WorkspaceBrowserStartView(
                            allowsProjectTools: allowsProjectTools,
                            onOpenTool: onOpenTool,
                            onFocusAddress: { isAddressFocused = true },
                            recentSites: Array(viewModel.history.sites.prefix(8)),
                            onOpenRecentSite: { url in
                                viewModel.addressText = url.absoluteString
                                viewModel.openAddress()
                            }
                        )
                    }
                }
        }
        .background(theme.colors.surface)
        .onDisappear { viewModel.annotations.stopPicking() }
    }

    private var annotationButton: some View {
        let annotations = viewModel.annotations
        let isActive = annotations.isSelecting || annotations.draft != nil
        return Button {
            if isActive { annotations.cancel() }
            else if let onAnnotate {
                let receive = onAnnotate()
                Task { await annotations.begin(in: viewModel.ensureBrowserRuntime().webView, receive: receive) }
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                Label("Annotate", systemImage: "cursorarrow.click.2").fixedSize()
                Image(systemName: "cursorarrow.click.2")
            }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10)
                .frame(minWidth: 36, minHeight: 36)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? theme.colors.textPrimary : theme.colors.textSecondary)
        .background(isActive ? theme.colors.surfaceRaised : theme.colors.surfaceGlow, in: Capsule())
        .disabled(onAnnotate == nil || externalBrowserURL == nil || viewModel.isLoading || annotations.isCapturing)
        .help(onAnnotate == nil ? "Open a chat to annotate this page" : "Annotate an element on this page")
        .accessibilityLabel("Annotate")
        .accessibilityIdentifier("workspace-browser-annotate")
    }
#endif

    private var externalBrowserURL: URL? {
        guard let url = viewModel.currentURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    private func navigationButton(
        _ symbol: String,
        title: String,
        enabled: Bool = true,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? theme.colors.textSecondary : theme.colors.textMuted.opacity(0.45))
        .disabled(!enabled)
        .help(title)
        .accessibilityLabel(title)
    }

    private var compactBrowser: some View {
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
