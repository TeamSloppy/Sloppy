import SwiftUI
import SloppyClientUI

@MainActor
public struct ChatRenameSheet: View {
    @State private var title: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isTitleFocused: Bool
    @Environment(\.dismiss) private var dismiss
    private let onSave: @MainActor (String) async throws -> Void

    public init(title: String, onSave: @escaping @MainActor (String) async throws -> Void) {
        _title = State(initialValue: title)
        self.onSave = onSave
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var body: some View {
        NavigationStack {
#if os(iOS)
            Form {
                Section("Chat name") {
                    TextField("Chat name", text: $title)
                        .focused($isTitleFocused)
                        .accessibilityIdentifier("chat.rename.title")
                        .onSubmit { save() }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .mobileScreenBackground()
            .navigationTitle("Rename Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(isSaving || trimmedTitle.isEmpty || trimmedTitle.count > 200)
                        .accessibilityIdentifier("chat.rename.save")
                }
            }
#else
            VStack(alignment: .leading, spacing: 16) {
                TextField("Chat name", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTitleFocused)
                    .accessibilityIdentifier("chat.rename.title")
                    .onSubmit { save() }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.callout)
                }
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .disabled(isSaving)
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving || trimmedTitle.isEmpty || trimmedTitle.count > 200)
                        .accessibilityIdentifier("chat.rename.save")
                }
            }
            .padding(24)
            .navigationTitle("Rename Chat")
            #if os(macOS)
            .frame(width: 380)
            #else
            .navigationBarTitleDisplayMode(.inline)
            #endif
#endif
        }
        .interactiveDismissDisabled(isSaving)
#if os(iOS)
        .presentationDetents([.medium])
#else
        .presentationDetents([.height(220)])
#endif
        .onAppear { isTitleFocused = true }
    }

    private func save() {
        guard !isSaving, !trimmedTitle.isEmpty, trimmedTitle.count <= 200 else { return }
        let newTitle = trimmedTitle
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await onSave(newTitle)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
