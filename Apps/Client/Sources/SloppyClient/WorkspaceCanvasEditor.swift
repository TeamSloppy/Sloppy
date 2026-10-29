import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct WorkspaceCanvasEditor: View {
    let model: WorkspaceCanvasModel
    let onOpenChat: @MainActor @Sendable () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    WorkspaceAction(title: "Canvases", icon: .folder) { model.close() }.disabled(model.isSaving)
                    Text(model.workspace?.title ?? "Canvas").font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    WorkspaceIconButton(icon: .refresh) { if let workspace = model.workspace { Task { await model.open(workspace) } } }.disabled(model.isSaving)
                    WorkspaceAction(title: "Ask agent", icon: .chatAddOn, action: onOpenChat).disabled(model.isSaving)
                    Spacer()
                    Text(model.isSaving ? "Saving…" : "Revision \(model.document?.revision ?? 0)").font(.system(size: 11))
                    WorkspaceAction(title: "−") { model.zoom = max(0.25, model.zoom - 0.25) }
                    Text("\(Int(model.zoom * 100))%").font(.system(size: 12))
                    WorkspaceAction(title: "+") { model.zoom = min(2, model.zoom + 0.25) }
                }.padding(12).frame(height: 56)
                ScrollView(.horizontal, respectsSafeArea: false) {
                    HStack(spacing: 8) {
                        ForEach([CanvasWorkspaceElementKind.sticky, .text, .shape, .frame], id: \.self) { kind in
                            WorkspaceAction(title: "Add \(kind.rawValue)", icon: .add) { Task { await model.add(kind) } }.disabled(model.isSaving || model.document == nil)
                        }
                    }.padding(.horizontal, 12)
                }.frame(height: 42)
                if let error = model.error { Text(error).font(.system(size: 12)).foregroundColor(theme.colors.statusBlocked).padding(12) }
                if model.isLoading { Text("Loading canvas…").padding(18) }
                HStack(alignment: .top, spacing: 0) {
                    ScrollView([.horizontal, .vertical], respectsSafeArea: false) {
                        ZStack(anchor: .topLeading) {
                            theme.colors.surface.frame(width: boardWidth, height: boardHeight)
                            ForEach((model.document?.elements ?? []).sorted { $0.zIndex < $1.zIndex }) { element in
                                CanvasElementCard(element: element, selected: model.selection == element.id,
                                    zoom: model.zoom, onSelect: { model.select(element) }, onMove: { dx, dy in
                                        Task { await model.move(element.id, dx: dx, dy: dy) }
                                    })
                                    .offset(x: Float(element.bounds.x * model.zoom), y: Float(element.bounds.y * model.zoom))
                            }
                        }.frame(width: boardWidth, height: boardHeight, alignment: .topLeading)
                    }.frame(width: max(100, geometry.size.width - (model.selected == nil ? 0 : 230)), height: max(100, geometry.size.height - 110))
                    if let element = model.selected { inspector(element).frame(width: 230) }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }.sloppyTextInputStyle(theme.colors).accessibilityIdentifier("workspace.canvas.editor")
    }
    private var boardWidth: Float { Float(max(1200, (model.document?.elements.map { $0.bounds.x + $0.bounds.width }.max() ?? 0) + 100) * model.zoom) }
    private var boardHeight: Float { Float(max(850, (model.document?.elements.map { $0.bounds.y + $0.bounds.height }.max() ?? 0) + 100) * model.zoom) }

    private func inspector(_ element: CanvasWorkspaceElement) -> some View {
        ScrollView(respectsSafeArea: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text(element.kind.rawValue.capitalized).font(.system(size: 16, weight: .semibold))
                Text("Text").font(.system(size: 12))
                TextEditor(text: Binding(get: { model.text }, set: { model.text = $0 }), showsLineNumbers: false, wrapsLines: true).font(.system(size: 13)).frame(height: 130)
                    .accessibilityIdentifier("workspace.canvas.text")
                coordinate("X", get: { model.x }, set: { model.x = $0 })
                coordinate("Y", get: { model.y }, set: { model.y = $0 })
                coordinate("Width", get: { model.width }, set: { model.width = $0 })
                coordinate("Height", get: { model.height }, set: { model.height = $0 })
                WorkspaceAction(title: "Save element", primary: true) { Task { await model.saveSelection() } }.disabled(model.isSaving)
                    .accessibilityIdentifier("workspace.canvas.save")
                WorkspaceAction(title: "Delete element") { Task { await model.deleteSelection() } }.disabled(model.isSaving)
            }.padding(14)
        }
    }
    private func coordinate(_ title: String, get: @escaping () -> String, set: @escaping (String) -> Void) -> some View {
        HStack {
            Text(title).font(.system(size: 12)).frame(width: 50, alignment: .leading)
            TextField(title, text: Binding(get: get, set: set)).font(.system(size: 13)).padding(.horizontal, 6).frame(height: 34).background(theme.colors.surfaceRaised)
        }
    }
}

private struct CanvasElementCard: View {
    let element: CanvasWorkspaceElement
    let selected: Bool
    let zoom: Double
    let onSelect: () -> Void
    let onMove: (Double, Double) -> Void
    @State private var translation = Size.zero
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(element.kind.rawValue.capitalized).font(.system(size: 10)).foregroundColor(theme.colors.textMuted)
                Spacer()
                Text("⠿").font(.system(size: 13)).foregroundColor(theme.colors.textMuted)
            }
            Text(markdown: element.title).textSelection(.disabled).font(.system(size: 14 * zoom)).lineLimit(10)
            Spacer(minLength: 0)
        }.padding(12).frame(width: Float(element.bounds.width * zoom), height: Float(element.bounds.height * zoom), alignment: .topLeading)
            .background { RoundedRectangle(cornerRadius: element.kind == .shape ? 40 : 6).fill(theme.colors.surfaceRaised) }
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(selected ? theme.colors.accentCyan : theme.colors.border, lineWidth: selected ? 2 : 1) }
            .offset(x: translation.width, y: translation.height)
            .onTapGesture(perform: onSelect)
            .gesture(DragGesture().onChanged { value in translation = value.translation }.onEnded { value in
                translation = .zero; onSelect(); onMove(Double(value.translation.width), Double(value.translation.height))
            })
            .accessibilityIdentifier("workspace.canvas.element.\(element.id)")
    }
}
