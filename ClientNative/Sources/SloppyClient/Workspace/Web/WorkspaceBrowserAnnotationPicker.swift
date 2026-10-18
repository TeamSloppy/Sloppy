#if os(macOS)
import AppKit
import SwiftUI

@MainActor
struct WorkspaceBrowserAnnotationPicker: View {
    let model: WorkspaceBrowserAnnotations

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                BrowserAnnotationPointerInput(model: model)
                if let element = model.hovered {
                    Rectangle().fill(.blue.opacity(0.08))
                        .overlay { Rectangle().strokeBorder(.blue, lineWidth: 2) }
                        .frame(width: element.width * geometry.size.width, height: element.height * geometry.size.height)
                        .offset(x: element.x * geometry.size.width, y: element.y * geometry.size.height)
                        .allowsHitTesting(false)
                    Text("\(element.tag) · \(Int(element.width * geometry.size.width)) × \(Int(element.height * geometry.size.height))")
                        .font(.system(size: 12)).foregroundStyle(.white).padding(6)
                        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 5))
                        .offset(x: max(4, min(element.x * geometry.size.width, geometry.size.width - 180)),
                                y: max(4, element.y * geometry.size.height - 30))
                        .allowsHitTesting(false)
                }
            }
        }
        .accessibilityLabel("Select an element to annotate")
    }
}

private struct BrowserAnnotationPointerInput: NSViewRepresentable {
    let model: WorkspaceBrowserAnnotations
    func makeNSView(context: Context) -> BrowserAnnotationPointerView { BrowserAnnotationPointerView(model: model) }
    func updateNSView(_ nsView: BrowserAnnotationPointerView, context: Context) { nsView.model = model }
}

@MainActor
final class BrowserAnnotationPointerView: NSView {
    var model: WorkspaceBrowserAnnotations
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(model: WorkspaceBrowserAnnotations) { self.model = model; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if model.isSelecting { window?.makeFirstResponder(self) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    private func point(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x / max(1, bounds.width), y: point.y / max(1, bounds.height))
    }
    override func mouseMoved(with event: NSEvent) { model.hover(at: point(event)) }
    override func mouseEntered(with event: NSEvent) { model.hover(at: point(event)) }
    override func mouseExited(with event: NSEvent) { model.hover(at: nil) }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        model.pick(at: point(event))
    }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { model.cancel() } }
}
#endif
