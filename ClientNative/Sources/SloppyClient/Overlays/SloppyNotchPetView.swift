#if os(macOS)
import AppKit
import QuartzCore
import SpriteKit
import SwiftUI

enum SloppyNotchPetState: String, Equatable, Sendable {
    case idle
    case working
    case thinking
    case needsInput
    case error
}

struct SloppyNotchPetView: NSViewRepresentable {
    var presentationScale: CGFloat = 1
    var state: SloppyNotchPetState = .idle
    var onClick: (@MainActor () -> Void)?

    func makeNSView(context: Context) -> SloppyNotchPetSpriteView {
        SloppyNotchPetSpriteView(
            presentationScale: presentationScale,
            state: state,
            onClick: onClick
        )
    }

    func updateNSView(_ nsView: SloppyNotchPetSpriteView, context: Context) {
        nsView.setCommunicationState(state)
        nsView.onClick = onClick
    }

    static func dismantleNSView(_ nsView: SloppyNotchPetSpriteView, coordinator: Void) {
        nsView.stopAnimating()
    }
}

@MainActor
final class SloppyNotchPetSpriteView: SKView {
    private let petScene: SloppyNotchPetScene
    private var animationTimer: Timer?
    private var petTrackingArea: NSTrackingArea?
    var onClick: (@MainActor () -> Void)?

