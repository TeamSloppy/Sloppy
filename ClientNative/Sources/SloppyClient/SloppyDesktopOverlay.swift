import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI

#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class SloppyDesktopOverlay {
    private let state = SloppyDesktopOverlayState()
    private weak var window: NSWindow?
    private var closeBehavior: ClientWindowCloseBehavior = .keepProcess

    func start(settings: ClientSettings) {
        closeBehavior = settings.windowCloseBehavior
        if let window {
            configureTransparentWindow(window)
        }
        applyCloseBehavior(settings.windowCloseBehavior)
    }

    func attach(window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        configureTransparentWindow(window)
        applyCloseBehavior(closeBehavior)
    }

    func applyCloseBehavior(_ behavior: ClientWindowCloseBehavior) {
        closeBehavior = behavior
    }

    func updateToolApproval(_ notification: AppNotification) {
        state.apply(notification)
    }

    private func configureTransparentWindow(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

@MainActor
struct TransparentWindowConfigurationView: NSViewRepresentable {
    let onWindowAvailable: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWindow(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWindow(from: nsView)
    }

    private func configureWindow(from view: NSView) {
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            onWindowAvailable(window)
        }
    }
}

@Observable
@MainActor
private final class SloppyDesktopOverlayState {
    var toolApproval: AppNotification?

    func apply(_ notification: AppNotification) {
        guard notification.type == .toolApproval else { return }

        let status = notification.metadata["status"] ?? "pending"
        if status == "pending" {
            toolApproval = notification
            return
        }
        if toolApproval?.metadata["approvalId"] == notification.metadata["approvalId"] {
            toolApproval = nil
        }
    }
}
#endif
