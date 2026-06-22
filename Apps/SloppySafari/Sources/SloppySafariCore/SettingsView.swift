import SwiftUI
#if os(macOS)
import SafariServices
#endif
#if canImport(UIKit)
import UIKit
#endif

public struct SettingsView: View {
    @State private var safariMessage: String?
    @Environment(\.openURL) private var openURL

    public init(store: ConnectionSettingsStore) {
        _ = store
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 26) {
                Spacer(minLength: 24)

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

                VStack(spacing: 12) {
                    Button {
                        openDownloadPage()
                    } label: {
                        Label("Download Sloppy", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        openExtensionSettings()
                    } label: {
                        Label("Open Extension Settings", systemImage: "safari.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .frame(maxWidth: 360)

                if let safariMessage {
                    Text(safariMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("SloppySafari")
#if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .background(Color.black.ignoresSafeArea())
        }
#if os(macOS)
        .frame(minWidth: 420, minHeight: 460)
#endif
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