    init(
        presentationScale: CGFloat,
        state: SloppyNotchPetState,
        onClick: (@MainActor () -> Void)?
    ) {
        petScene = SloppyNotchPetScene(
            size: CGSize(width: 24, height: 24),
            presentationScale: presentationScale,
            communicationState: state
        )
        self.onClick = onClick
        super.init(frame: .zero)
        allowsTransparency = true
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        preferredFramesPerSecond = 30
        isPaused = false
        petScene.scaleMode = .resizeFill
        presentScene(petScene)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopAnimating()
        } else {
            startAnimating()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let petTrackingArea {
            removeTrackingArea(petTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        petTrackingArea = trackingArea
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseEntered(with event: NSEvent) {
        petScene.handlePointerEntered(at: scenePoint(for: event))
    }

    override func mouseExited(with event: NSEvent) {
        petScene.handlePointerExited()
    }

    override func mouseMoved(with event: NSEvent) {
        petScene.handlePointerMove(at: scenePoint(for: event))
    }

    override func mouseDragged(with event: NSEvent) {
        petScene.handlePointerMove(at: scenePoint(for: event))
    }

    override func mouseDown(with event: NSEvent) {
        petScene.handlePoke(at: scenePoint(for: event))
        onClick?()
    }

    func setCommunicationState(_ state: SloppyNotchPetState) {
        petScene.setCommunicationState(state)
    }

    func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func startAnimating() {
        guard animationTimer == nil else { return }
        let timer = Timer(
            timeInterval: 1 / 30,
            target: self,
            selector: #selector(advanceAnimation),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 1 / 120
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    @objc private func advanceAnimation() {
        isPaused = false
        petScene.advanceFrame(to: CACurrentMediaTime(), pointer: pointerPositionInScene())
    }

    private func pointerPositionInScene() -> CGPoint? {
        guard let window else { return nil }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let viewPoint = convert(windowPoint, from: nil)
        return petScene.convertPoint(fromView: viewPoint)
    }

    private func scenePoint(for event: NSEvent) -> CGPoint {
        let viewPoint = convert(event.locationInWindow, from: nil)
        return petScene.convertPoint(fromView: viewPoint)
    }
}

@MainActor
private final class SloppyNotchPetScene: SKScene {
    private enum Reaction: Equatable {
        case none
        case happy
        case surprised
        case angry
    }

    private enum Expression: Equatable {
        case idle
        case working
        case thinking
        case needsInput
        case error
        case happy
        case surprised
        case angry
    }

    private let glowNode = SKNode()
    private let characterNode = SKNode()
    private let bodyNode = SKShapeNode()
    private let leftFootNode = SKShapeNode(ellipseOf: CGSize(width: 5.2, height: 3.3))
    private let rightFootNode = SKShapeNode(ellipseOf: CGSize(width: 5.2, height: 3.3))
    private let leftEyeNode = SKShapeNode(rectOf: CGSize(width: 2.2, height: 5.3), cornerRadius: 1.1)
    private let rightEyeNode = SKShapeNode(rectOf: CGSize(width: 2.2, height: 5.3), cornerRadius: 1.1)
    private let thoughtBubbleNode = SKShapeNode(circleOfRadius: 2.7)
    private let bubbleSymbolNode = SKLabelNode(fontNamed: "SFProRounded-Semibold")
    private let presentationScale: CGFloat
    private var communicationState: SloppyNotchPetState

    private var startedAt: TimeInterval?
    private var lastUpdate: TimeInterval = 0
    private var eyeOffset = CGVector.zero
    private var bubbleAlpha: CGFloat = 0
    private var reaction: Reaction = .none
    private var reactionEndsAt: TimeInterval = 0
    private var pokeTimes: [TimeInterval] = []
    private var lastPetPoint: CGPoint?
    private var pettingDistance: CGFloat = 0
    private var lastPetMoveAt: TimeInterval = 0

    init(
        size: CGSize,
        presentationScale: CGFloat,
        communicationState: SloppyNotchPetState
    ) {
        self.presentationScale = presentationScale
        self.communicationState = communicationState
        super.init(size: size)
        backgroundColor = .clear
        anchorPoint = .zero
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    override func didMove(to view: SKView) {
        buildScene()
        layoutScene()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutScene()
    }

    func advanceFrame(to currentTime: TimeInterval, pointer: CGPoint?) {
        if startedAt == nil {
            startedAt = currentTime
            lastUpdate = currentTime
        }
        guard let startedAt else { return }

        let elapsed = currentTime - startedAt
        let delta = min(max(currentTime - lastUpdate, 0), 1 / 15)
        lastUpdate = currentTime
        if reaction != .none, currentTime >= reactionEndsAt {
            reaction = .none
        }
        let expression = currentExpression

        updateFace(pointer: pointer, expression: expression, elapsed: elapsed, delta: delta)
        updateBody(expression: expression, elapsed: elapsed, delta: delta)
    }

    func setCommunicationState(_ state: SloppyNotchPetState) {
        guard communicationState != state else { return }
        communicationState = state
        if state == .error || state == .needsInput {
            reaction = .none
        }
    }

    func handlePointerEntered(at point: CGPoint) {
        lastPetPoint = point
        pettingDistance = 0
        lastPetMoveAt = CACurrentMediaTime()
    }

    func handlePointerExited() {
        lastPetPoint = nil
        pettingDistance = 0
    }

    func handlePointerMove(at point: CGPoint) {
        let now = CACurrentMediaTime()
        defer {
            lastPetPoint = point
            lastPetMoveAt = now
        }
        guard let lastPetPoint, now - lastPetMoveAt < 0.22 else {
            pettingDistance = 0
            return
        }

        let distance = hypot(point.x - lastPetPoint.x, point.y - lastPetPoint.y)
        guard distance < 18 else {
            pettingDistance = 0
            return
        }
        pettingDistance += distance
        if pettingDistance >= 28 {
            setReaction(.happy, duration: 1.8, at: now)
            pettingDistance = 0
        }
    }

    func handlePoke(at point: CGPoint) {
        let now = CACurrentMediaTime()
        pokeTimes = pokeTimes.filter { now - $0 < 1.35 }
        pokeTimes.append(now)

        switch pokeTimes.count {
        case 1:
            setReaction(.surprised, duration: 0.75, at: now)
        case 2:
            setReaction(.happy, duration: 1.25, at: now)
        default:
            setReaction(.angry, duration: 2.2, at: now)
            pokeTimes.removeAll()
        }
        lastPetPoint = point
    }

    private var currentExpression: Expression {
        if communicationState == .error {
            return .error
        }
        if communicationState == .needsInput {
            return .needsInput
        }
        switch reaction {
        case .happy: return .happy
        case .surprised: return .surprised
        case .angry: return .angry
        case .none: break
        }
        switch communicationState {
        case .idle: return .idle
        case .working: return .working
        case .thinking: return .thinking
        case .needsInput: return .needsInput
        case .error: return .error
        }
    }

    private func setReaction(_ reaction: Reaction, duration: TimeInterval, at time: TimeInterval) {
        guard communicationState != .error, communicationState != .needsInput else { return }
        self.reaction = reaction
        reactionEndsAt = time + duration
    }

    private func buildScene() {
        guard children.isEmpty else { return }

        glowNode.zPosition = 0
        addChild(glowNode)
        for (index, diameter) in [22.0, 17.0].enumerated() {
            let glow = SKShapeNode(circleOfRadius: diameter / 2)
            glow.fillColor = NSColor(
                calibratedRed: 0.05,
                green: 0.58,
                blue: 0.92,
                alpha: index == 0 ? 0.08 : 0.13
            )
            glow.strokeColor = .clear
            glowNode.addChild(glow)
        }

        characterNode.zPosition = 2
        addChild(characterNode)

        leftFootNode.fillColor = NSColor(calibratedWhite: 0.73, alpha: 1)
        rightFootNode.fillColor = leftFootNode.fillColor
        leftFootNode.strokeColor = .clear
        rightFootNode.strokeColor = .clear
        leftFootNode.zRotation = 0.18
        rightFootNode.zRotation = -0.18
        characterNode.addChild(leftFootNode)
        characterNode.addChild(rightFootNode)

        bodyNode.path = makeBodyPath()
        bodyNode.fillColor = NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.95, alpha: 1)
        bodyNode.strokeColor = NSColor(calibratedWhite: 1, alpha: 0.72)
        bodyNode.lineWidth = 0.45
        bodyNode.zPosition = 2
        characterNode.addChild(bodyNode)

        for eye in [leftEyeNode, rightEyeNode] {
            eye.fillColor = NSColor(calibratedWhite: 0.015, alpha: 1)
            eye.strokeColor = .clear
            eye.zPosition = 4
            characterNode.addChild(eye)
        }

        thoughtBubbleNode.fillColor = NSColor(calibratedRed: 0.08, green: 0.64, blue: 0.96, alpha: 1)
        thoughtBubbleNode.strokeColor = NSColor(calibratedRed: 0.42, green: 0.86, blue: 1, alpha: 0.8)
        thoughtBubbleNode.lineWidth = 0.35
        thoughtBubbleNode.zPosition = 6
        thoughtBubbleNode.alpha = 0
        addChild(thoughtBubbleNode)

        bubbleSymbolNode.fontSize = 3.1
        bubbleSymbolNode.fontColor = NSColor(calibratedWhite: 0.02, alpha: 0.9)
        bubbleSymbolNode.horizontalAlignmentMode = .center
        bubbleSymbolNode.verticalAlignmentMode = .center
        bubbleSymbolNode.position = CGPoint(x: 0, y: 0.15)
        bubbleSymbolNode.zPosition = 7
        thoughtBubbleNode.addChild(bubbleSymbolNode)
    }

    private func layoutScene() {
        let center = CGPoint(x: size.width / 2, y: size.height / 2 - 0.25)
        glowNode.position = center
        glowNode.setScale(presentationScale)
        characterNode.position = center
        characterNode.setScale(presentationScale)
        thoughtBubbleNode.position = CGPoint(
            x: center.x - 6.2 * presentationScale,
            y: center.y + 6.2 * presentationScale
        )
        thoughtBubbleNode.setScale(presentationScale)
        leftFootNode.position = CGPoint(x: -3.1, y: -6.6)
        rightFootNode.position = CGPoint(x: 3.1, y: -6.6)
        leftEyeNode.position = CGPoint(x: -2.45, y: -0.55)
        rightEyeNode.position = CGPoint(x: 2.45, y: -0.55)
    }

    private func updateFace(
        pointer: CGPoint?,
        expression: Expression,
        elapsed: TimeInterval,
        delta: TimeInterval
    ) {
        let target: CGVector
        switch expression {
        case .thinking:
            target = CGVector(dx: -0.65 + sin(elapsed * 1.5) * 0.18, dy: 0.75)
        case .error:
            target = CGVector(dx: 0, dy: -0.48)
        case .angry:
            target = .zero
        case .idle, .working, .needsInput, .happy, .surprised:
            if let pointer {
                let dx = pointer.x - characterNode.position.x
                let dy = pointer.y - characterNode.position.y
                let distance = max(hypot(dx, dy), 1)
                target = CGVector(dx: dx / distance * 0.95, dy: dy / distance * 0.8)
            } else {
                target = .zero
            }
        }

        let smoothing = min(CGFloat(delta * 12), 1)
        eyeOffset.dx += (target.dx - eyeOffset.dx) * smoothing
        eyeOffset.dy += (target.dy - eyeOffset.dy) * smoothing
        leftEyeNode.position = CGPoint(x: -2.45 + eyeOffset.dx, y: -0.55 + eyeOffset.dy)
        rightEyeNode.position = CGPoint(x: 2.45 + eyeOffset.dx, y: -0.55 + eyeOffset.dy)

        let blinkPhase = elapsed.truncatingRemainder(dividingBy: 3.8)
        let blinkScale = blinkPhase < 0.16
            ? max(0.08, abs(CGFloat(blinkPhase / 0.08 - 1)))
            : 1
        leftEyeNode.xScale = 1
        rightEyeNode.xScale = 1
        leftEyeNode.yScale = blinkScale
        rightEyeNode.yScale = blinkScale
        leftEyeNode.zRotation = 0
        rightEyeNode.zRotation = 0

        switch expression {
        case .happy:
            leftEyeNode.yScale = 0.42
            rightEyeNode.yScale = 0.42
            leftEyeNode.zRotation = -0.14
            rightEyeNode.zRotation = 0.14
        case .surprised:
            leftEyeNode.xScale = 0.78
            rightEyeNode.xScale = 0.78
            leftEyeNode.yScale = 1.22
            rightEyeNode.yScale = 1.22
        case .angry:
            leftEyeNode.yScale = 0.66
            rightEyeNode.yScale = 0.66
            leftEyeNode.zRotation = -0.34
            rightEyeNode.zRotation = 0.34
        case .error:
            leftEyeNode.yScale = 0.72
            rightEyeNode.yScale = 0.72
            leftEyeNode.zRotation = 0.12
            rightEyeNode.zRotation = -0.12
        case .idle, .working, .thinking, .needsInput:
            break
        }
    }

    private func updateBody(expression: Expression, elapsed: TimeInterval, delta: TimeInterval) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2 - 0.25)
        let baseX = sin(elapsed * 0.72) * 0.25
        let baseY = sin(elapsed * 2.05) * 0.32
        let reactionX: CGFloat
        let reactionY: CGFloat
        let rotation: CGFloat
        let scaleX: CGFloat
        let scaleY: CGFloat

        switch expression {
        case .happy:
            reactionX = 0
            reactionY = abs(sin(elapsed * 7.5)) * 0.9
            rotation = sin(elapsed * 6.5) * 0.07
            scaleX = 1.04
            scaleY = 0.98
        case .surprised:
            reactionX = 0
            reactionY = abs(sin(elapsed * 10)) * 0.45
            rotation = 0
            scaleX = 0.92
            scaleY = 1.1
        case .angry:
            reactionX = sin(elapsed * 30) * 0.55
            reactionY = 0
            rotation = sin(elapsed * 24) * 0.045
            scaleX = 1.05
            scaleY = 0.96
        case .error:
            reactionX = 0
            reactionY = -0.35 + sin(elapsed * 1.4) * 0.1
            rotation = -0.055
            scaleX = 0.98
            scaleY = 0.96
        case .idle, .working, .thinking, .needsInput:
            reactionX = 0
            reactionY = 0
            rotation = sin(elapsed * 0.83) * 0.025
            scaleX = 1
            scaleY = 1
        }

        characterNode.position = CGPoint(
            x: center.x + (baseX + reactionX) * presentationScale,
            y: center.y + (baseY + reactionY) * presentationScale
        )
        characterNode.zRotation = rotation
        characterNode.xScale = presentationScale * scaleX
        characterNode.yScale = presentationScale * scaleY

        let bubble = bubblePresentation(for: expression)
        let desiredBubbleAlpha: CGFloat = bubble == nil ? 0 : 1
        bubbleAlpha += (desiredBubbleAlpha - bubbleAlpha) * min(CGFloat(delta * 9), 1)
        thoughtBubbleNode.alpha = bubbleAlpha
        if let bubble {
            thoughtBubbleNode.fillColor = bubble.color
            thoughtBubbleNode.strokeColor = bubble.stroke
            bubbleSymbolNode.text = bubble.symbol
        }
        thoughtBubbleNode.setScale(presentationScale * (0.82 + bubbleAlpha * 0.18))
        thoughtBubbleNode.position = CGPoint(
            x: characterNode.position.x - 6.2 * presentationScale,
            y: characterNode.position.y
                + (6.2 + sin(elapsed * 3.2) * 0.22) * presentationScale
        )

        let palette = glowPalette(for: expression)
        for (index, child) in glowNode.children.enumerated() {
            let pulse = 1 + sin(elapsed * 1.3 + Double(index) * 0.45) * 0.025
            child.setScale(pulse * palette.scale)
            (child as? SKShapeNode)?.fillColor = palette.color.withAlphaComponent(
                index == 0 ? 0.08 : 0.13
            )
        }
        bodyNode.strokeColor = palette.color.withAlphaComponent(expression == .error ? 0.82 : 0.28)
    }

    private func bubblePresentation(
        for expression: Expression
    ) -> (symbol: String, color: NSColor, stroke: NSColor)? {
        switch expression {
        case .thinking:
            ("•••", .systemCyan, .cyan)
        case .needsInput:
            ("?", .systemOrange, .orange)
        case .error:
            ("!", .systemRed, .red)
        case .happy:
            ("♥", .systemPink, .systemPink)
        case .surprised:
            ("!", .systemYellow, .systemYellow)
        case .angry:
            ("!", .systemRed, .systemOrange)
        case .idle, .working:
            nil
        }
    }

    private func glowPalette(for expression: Expression) -> (color: NSColor, scale: CGFloat) {
        switch expression {
        case .needsInput, .surprised:
            (.systemOrange, 1.08)
        case .error, .angry:
            (.systemRed, 1.1)
        case .happy:
            (.systemPink, 1.12)
        case .thinking:
            (.systemCyan, 1.12)
        case .idle:
            (.systemTeal, 0.96)
        case .working:
            (.systemCyan, 1)
        }
    }

    private func makeBodyPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 7.7))
        path.addCurve(
            to: CGPoint(x: 6.6, y: 0.8),
            control1: CGPoint(x: 4.1, y: 7.7),
            control2: CGPoint(x: 6.6, y: 4.8)
        )
        path.addCurve(
            to: CGPoint(x: 4.8, y: -5.6),
            control1: CGPoint(x: 6.6, y: -2.2),
            control2: CGPoint(x: 6.4, y: -4.5)
        )
        path.addCurve(
            to: CGPoint(x: -5.6, y: -4.9),
            control1: CGPoint(x: 0.6, y: -6.6),
            control2: CGPoint(x: -3.8, y: -6.2)
        )
        path.addCurve(
            to: CGPoint(x: -6.7, y: 0.8),
            control1: CGPoint(x: -6.5, y: -3.5),
            control2: CGPoint(x: -6.7, y: -1.4)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: 7.7),
            control1: CGPoint(x: -6.7, y: 4.9),
            control2: CGPoint(x: -4.1, y: 7.7)
        )
        path.closeSubpath()
        return path
    }
}
#endif
