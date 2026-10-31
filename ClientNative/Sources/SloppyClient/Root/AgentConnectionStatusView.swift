import SwiftUI
import SloppyClientCore
import SloppyClientUI

/// Shared by the browser assistant and the disconnected Work surface.
struct AgentConnectionStatusView: View {
    let root: RootShellViewModel
    let onConfigure: () -> Void
    @State private var retrying = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: symbol).font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text(title).font(.title2.weight(.semibold))
                Text(message).font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .failed = root.agentConnectionStatus {
                Button("Try again") { retry() }
                    .appPrimaryButton()
                    .disabled(retrying)
                    .accessibilityIdentifier("assistant-connection-retry")
            } else if case .waiting = root.agentConnectionStatus {
                if retrying { ProgressView().accessibilityLabel("Connecting") }
                Button("Connect now") { retry() }
                    .appPrimaryButton()
                    .disabled(retrying)
                    .accessibilityIdentifier("assistant-connection-retry")
            }
            Button(root.hasConfiguredInstance ? "Connection settings" : "Connect to Sloppy", action: onConfigure)
                .appSecondaryButton()
                .accessibilityIdentifier("assistant-connection-setup")
        }
        .multilineTextAlignment(.center)
        .padding(28)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assistant-connection-status")
    }

    private var title: String {
        switch root.agentConnectionStatus {
        case .notConfigured: "Sloppy is not configured"
        case .waiting: "Waiting for connection"
        case .failed: "Couldn’t connect to Sloppy"
        case .connected: "Sloppy is connected"
        }
    }

    private var message: String {
        switch root.agentConnectionStatus {
        case .notConfigured: "Connect your Sloppy instance to chat with an agent. You can keep browsing in the meantime."
        case .waiting: "Your instance is configured. The assistant will be ready when the connection is restored."
        case .failed: "Your Sloppy instance is unavailable. Check your connection and try again."
        case .connected: "Your assistant is ready."
        }
    }

    private var symbol: String {
        switch root.agentConnectionStatus {
        case .notConfigured: "bubble.left.and.bubble.right"
        case .waiting: "network"
        case .failed: "wifi.exclamationmark"
        case .connected: "checkmark.circle"
        }
    }

    private func retry() {
        retrying = true
        Task {
            await root.retryInstanceConnection()
            retrying = false
        }
    }
}

#if !os(iOS)
/// A local browser can run without starting or installing Core.
struct StandaloneBrowserShell: View {
    let root: RootShellViewModel
    @State private var browser = BrowserWorkspaceState()
    @State private var showsAssistant = false

    var body: some View {
        BrowserWorkspaceView(state: browser, onAskAgent: { _ in showsAssistant = true },
            onCollect: { _ in showsAssistant = true }, onSettings: { root.presentSettings(.general) })
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Assistant", systemImage: "sidebar.right") { showsAssistant.toggle() }
                        .accessibilityIdentifier("browser-agent-toggle")
                }
            }
            .inspector(isPresented: $showsAssistant) {
                AgentConnectionStatusView(root: root, onConfigure: root.showConnectionSetup)
                    .inspectorColumnWidth(min: 320, ideal: 420, max: 600)
            }
            .onDisappear { browser.checkpoint() }
    }
}
#endif
