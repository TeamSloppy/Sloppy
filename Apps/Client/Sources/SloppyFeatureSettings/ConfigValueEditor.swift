import Foundation
import AdaEngine
import SloppyClientCore
import SloppyClientUI

/// The same Codable models as Native back these forms; JSON mode covers nested collections.
struct ConfigValueEditor<Value: Codable & Sendable>: View {
    let initialValue: Value
    let onSave: (Value) -> Void
    @State private var value: ConfigJSONValue = .null
    @State private var json = ""
    @State private var usesJSON = false
    @State private var error: String?
    @Environment(\.theme) private var theme

    init(_ value: Value, onSave: @escaping (Value) -> Void) {
        initialValue = value
        self.onSave = onSave
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(usesJSON ? "Form" : "Edit JSON") {
                    if !usesJSON { json = value.formatted }
                    else if let parsed = try? JSONDecoder().decode(ConfigJSONValue.self, from: Data(json.utf8)) { value = parsed }
                    usesJSON.toggle()
                }
                Spacer()
                Button("Reset") { reset() }
            }
            if usesJSON {
                TextEditor(text: $json, showsLineNumbers: true).font(.system(size: 13)).frame(height: 420)
            } else {
                JSONSettingsFields(value: Binding(get: { value }, set: { value = $0 }))
            }
            if let error { Text(error).font(.system(size: 12)).foregroundColor(theme.colors.statusBlocked) }
            Button("Save changes") {
                do {
                    let updated = usesJSON ? try JSONDecoder().decode(ConfigJSONValue.self, from: Data(json.utf8)) : value
                    let decoded = try updated.decoded(Value.self)
                    error = nil
                    onSave(decoded)
                } catch { self.error = error.localizedDescription }
            }.foregroundColor(theme.colors.accent).frame(height: 36)
        }.onAppear { reset() }
    }
    private func reset() {
        value = (try? .encoded(initialValue)) ?? .null
        json = value.formatted
        error = nil
    }
}

private struct JSONSettingsFields: View {
    let value: Binding<ConfigJSONValue>
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .object(let object) = value.wrappedValue {
                ForEach(object.keys.sorted(), id: \.self) { key in
                    field(key, Binding(get: {
                        if case .object(let current) = value.wrappedValue { return current[key] ?? .null }
                        return .null
                    }, set: { updated in
                        if case .object(var current) = value.wrappedValue { current[key] = updated; value.wrappedValue = .object(current) }
                    }))
                }
            } else { JSONCollectionEditor(value: value) }
        }
    }
    private func field(_ key: String, _ binding: Binding<ConfigJSONValue>) -> AnyView {
        let title = key.reduce(into: "") { text, letter in
            if letter.isUppercase { text += " " }
            text.append(letter)
        }.capitalized
        switch binding.wrappedValue {
        case .bool(let flag):
            return AnyView(SettingsToggleRow(label: title, value: flag) { binding.wrappedValue = .bool(!flag) })
        case .string:
            return AnyView(SettingsFieldRow(title, text: Binding(get: {
                if case .string(let text) = binding.wrappedValue { return text }; return ""
            }, set: { binding.wrappedValue = .string($0) })))
        case .number:
            return AnyView(SettingsFieldRow(title, text: Binding(get: {
                if case .number(let number) = binding.wrappedValue { return number.rounded() == number ? String(format: "%.0f", number) : String(number) }; return ""
            }, set: { if let number = Double($0), number.isFinite { binding.wrappedValue = .number(number) } })))
        case .object:
            return AnyView(SettingsSectionCard(title) { JSONSettingsFields(value: binding).padding(12) })
        default:
            return AnyView(SettingsSectionCard(title) { JSONCollectionEditor(value: binding).padding(12) })
        }
    }
}

private struct JSONCollectionEditor: View {
    let value: Binding<ConfigJSONValue>
    @State private var draft = ""
    @State private var error: String?
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $draft, showsLineNumbers: true).font(.system(size: 12)).frame(height: 180)
            Button("Apply collection") {
                do { value.wrappedValue = try JSONDecoder().decode(ConfigJSONValue.self, from: Data(draft.utf8)); error = nil }
                catch { self.error = error.localizedDescription }
            }
            if let error { Text(error).font(.system(size: 11)).foregroundColor(theme.colors.statusBlocked) }
        }.onAppear { draft = value.wrappedValue.formatted }
    }
}
