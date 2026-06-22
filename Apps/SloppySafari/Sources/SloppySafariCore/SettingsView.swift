import SwiftUI
#if os(macOS)
import SafariServices
#endif

public struct SettingsView: View {
    @ObservedObject private var store: ConnectionSettingsStore
    @State private var saveMessage: String?
    @State private var safariMessage: String?

    public init(store: ConnectionSettingsStore) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("Sloppy Core") {
                TextField("Core URL", text: $store.settings.coreURLString)
#if os(iOS) || os(visionOS)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled()
                SecureField("Auth token", text: $store.settings.authToken)
                TextField("Default agent", text: $store.settings.defaultAgentID)
#if os(iOS) || os(visionOS)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled()
                HStack {
                    Button("Save") {
                        save()
                    }
                    if let saveMessage {
                        Text(saveMessage)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
            }

            Section("Safari") {
                Text("Enable SloppySafari in Safari settings, then open a page, select text, and use the toolbar item.")
                    .font(.callout)
#if os(macOS)
                HStack {
                    Button("Open Safari Extensions") {
                        openSafariExtensions()
                    }
                    if let safariMessage {
                        Text(safariMessage)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
#endif
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 260)
    }

    private func save() {
        store.save()
        withAnimation {
            saveMessage = "Saved"
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation {
                    saveMessage = nil
                }
            }
        }
    }

#if os(macOS)
    private func openSafariExtensions() {
        SFSafariApplication.showPreferencesForExtension(
            withIdentifier: "team.sloppy.sloppysafari.webextension"
        ) { error in
            Task { @MainActor in
                withAnimation {
                    if let error {
                        safariMessage = (error as NSError).description
                    } else {
                        safariMessage = "Opened Safari Extensions"
                    }
                }
            }
        }
    }
#endif
}
