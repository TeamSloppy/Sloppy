import SwiftUI
#if os(macOS)
import SafariServices
#endif
#if canImport(UIKit)
import UIKit
#endif

public struct SettingsView: View {
    @State private var safariMessage: String?
    @AppStorage("sloppySafari.hasCompletedAgentSetupGuide") private var hasCompletedAgentSetupGuide = false
    @Environment(\.openURL) private var openURL

    public init(store: ConnectionSettingsStore) {
        _ = store
    }

    public var body: some View {
        NavigationStack {
            contentBody
            .navigationTitle("SloppySafari")
        #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .background(Color.black.ignoresSafeArea())
        #if os(macOS)
            .fixedSize(horizontal: false, vertical: true)
        #endif
        }
    #if os(macOS)
        .frame(minWidth: 420)
    #endif
    }

    @ViewBuilder
    private var contentBody: some View {
    #if canImport(UIKit)
        ScrollView {
            VStack(spacing: 24) {
                settingsContent
                settingsActionButtons
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    #else
        ZStack(alignment: .bottomTrailing) {
            settingsContent
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity, alignment: .leading)

            floatingActionButtons
        }
    #endif
    }

    private var settingsContent: some View {
        VStack(spacing: 20) {
            Image("SloppyLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("SloppySafari")
                    .font(.largeTitle.bold())
                Text("Enable the Safari extension, then ask Sloppy from any page with the toolbar, floating button, or selected text menu.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !hasCompletedAgentSetupGuide {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Agent required")
                        .font(.headline)
                    Text("SloppySafari works only when a Sloppy Agent is running locally. Install and start **sloppy** first, then connect the extension to the core API.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Setup steps:")
                            .font(.subheadline.bold())
                        Text("1. Download and install Sloppy Agent.")
                        Text("2. Launch Sloppy and keep the core API enabled.")
                        Text("3. Use the core URL `http://127.0.0.1:25101` (default).")
                        Text("4. Open Safari extension settings and ensure it can access this agent.")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    Button {
                        hasCompletedAgentSetupGuide = true
                    } label: {
                        Text("I understand, continue")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }

            if let safariMessage {
                Text(safariMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var settingsActionButtons: some View {
        VStack(spacing: 10) {
            Button {
                openDownloadPage()
            } label: {
                Label("Download Sloppy", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)

            Button {
                openExtensionSettings()
            } label: {
                Label("Open Extension Settings", systemImage: "safari.fill")
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    private var floatingActionButtons: some View {
        settingsActionButtons
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 8)
        .padding([.trailing, .bottom], 16)
    }

    private func openDownloadPage() {
        if let url = URL(string: "https://sloppy.team") {
            openURL(url)
        }
    }

    private func openExtensionSettings() {
    #if os(macOS)
        SFSafariApplication.showPreferencesForExtension(
            withIdentifier: "team.sloppy.sloppysafari.webextension"
        ) { error in
            Task { @MainActor in
                withAnimation {
                    if let error {
                        safariMessage = (error as NSError).localizedDescription
                    } else {
                        safariMessage = "Opened Safari Extensions"
                    }
                }
            }
        }
    #elseif canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    #endif
    }
}
