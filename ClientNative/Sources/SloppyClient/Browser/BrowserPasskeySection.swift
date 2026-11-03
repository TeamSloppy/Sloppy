#if os(macOS)
import SwiftUI

@MainActor
struct BrowserPasskeySection: View {
    @State private var access = BrowserPasskeyAccess()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section("Passkeys") {
            switch access.authorization {
            case .unavailable:
                Text("Passkeys are unavailable in this build of Sloppy.")
                Text("Use another sign-in method on this site. A browser update is required to enable passkeys.")
                    .font(.caption).foregroundStyle(.secondary)
            case .notDetermined:
                Button("Allow Sloppy to use passkeys…") {
                    Task { await access.requestAccess() }
                }
                .disabled(access.isRequesting)
                .accessibilityIdentifier("browser-passkey-request-access")
            case .authorized:
                Label("Passkey access allowed", systemImage: "checkmark.circle")
                Text("Retry passkey sign-in on the website. Your password manager handles credential selection and verification.")
                    .font(.caption).foregroundStyle(.secondary)
            case .denied:
                Text("Passkey access is disabled for Sloppy.")
                Text("Allow access in System Settings → Privacy & Security → Passkeys Access for Web Browsers, then retry sign-in.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if access.isRequesting { ProgressView().controlSize(.small) }
        }
        .accessibilityIdentifier("browser-passkey-access")
        .task { access.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { access.refresh() }
        }
    }
}
#endif
