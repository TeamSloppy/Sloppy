#if os(macOS)
import AppKit
import SwiftUI

/// SwiftUI owns the annotations; this view only tracks a pointer in canvas coordinates.
struct ChatImageAnnotationPointerInput: NSViewRepresentable {
    var isPanning = false
    let changed: @MainActor (CGPoint, CGPoint) -> Void
    let ended: @MainActor (CGPoint, CGPoint) -> Void

    var pan: @MainActor (CGSize) -> Void = { _ in }
    var magnify: @MainActor (CGFloat) -> Void = { _ in }

    func makeNSView(context: Context) -> AnnotationPointerView {
        let view = AnnotationPointerView()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        view.setAccessibilityLabel("Screenshot annotation canvas")
        view.setAccessibilityIdentifier("chat.image.annotations.canvas")
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: AnnotationPointerView, context: Context) {
        view.isPanning = isPanning
        view.pan = pan
        view.magnify = magnify
        view.changed = changed
        view.ended = ended
    }

    final class AnnotationPointerView: NSView {
        var changed: (@MainActor (CGPoint, CGPoint) -> Void)?
        var ended: (@MainActor (CGPoint, CGPoint) -> Void)?
        var isPanning = false
        var pan: (@MainActor (CGSize) -> Void)?
        var magnify: (@MainActor (CGFloat) -> Void)?
        private var panningGesture = false
        private var previous: CGPoint?
        private var start: CGPoint?

        override var isFlipped: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            panningGesture = isPanning || event.modifierFlags.contains(.option)
            previous = point
            start = point
            if panningGesture { return }
            changed?(point, point)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start else { return }
            let point = convert(event.locationInWindow, from: nil)
            if panningGesture {
                if let previous { pan?(CGSize(width: point.x - previous.x, height: point.y - previous.y)) }
                previous = point
            } else { changed?(start, point) }
        }

        override func scrollWheel(with event: NSEvent) {
            guard start == nil else { return }
            let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
            pan?(CGSize(width: event.scrollingDeltaX * factor, height: event.scrollingDeltaY * factor))
        }

        override func magnify(with event: NSEvent) {
            // A pinch cancels any pending annotation gesture.
            start = nil
            magnify?(max(0.01, 1 + event.magnification))
        }

        override func mouseUp(with event: NSEvent) {
            guard let start else { return }
            self.start = nil
            guard !panningGesture else { panningGesture = false; return }
            ended?(start, convert(event.locationInWindow, from: nil))
        }
    }
}
#endif
