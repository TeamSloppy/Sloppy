import AppKit
import QuartzCore
import SpriteKit

@MainActor
final class NotchPanelController {
    static let panelSize = CGSize(width: 348, height: 156)

    private let panel: NotchPetPanel
    private let spriteView: NotchPetView
    private let scene: NotchPetScene
    private var screenObserver: NSObjectProtocol?
    private var animationTimer: Timer?

    init() {
        let contentRect = NSRect(origin: .zero, size: Self.panelSize)
        panel = NotchPetPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        spriteView = NotchPetView(frame: contentRect)
        spriteView.allowsTransparency = true
        spriteView.wantsLayer = true
        spriteView.layer?.backgroundColor = NSColor.clear.cgColor
        spriteView.preferredFramesPerSecond = 60
        spriteView.isPaused = false

        scene = NotchPetScene(size: Self.panelSize)
        scene.scaleMode = .resizeFill
        spriteView.presentScene(scene)

        panel.contentView = spriteView
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .none

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.positionAtNotch()
            }
        }
    }

    func show() {
        positionAtNotch()
        panel.orderFrontRegardless()
        startAnimationTimer()
    }

    func hide() {
        panel.orderOut(nil)
        animationTimer?.invalidate()
        animationTimer = nil
    }

    func stop() {
        panel.orderOut(nil)
        animationTimer?.invalidate()
        animationTimer = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    func triggerThinking() {
        show()
        scene.triggerThinking()
    }

    func triggerReaction() {
        show()
        scene.triggerReaction()
    }

    private func positionAtNotch() {
        guard let screen = preferredScreen() else { return }
        let size = Self.panelSize
        panel.setFrame(
            NSRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - size.height,
                width: size.width,
                height: size.height
            ),
            display: true
        )
    }

    private func startAnimationTimer() {
        guard animationTimer == nil else { return }
        let timer = Timer(
            timeInterval: 1 / 60,
            target: self,
            selector: #selector(advanceAnimation),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 1 / 240
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    @objc private func advanceAnimation() {
        spriteView.isPaused = false
        scene.advanceFrame(to: CACurrentMediaTime())
    }

    private func preferredScreen() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

private final class NotchPetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private final class NotchPetView: SKView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        scene?.mouseDown(with: event)
    }
}
