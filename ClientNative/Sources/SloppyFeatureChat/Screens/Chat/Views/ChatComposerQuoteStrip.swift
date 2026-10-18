import SwiftUI
import SloppyClientUI

struct ChatComposerQuoteStrip: View {
    let quotes: [ChatComposerQuote]
    let update: @MainActor (ChatComposerQuote.ID, String) -> Void
    let remove: @MainActor (ChatComposerQuote.ID) -> Void
    var edit: @MainActor (UUID) -> Bool = { _ in false }
    var finish: @MainActor (UUID) -> Void = { _ in }
#if os(macOS)
    @State private var editingID: UUID?
    @Environment(\.theme) private var theme
#endif

    @FocusState private var focusedID: UUID?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
#if os(macOS)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(quotes.enumerated()), id: \.element.id) { number, quote in
                    HStack(spacing: 8) {
                        Button {
                            if !edit(quote.id) { editingID = quote.id }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "quote.opening")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Annotation \(number + 1)").font(.caption.weight(.semibold))
                                    Text(quote.comment.isEmpty ? quote.text : quote.comment)
                                        .font(.caption).foregroundStyle(theme.colors.textSecondary).lineLimit(1)
                                }
                            }
                            .frame(maxWidth: 230, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit annotation \(number + 1)")
                        .accessibilityIdentifier("chat.composer.annotation.\(quote.id).edit")
                        .popover(isPresented: Binding(get: { editingID == quote.id }, set: { if !$0 { editingID = nil } })) {
                            ChatQuoteAnnotationEditor(quote: quote, update: { update(quote.id, $0) }, done: { editingID = nil })
                                .onDisappear { finish(quote.id) }
                        }
                        Button { remove(quote.id) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove annotation \(number + 1)")
                    }
                    .padding(10)
                    .foregroundStyle(theme.colors.textPrimary)
                    .background(theme.colors.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(theme.colors.border, lineWidth: 1) }
                }
            }
        }
        .accessibilityIdentifier("chat.composer.quotes")
        .onChange(of: quotes.map(\.id)) { old, new in
            if new.count > old.count, let quote = quotes.last, quote.source == nil {
                _ = edit(quote.id)
                editingID = quote.id
            }
        }
#else
        editableCards
#endif
    }

    private var editableCards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(quotes.enumerated()), id: \.element.id) { number, quote in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Annotation \(number + 1)", systemImage: "quote.opening")
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Button { remove(quote.id) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove annotation \(number + 1)")
                            }
                            Text(quote.text).font(.caption).lineLimit(2)
                            Divider()
                            TextField("Add a comment…", text: Binding(
                                get: { quote.comment }, set: { update(quote.id, $0) }
                            ), axis: .vertical)
                                .font(.callout)
                                .lineLimit(1...3)
                                .textFieldStyle(.plain)
                                .focused($focusedID, equals: quote.id)
                                .accessibilityLabel("Comment for annotation \(number + 1)")
                                .accessibilityIdentifier("chat.composer.annotation.\(quote.id).comment")
                        }
                        .id(quote.id)
                        .padding(12)
                        .frame(width: 280, alignment: .topLeading)
                        .foregroundStyle(ChatAnnotationStyle.foreground(colorScheme))
                        .background(ChatAnnotationStyle.background(colorScheme), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .frame(maxHeight: 164)
            .accessibilityIdentifier("chat.composer.quotes")
            .onChange(of: quotes.last?.id) { _, id in
                if let id { proxy.scrollTo(id, anchor: .trailing) }
                focusedID = id
            }
            .onAppear {
                if let id = quotes.last?.id { proxy.scrollTo(id, anchor: .trailing) }
                focusedID = quotes.last?.id
            }
        }
    }
}
