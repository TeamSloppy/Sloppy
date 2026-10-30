#if os(macOS)
import SwiftUI
import SloppyClientUI

@MainActor
struct BrowserExtensionsSheet: View {
    @Bindable var extensions: BrowserExtensions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Add a Safari Web Extension app or an unpacked extension folder. Choose its browser permissions and website access below, then enable the extension.")
                        .foregroundStyle(.secondary)
                    Text("Safari’s permissions are managed separately. Some extensions require a companion app or browser features Sloppy does not support.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Reload a page after changing extension access.").font(.caption).foregroundStyle(.secondary)
                    Button("Add Web Extension…", systemImage: "plus") {
                        Task { await extensions.chooseImport() }
                    }
                    .disabled(extensions.isImporting)
                    .accessibilityIdentifier("browser-extension-import")
                }
                ForEach(extensions.records) { record in
                    Section {
                        Toggle(isOn: Binding(get: {
                            extensions.records.first { $0.id == record.id }?.enabled ?? false
                        }, set: { extensions.setEnabled($0, id: record.id) })) {
                            VStack(alignment: .leading) {
                                Text(record.name).fontWeight(.medium)
                                Text(record.version).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(extensions.contexts[record.id] == nil)
                        .accessibilityIdentifier("browser-extension-enabled-\(record.id)")
                        DisclosureGroup("Browser permissions") {
                            if record.permissions.isEmpty { Text("No browser permissions requested.").foregroundStyle(.secondary) }
                            ForEach(record.permissions, id: \.self) { permission in
                                permissionToggle(permission, record: record, website: false)
                            }
                        }
                        DisclosureGroup("Website access") {
                            if record.sites.isEmpty { Text("No website access requested.").foregroundStyle(.secondary) }
                            ForEach(record.sites, id: \.self) { site in
                                permissionToggle(site, record: record, website: true)
                            }
                        }
                        if let error = extensions.errors[record.id] {
                            Text(error).foregroundStyle(.red).textSelection(.enabled)
                        }
                        Button("Remove extension", role: .destructive) { extensions.remove(record.id) }
                    }
                }
                if extensions.records.isEmpty {
                    ContentUnavailableView("No extensions", systemImage: "puzzlepiece.extension",
                                           description: Text("Add a compatible Safari Web Extension to get started."))
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Web Extensions")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Couldn’t add extension", isPresented: Binding(get: { extensions.lastError != nil }, set: {
                if !$0 { extensions.lastError = nil }
            })) { Button("OK") { extensions.lastError = nil } } message: { Text(extensions.lastError ?? "") }
        }
        .frame(width: 560, height: 580)
        .task { await extensions.restore() }
    }

    private func permissionToggle(_ value: String, record: BrowserExtensionRecord, website: Bool) -> some View {
        Toggle(value == "<all_urls>" ? "All websites" : value, isOn: Binding(get: {
            guard let current = extensions.records.first(where: { $0.id == record.id }) else { return false }
            return (website ? current.allowedSites : current.allowedPermissions).contains(value)
        }, set: { extensions.setPermission(value, allowed: $0, id: record.id, website: website) }))
        .font(.callout)
    }
}
#endif
