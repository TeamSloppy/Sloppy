#if os(macOS)
import SwiftUI
import SloppyClientUI
import SloppyFeatureChat

@MainActor
struct WorkspaceBrowserAnnotationOverlay: View {
    @Bindable var model: WorkspaceBrowserAnnotations
    let draft: WorkspaceBrowserAnnotations.Draft
    @Environment(\.theme) private var theme
    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let frame = ChatImageRegion.imageFrame(imageSize: draft.image.size, canvasSize: geometry.size)
            let region = draft.element.region
            let selected = CGRect(x: frame.minX + region.x * frame.width, y: frame.minY + region.y * frame.height,
                                  width: region.width * frame.width, height: region.height * frame.height)
            let width = min(300, max(160, geometry.size.width - 24))
            let x = min(max(12, selected.minX), max(12, geometry.size.width - width - 12))
            let y = min(selected.maxY + 10, max(12, geometry.size.height - 260))
            ZStack(alignment: .topLeading) {
                theme.colors.surface
                    .contentShape(Rectangle()).onTapGesture { isFocused = false }
                Image(nsImage: draft.image).resizable()
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .allowsHitTesting(false).accessibilityHidden(true)
                Rectangle().fill(.blue.opacity(0.08))
                    .overlay { Rectangle().strokeBorder(.blue, lineWidth: 2) }
                    .frame(width: selected.width, height: selected.height)
                    .offset(x: selected.minX, y: selected.minY)
                    .allowsHitTesting(false)
                ScrollView { editor }
                    .frame(width: width, height: min(260, max(80, geometry.size.height - 24)))
                    .offset(x: x, y: y)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .task(id: draft.id) {
            await Task.yield()
            isFocused = true
        }
        .onExitCommand { model.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace-browser-annotation-editor")
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Annotate <\(draft.element.tag)>").font(.caption.weight(.semibold))
            if !draft.element.elementID.isEmpty {
                Text("id: \(draft.element.elementID)").font(.caption.monospaced()).lineLimit(1)
            }
            if !draft.element.classNames.isEmpty {
                Text("class: \(draft.element.classNames.joined(separator: " "))")
                    .font(.caption.monospaced()).lineLimit(2)
            }
            Text(draft.element.selector).font(.caption.monospaced())
                .foregroundStyle(theme.colors.textMuted).lineLimit(2)
            TextField("Add a comment…", text: Binding(
                get: { model.draft?.comment ?? "" }, set: { model.draft?.comment = $0 }), axis: .vertical)
                .lineLimit(2...4).textFieldStyle(.plain).focused($isFocused)
                .accessibilityIdentifier("workspace-browser-annotation-comment")
            HStack {
                Button("Cancel") { model.cancel() }.buttonStyle(.plain)
                Spacer()
                Button("Add to chat") { model.save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.draft?.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
                    .accessibilityIdentifier("workspace-browser-annotation-save")
            }
            .font(.caption)
        }
        .padding(14)
        .foregroundStyle(theme.colors.textPrimary)
        .background(theme.colors.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(theme.colors.borderBold, lineWidth: 1) }
    }
}
#endif
