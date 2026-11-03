#if os(macOS)
import AppKit
import SwiftUI

/// Observe movement over WebKit without placing an input-blocking view over it.
struct BrowserSidebarPeekTracking: NSViewRepresentable {
    var isEnabled: Bool
    var isPresented: Bool
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView { TrackingView() }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.isEnabled = isEnabled
        view.isPresented = isPresented
        view.onChange = onChange
    }

    static func dismantleNSView(_ view: TrackingView, coordinator: ()) { view.stopMonitoring() }

    final class TrackingView: NSView {
        var isEnabled = false
        var isPresented = false
        var onChange: ((Bool) -> Void)?
        private var monitor: Any?
        private var tracking: NSTrackingArea?
        private var resignationObserver: NSObjectProtocol?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard let window else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard event.window === self.window else { self.setPresented(false); return }
                    self.updateHover(at: self.convert(event.locationInWindow, from: nil))
                }
                return event
            }
            resignationObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.setPresented(false) }
            }
        }

        override func updateTrackingAreas() {
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: .zero,
                                      options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                                      owner: self)
            addTrackingArea(area)
            tracking = area
            super.updateTrackingAreas()
        }

        override func mouseEntered(with event: NSEvent) { updateHover(at: convert(event.locationInWindow, from: nil)) }
        override func mouseMoved(with event: NSEvent) { updateHover(at: convert(event.locationInWindow, from: nil)) }
        override func mouseExited(with event: NSEvent) { setPresented(false) }

        func updateHover(at point: NSPoint) {
            setPresented(isEnabled && bounds.contains(point) && point.x < (isPresented ? 260 : 8))
        }

        private func setPresented(_ presented: Bool) {
            guard presented != isPresented else { return }
            isPresented = presented
            onChange?(presented)
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let resignationObserver { NotificationCenter.default.removeObserver(resignationObserver) }
            monitor = nil
            resignationObserver = nil
        }
    }
}
#endif
