import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var store: ConnectionSettingsStore

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
                Button("Save") {
                    store.save()
                }
            }

            Section("Safari") {
                Text("Enable SafariExtension in Safari settings, then open a page, select text, and use the toolbar item.")
                    .font(.callout)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 260)
    }
}
