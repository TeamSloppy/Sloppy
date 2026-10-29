import AdaEngine
import Observation
import SloppyClientCore
import SloppyClientUI

@Observable
@MainActor
public final class ChatComposerDraft {
    public var text: String
    public init(text: String = "") { self.text = text }
}

public struct ChatComposerView: View {
    public static let panelWidth: Float = 900
    public static let panelHeight: Float = 52
    public static let phonePanelHeight: Float = 60
    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme
    public let draft: ChatComposerDraft
    public let agentName: String
    public let isSending: Bool
    public let onSend: (String) -> Void
    private let api: SloppyAPIClient?
    private let agentID: String?
    private let projectID: String?
    @State private var completions = ChatComposerSuggestionModel()
    @State private var cursor: Int?

    public init(draft: ChatComposerDraft, agentName: String = "Agent", isSending: Bool = false,
                api: SloppyAPIClient? = nil, agentID: String? = nil, projectID: String? = nil, onSend: @escaping (String) -> Void) {
        self.draft = draft
        self.agentName = agentName
        self.isSending = isSending
        self.onSend = onSend
        self.api = api
        self.agentID = agentID
        self.projectID = projectID
    }

    public var body: some View {
        VStack(spacing: 8) {
            ComposerSuggestionsPanel(model: completions, onSelect: apply)
            inputBar
        }
        .frame(maxWidth: Self.panelWidth)
        .onChange(of: draft.text) { old, new in
            cursor = ChatComposerTextEdit.cursorOffsetAfterEdit(from: old, to: new)
            updateSuggestions()
        }
        .onChange(of: projectID) { _, _ in completions.dismiss() }
        .onChange(of: agentID) { _, _ in completions.dismiss() }
        .onDisappear { completions.dismiss() }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button { insertTrigger("/") } label: {
                Text("/").font(.system(size: 18)).foregroundColor(theme.colors.textMuted).frame(width: 24, height: 32)
            }.accessibilityIdentifier("chat.composer.commands")
            Button { insertTrigger("@") } label: {
                Text("@").font(.system(size: 18)).foregroundColor(theme.colors.textMuted).frame(width: 24, height: 32)
            }.accessibilityIdentifier("chat.composer.files")
            TextField("Ask \(agentName.isEmpty ? "Sloppy" : agentName) or type / for commands", text: Binding(
                get: { draft.text }, set: { draft.text = $0 }
            ), onSubmit: submit)
            .onCaretChange { offset in
                guard cursor != offset else { return }
                cursor = offset
                updateSuggestions()
            }
            .onKeyPress { event in
                guard event.status == .down else { return false }
                switch event.keyCode {
                case .arrowUp: return completions.selection.move(.previous, in: completions.suggestions)
                case .arrowDown: return completions.selection.move(.next, in: completions.suggestions)
                case .tab, .enter:
                    guard let item = completions.selection.selectedSuggestion(in: completions.suggestions) else { return false }
                    apply(item)
                    return true
                case .escape:
                    completions.dismiss()
                    return true
                default: return false
                }
            }
            .font(.system(size: 15))
            .foregroundColor(theme.colors.textPrimary)
            .accentColor(theme.colors.accent)
            .textFieldStyle(PlainTextFieldStyle())
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("chat.composer.input")
            Button(action: submit) {
                Icons.symbol(isSending ? .moreHoriz : .arrowUpward, size: 20)
                    .foregroundColor(theme.colors.background)
                    .frame(width: 32, height: 32)
                    .background { Circle().fill(theme.colors.accent) }
            }
            .disabled(isSending || draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("chat.composer.send")
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.panelHeight(for: idiom))
        .background {
            RoundedRectangle(cornerRadius: 20).fill(theme.colors.surfaceRaised)
        }
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(theme.colors.borderBold, lineWidth: 1) }
        .frame(maxWidth: Self.panelWidth)
    }

    private func updateSuggestions() {
        guard let api else { return }
        completions.update(text: draft.text, cursor: cursor, agentID: agentID, projectID: projectID, api: api)
    }
    private func apply(_ item: ChatComposerSuggestion) {
        draft.text = completions.apply(item, text: draft.text)
    }
    private func insertTrigger(_ trigger: String) {
        draft.text += (draft.text.isEmpty || draft.text.last?.isWhitespace == true ? "" : " ") + trigger
    }

    public static func panelHeight(for idiom: UserInterfaceIdiom) -> Float {
        idiom == .phone ? phonePanelHeight : panelHeight
    }

    private func submit() {
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSending, !text.isEmpty else { return }
        onSend(text)
        draft.text = ""
        completions.dismiss()
    }
}

private struct ComposerSuggestionsPanel: View {
    let model: ChatComposerSuggestionModel
    let onSelect: (ChatComposerSuggestion) -> Void
    @Environment(\.theme) private var theme
    var body: some View {
        if !model.suggestions.isEmpty || model.isLoading || model.error?.isEmpty == false {
            VStack(alignment: .leading, spacing: 3) {
                if model.isLoading { Text("Searching…").font(.system(size: 12)).padding(8) }
                if let error = model.error, !error.isEmpty {
                    Text(error).font(.system(size: 11)).foregroundColor(theme.colors.statusWarning).lineLimit(2).padding(8)
                }
                ScrollView(respectsSafeArea: false) {
                    VStack(spacing: 2) {
                        ForEach(model.suggestions) { item in
                            Button { onSelect(item) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Text(item.subtitle).font(.system(size: 11)).foregroundColor(theme.colors.textMuted).lineLimit(1)
                                }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
                                    .background { RoundedRectangle(cornerRadius: 8).fill(model.selection.selectedID == item.id ? theme.colors.surfaceRaised : .clear) }
                            }.accessibilityIdentifier("chat.suggestion.\(item.id)")
                        }
                    }
                }.frame(height: min(240, Float(model.suggestions.count) * 52))
                Text("Up / Down to navigate · Tab or Enter to insert · Esc to close").font(.system(size: 10)).foregroundColor(theme.colors.textMuted).padding(8)
            }.foregroundColor(theme.colors.textPrimary).padding(6).background { RoundedRectangle(cornerRadius: 14).fill(theme.colors.surface) }
                .shadow(color: .black.opacity(0.25 as Float), radius: 12, y: 6, shape: .roundedRectangle(cornerRadius: 14))
        }
    }
}
