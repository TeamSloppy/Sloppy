#if os(macOS) || os(iOS)
import Foundation
import SwiftUI
import WebKit
import SloppyClientUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Observable @MainActor
final class BrowserAgentPointerState {
    enum Action: String { case click = "Clicking", type = "Typing", scroll = "Scrolling" }
    var point: CGPoint?
    var action = Action.click
    var agentID = "sloppy"
    var paletteID: String?
}

/// This is native app chrome; page JavaScript cannot impersonate its agent identity.
@MainActor
final class BrowserAgentPointer {
    let state = BrowserAgentPointerState()
    private weak var webView: WKWebView?
    private var expiry: Task<Void, Never>?
#if os(macOS)
    private var host: BrowserPointerHostingView?
#else
    private var host: UIHostingController<BrowserAgentPointerOverlay>?
#endif

    func show(in webView: WKWebView, point: CGPoint, action: BrowserAgentPointerState.Action, agentID: String, paletteID: String?) {
        guard point.x.isFinite, point.y.isFinite, (0...1).contains(point.x), (0...1).contains(point.y) else { clear(); return }
        if self.webView !== webView {
            detach()
            self.webView = webView
#if os(macOS)
            let view = BrowserPointerHostingView(rootView: BrowserAgentPointerOverlay(state: state))
            view.frame = webView.bounds
            view.autoresizingMask = [.width, .height]
            webView.addSubview(view)
            host = view
#else
            let controller = UIHostingController(rootView: BrowserAgentPointerOverlay(state: state))
            controller.view.backgroundColor = .clear
            controller.view.isUserInteractionEnabled = false
            controller.view.frame = webView.bounds
            controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            webView.addSubview(controller.view)
            host = controller
#endif
        }
        state.agentID = agentID
        state.paletteID = paletteID
        state.action = action
        state.point = point
        expiry?.cancel()
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            self?.state.point = nil
        }
    }

    func clear() { expiry?.cancel(); expiry = nil; state.point = nil }
    func detach() {
        clear()
#if os(macOS)
        host?.removeFromSuperview()
#else
        host?.view.removeFromSuperview()
#endif
        host = nil
        webView = nil
    }
}

@MainActor
struct BrowserAgentPointerOverlay: View {
    let state: BrowserAgentPointerState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            if let point = state.point {
                let x = point.x * geometry.size.width
                let y = point.y * geometry.size.height
                ZStack(alignment: .topLeading) {
                    Circle()
                        .fill(Color.accentColor.opacity(reduceTransparency ? 0.5 : 0.24))
                        .frame(width: 34, height: 34)
                        .blur(radius: reduceTransparency ? 0 : 5)
                        .offset(x: x - 17, y: y - 17)
                    Image(systemName: state.action == .type ? "cursorarrow.and.square.on.square.dashed" : "cursorarrow")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                        .offset(x: x - 3, y: y - 3)
                    AgentBotAvatar(agentID: state.agentID, size: 28, paletteID: state.paletteID,
                                   emotion: .idle, isAnimated: !reduceMotion)
                        .offset(x: x + (point.x > 0.8 ? -40 : 20), y: min(y + 15, geometry.size.height - 30))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if os(macOS)
private final class BrowserPointerHostingView: NSHostingView<BrowserAgentPointerOverlay> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif
#endif
