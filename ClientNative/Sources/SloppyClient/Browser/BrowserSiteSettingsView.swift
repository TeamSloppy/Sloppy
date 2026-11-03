import SwiftUI

@MainActor
struct BrowserSiteSettingsView: View {
    let url: URL
    let permissions: BrowserSitePermissions
    var page: WorkspaceWebViewModel? = nil
    @State private var reloadAfterClear = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let origin = BrowserSiteOrigin(url) {
                    Section {
                        Text(origin.id).font(.headline).textSelection(.enabled)
                        if url.scheme?.lowercased() == "http" {
                            Picker("Insecure HTTP", selection: Binding(
                                get: { permissions.decision(for: origin, resource: .http) },
                                set: { permissions.set($0, for: origin, resource: .http) }
                            )) {
                                ForEach(BrowserSiteDecision.allCases) { Text($0.title).tag($0) }
                            }
                            .accessibilityIdentifier("browser-site-http")
                        }
                        ForEach([BrowserSiteResource.camera, .microphone, .location]) { resource in
                            Picker(resource.title, selection: Binding(
                                get: { permissions.decision(for: origin, resource: resource) },
                                set: { permissions.set($0, for: origin, resource: resource) }
                            )) {
                                ForEach(BrowserSiteDecision.allCases) { Text($0.title).tag($0) }
                            }
                            .disabled(resource == .location && !BrowserGeolocationPermissions.isSupported)
                            .accessibilityIdentifier("browser-site-\(resource.rawValue)")
                        }
                        if !BrowserGeolocationPermissions.isSupported {
                            Text("Location access is managed by the system on this OS version.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("System privacy settings also apply. Resetting a permission stops active capture and asks again on the next request.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Reset permissions for this site") { permissions.reset(origin) }
                            .accessibilityIdentifier("browser-site-reset")
                    }
                    BrowserSiteDataSection(url: url, page: page) { reloadAfterClear = true }
#if os(macOS)
                    BrowserPasskeySection()
#endif
                    if !permissions.savedOrigins.isEmpty {
                        Section("Saved site permissions") {
                            ForEach(permissions.savedOrigins, id: \.self) { key in
                                HStack {
                                    Text(key).lineLimit(2)
                                    Spacer()
                                    Button("Reset") {
                                        if let url = URL(string: key), let saved = BrowserSiteOrigin(url) { permissions.reset(saved) }
                                    }
                                    .accessibilityLabel("Reset permissions for \(key)")
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Site Settings")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onDisappear {
            if reloadAfterClear, let page, page.currentURL.flatMap(BrowserSiteOrigin.init) == BrowserSiteOrigin(url) {
                page.reload()
            }
        }
#if os(macOS)
        .frame(minWidth: 480, minHeight: 500)
#endif
    }
}
