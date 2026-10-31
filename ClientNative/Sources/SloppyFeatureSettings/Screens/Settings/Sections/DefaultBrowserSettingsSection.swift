import SwiftUI
import SloppyClientCore
import SloppyClientUI

#if os(macOS) || os(iOS)
struct DefaultBrowserSettingsSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isDefault = false
    @State private var isRequesting = false
    @State private var errorText: String?

    var body: some View {
        SettingsSectionCard("Default browser") {
            VStack(alignment: .leading, spacing: 12) {
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    isRequesting = true
                    errorText = nil
                    Task { @MainActor in
                        defer { isRequesting = false }
                        do { try await DefaultBrowserSystem.requestDefault() }
                        catch { errorText = error.localizedDescription }
                        refreshStatus()
                    }
                } label: {
                    Label(buttonTitle, systemImage: isDefault ? "checkmark.circle" : "globe")
                }
                .buttonStyle(.bordered)
                .disabled(isRequesting || isDefault)
                .accessibilityIdentifier("settings.default-browser")
                if let errorText {
                    Text(errorText)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.default-browser.error")
                }
            }
            .padding(16)
        }
        .task { refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshStatus() }
        }
    }

    private var description: String {
        #if os(macOS)
        isDefault ? "Links from other apps open in Sloppy." : "Open web links from other apps in Sloppy. macOS will ask you to confirm your choice."
        #else
        "Choose Sloppy under Default Browser App in system settings to open links from other apps here."
        #endif
    }

    private var buttonTitle: String {
        #if os(macOS)
        isDefault ? "Sloppy is your default browser" : "Make Default"
        #else
        "Open Default Browser Settings"
        #endif
    }

    private func refreshStatus() {
        #if os(macOS)
        isDefault = DefaultBrowserSystem.isDefault
        #endif
    }
}
#endif
