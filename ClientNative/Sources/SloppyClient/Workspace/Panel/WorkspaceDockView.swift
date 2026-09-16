import SwiftUI
import SloppyClientUI

@MainActor
struct WorkspaceDockView<Content: View>: View {
    @Bindable var state: WorkspaceDockState
    let onOpen: @MainActor @Sendable (WorkspaceSidePanelItem) -> Void
    @ViewBuilder let content: (WorkspaceDockTab) -> Content
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 3) {
                            ForEach(state.tabs) { tab in
                                HStack(spacing: 4) {
                                    Button { state.select(tab) } label: {
                                        Label(tab.title, systemImage: tab.kind.systemImage)
                                            .font(.system(size: 12, weight: state.selectedID == tab.id ? .semibold : .regular))
                                            .lineLimit(1)
                                            .padding(.leading, 10)
                                            .padding(.vertical, 9)
                                    }
                                    .accessibilityIdentifier("workspace.dock.tab.\(tab.kind.rawValue).\(tab.number)")
                                    .accessibilityAddTraits(state.selectedID == tab.id ? .isSelected : [])
                                    Button { state.close(tab.id) } label: {
                                        Image(systemName: "xmark").font(.system(size: 9, weight: .medium))
                                            .frame(width: 24, height: 28)
                                            .contentShape(Rectangle())
                                    }
                                    .help("Close \(tab.title)")
                                    .accessibilityLabel("Close \(tab.title)")
                                }
                                .foregroundStyle(state.selectedID == tab.id ? theme.colors.textPrimary : theme.colors.textSecondary)
                                .background(state.selectedID == tab.id ? theme.colors.surfaceRaised : .clear,
                                            in: RoundedRectangle(cornerRadius: 7))
                                .id(tab.id)
                            }
                        }
                    }
                    .onChange(of: state.selectedID) { _, id in
                        if let id {
                            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .trailing) }
                        }
                    }
                }
                Menu {
                    ForEach(WorkspaceSidePanelItem.allCases) { kind in
                        Button { onOpen(kind) } label: { Label(kind.title, systemImage: kind.systemImage) }
                            .disabled(kind.requiresProject && state.context == nil)
                    }
                } label: { Image(systemName: "plus").frame(width: 28, height: 30) }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("New panel tab")
                .accessibilityIdentifier("workspace.dock.add-tab")

            }
            .buttonStyle(.plain)
            .padding(6)
            Divider()
            if let tab = state.selectedTab {
                content(tab)
                    .id(tab.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                WorkspaceSidePanelPickerView(hasProject: state.context != nil, onSelect: onOpen)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.colors.surface)
        .accessibilityIdentifier("workspace.dock")
    }
}

#if os(macOS)
import AppKit

@MainActor
struct WorkspaceResizableSidePanel<Content: View, Panel: View>: View {
    @Bindable var state: WorkspaceDockState
    @ViewBuilder let content: () -> Content
    @ViewBuilder let panel: () -> Panel
    @State private var dragStart: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let width = WorkspaceDockState.visibleWidth(preferred: state.preferredWidth, available: geometry.size.width)
            HStack(spacing: 0) {
                content()
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                if state.isPresented {
                    panel().frame(width: width).frame(maxHeight: .infinity).clipped()
                        .overlay(alignment: .leading) {
                            WorkspacePanelResizeHandle { translation in
                                let start = dragStart ?? width
                                dragStart = start
                                state.preferredWidth = WorkspaceDockState.visibleWidth(
                                    preferred: start - translation, available: geometry.size.width)
                            } onEnd: {
                                dragStart = nil
                            }
                            .frame(width: 12)
                            .offset(x: -6)
                            .accessibilityLabel("Resize side panel")
                            .accessibilityIdentifier("workspace.dock.resize")
                            .accessibilityValue("\(Int(width)) points")
                            .accessibilityAdjustableAction { direction in
                                state.preferredWidth = WorkspaceDockState.visibleWidth(
                                    preferred: width + (direction == .increment ? 40 : -40), available: geometry.size.width)
                            }
                        }
                        .transition(reduceMotion ? .identity : .move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: state.isPresented)
        }
    }
}

/// Captures the drag in AppKit so crossing into a WKWebView cannot steal it.
struct WorkspacePanelResizeHandle: NSViewRepresentable {
    let onDrag: @MainActor (CGFloat) -> Void
    let onEnd: @MainActor () -> Void

    func makeNSView(context: Context) -> WorkspacePanelResizeView {
        let view = WorkspacePanelResizeView()
        view.onDrag = onDrag
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ view: WorkspacePanelResizeView, context: Context) {
        view.onDrag = onDrag
        view.onEnd = onEnd
    }
}

final class WorkspacePanelResizeView: NSView {
    var onDrag: (@MainActor (CGFloat) -> Void)?
    var onEnd: (@MainActor () -> Void)?
    private var startX: CGFloat?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.midX, y: 0, width: 1, height: bounds.height).fill()
    }
    override func mouseDown(with event: NSEvent) {
        startX = event.locationInWindow.x
        onDrag?(0)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let startX else { return }
        onDrag?(event.locationInWindow.x - startX)
    }
    override func mouseUp(with event: NSEvent) {
        if let startX { onDrag?(event.locationInWindow.x - startX) }
        startX = nil
        onEnd?()
    }
}

#Preview {
    WorkspaceResizableSidePanel(state: .init()) {
        Color.red
    } panel: {
        Color.blue
    }

}
#endif
