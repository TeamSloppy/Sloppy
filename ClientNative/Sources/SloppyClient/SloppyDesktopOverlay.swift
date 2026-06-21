import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI

#if os(macOS)
@MainActor
final class SloppyDesktopOverlay {
    private let state = SloppyDesktopOverlayState()

    func start(settings: ClientSettings) {
        applyCloseBehavior(settings.windowCloseBehavior)
    }

    func applyCloseBehavior(_ behavior: ClientWindowCloseBehavior) {
        // SwiftUI version: close-behavior preferences are managed by host UI layer.
        _ = behavior
    }

    func updateToolApproval(_ notification: AppNotification) {
        state.apply(notification)
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

