import AppKit
import SpriteKit

@MainActor
final class NotchPetScene: SKScene {
    private enum Behavior: CaseIterable {
        case watching
        case thinking
        case daydreaming
    }

    private let backgroundNode = SKShapeNode()
    private let glowNode = SKNode()
    private let characterNode = SKNode()
    private let bodyShadowNode = SKShapeNode()
    private let bodyNode = SKShapeNode()
    private let leftFootNode = SKShapeNode(ellipseOf: CGSize(width: 27, height: 19))
    private let rightFootNode = SKShapeNode(ellipseOf: CGSize(width: 27, height: 19))
    private let leftEyeNode = SKShapeNode(rectOf: CGSize(width: 12, height: 29), cornerRadius: 6)
    private let rightEyeNode = SKShapeNode(rectOf: CGSize(width: 12, height: 29), cornerRadius: 6)
    private let thoughtBubbleNode = SKShapeNode(circleOfRadius: 14)
    private let thoughtDotsNode = SKLabelNode(text: "•••")
    private let catchlightNode = SKShapeNode(ellipseOf: CGSize(width: 31, height: 19))

    private var behavior: Behavior = .thinking
    private var nextAmbientBehavior: Behavior = .daydreaming
    private var startedAt: TimeInterval?
    private var lastUpdate: TimeInterval = 0
    private var nextBehaviorChange: TimeInterval = 12
    private var nextBlink: TimeInterval = 2.2
    private var blinkStartedAt: TimeInterval?
    private var reactionEndsAt: TimeInterval = 0
    private var bubbleAlpha: CGFloat = 1
    private var glowIntensity: CGFloat = 0.55
    private var eyeOffset = CGVector.zero

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        anchorPoint = CGPoint(x: 0, y: 0)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        buildScene()
        layoutScene()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutScene()
    }

    func advanceFrame(to currentTime: TimeInterval) {
        if startedAt == nil {
            startedAt = currentTime
            lastUpdate = currentTime
        }
        guard let startedAt else { return }

        let elapsed = currentTime - startedAt
        let delta = min(max(currentTime - lastUpdate, 0), 1 / 15)
        lastUpdate = currentTime

        updateBehavior(at: elapsed)
        updateBlink(at: elapsed)
        updateCursorTracking(delta: delta, elapsed: elapsed)
        updateCharacterAnimation(elapsed: elapsed, delta: delta)
    }

    override func mouseDown(with event: NSEvent) {
        triggerReaction()
    }

    func triggerThinking() {
        let elapsed = currentElapsedTime
        setBehavior(.thinking, at: elapsed, duration: 6.5)
    }

    func triggerReaction() {
        let elapsed = currentElapsedTime
        reactionEndsAt = elapsed + 1.1
        setBehavior(.watching, at: elapsed, duration: 3.6)
        characterNode.removeAction(forKey: "reaction")
        let squash = SKAction.group([
            .scaleX(to: 1.13, duration: 0.10),
            .scaleY(to: 0.87, duration: 0.10),
        ])
        squash.timingMode = .easeOut
        let spring = SKAction.group([
            .scaleX(to: 0.94, duration: 0.13),
            .scaleY(to: 1.08, duration: 0.13),
            .moveBy(x: 0, y: 7, duration: 0.13),
        ])
        spring.timingMode = .easeOut
        let settle = SKAction.group([
            .scale(to: 1, duration: 0.24),
            .moveBy(x: 0, y: -7, duration: 0.24),
        ])
        settle.timingMode = .easeInEaseOut
        characterNode.run(.sequence([squash, spring, settle]), withKey: "reaction")
    }

    private var currentElapsedTime: TimeInterval {
        guard let startedAt else { return 0 }
        return lastUpdate - startedAt
    }

    private func buildScene() {
        guard children.isEmpty else { return }

        backgroundNode.fillColor = NSColor(calibratedWhite: 0.012, alpha: 0.985)
        backgroundNode.strokeColor = NSColor(calibratedWhite: 0.22, alpha: 0.42)
        backgroundNode.lineWidth = 1
        backgroundNode.zPosition = 0
        addChild(backgroundNode)

        glowNode.zPosition = 2
        addChild(glowNode)
        buildGlowLayers()

        characterNode.zPosition = 4
        addChild(characterNode)

        leftFootNode.fillColor = NSColor(calibratedRed: 0.76, green: 0.78, blue: 0.80, alpha: 1)
        rightFootNode.fillColor = leftFootNode.fillColor
        leftFootNode.strokeColor = .clear
        rightFootNode.strokeColor = .clear
        leftFootNode.zPosition = 1
        rightFootNode.zPosition = 1
        leftFootNode.zRotation = 0.20
        rightFootNode.zRotation = -0.20
        characterNode.addChild(leftFootNode)
        characterNode.addChild(rightFootNode)

        let bodyPath = makeBodyPath()
        bodyShadowNode.path = bodyPath
        bodyShadowNode.fillColor = NSColor(calibratedWhite: 0, alpha: 0.54)
        bodyShadowNode.strokeColor = .clear
        bodyShadowNode.position = CGPoint(x: 0, y: -5)
        bodyShadowNode.zPosition = 2
        bodyShadowNode.glowWidth = 12
        characterNode.addChild(bodyShadowNode)

        bodyNode.path = bodyPath
        bodyNode.fillColor = NSColor(calibratedRed: 0.91, green: 0.92, blue: 0.93, alpha: 1)
        bodyNode.strokeColor = NSColor(calibratedWhite: 1, alpha: 0.55)
        bodyNode.lineWidth = 1.2
        bodyNode.zPosition = 3
        characterNode.addChild(bodyNode)

        catchlightNode.fillColor = NSColor(calibratedWhite: 1, alpha: 0.18)
        catchlightNode.strokeColor = .clear
        catchlightNode.position = CGPoint(x: -13, y: 25)
        catchlightNode.zRotation = 0.38
        catchlightNode.zPosition = 4
        characterNode.addChild(catchlightNode)

        [leftEyeNode, rightEyeNode].forEach { eye in
            eye.fillColor = NSColor(calibratedWhite: 0.015, alpha: 1)
            eye.strokeColor = NSColor(calibratedWhite: 0.12, alpha: 1)
            eye.lineWidth = 0.7
            eye.zPosition = 6
            characterNode.addChild(eye)
        }

        thoughtBubbleNode.fillColor = NSColor(calibratedRed: 0.08, green: 0.62, blue: 0.94, alpha: 1)
        thoughtBubbleNode.strokeColor = NSColor(calibratedRed: 0.38, green: 0.82, blue: 1, alpha: 0.8)
        thoughtBubbleNode.lineWidth = 1
        thoughtBubbleNode.zPosition = 12
        thoughtBubbleNode.alpha = 1
        addChild(thoughtBubbleNode)

        thoughtDotsNode.fontName = "SFProRounded-Semibold"
        thoughtDotsNode.fontSize = 8
        thoughtDotsNode.fontColor = NSColor(calibratedWhite: 0.02, alpha: 0.85)
        thoughtDotsNode.verticalAlignmentMode = .center
        thoughtDotsNode.horizontalAlignmentMode = .center
        thoughtDotsNode.position = CGPoint(x: 0, y: 0.5)
        thoughtDotsNode.zPosition = 9
        thoughtBubbleNode.addChild(thoughtDotsNode)
    }

    private func buildGlowLayers() {
        let sizes: [CGFloat] = [162, 142, 120, 101]
        for (index, diameter) in sizes.enumerated() {
            let layer = SKShapeNode(circleOfRadius: diameter / 2)
            layer.name = "glow-\(index)"
            layer.fillColor = NSColor(calibratedRed: 0.08, green: 0.50, blue: 0.86, alpha: 0.025 + CGFloat(index) * 0.018)
            layer.strokeColor = .clear
            glowNode.addChild(layer)
        }
    }

    private func layoutScene() {
        backgroundNode.path = makeNotchPath(size: size)
        let petCenter = CGPoint(x: size.width / 2, y: 66)
        glowNode.position = petCenter
        characterNode.position = petCenter
        thoughtBubbleNode.position = CGPoint(x: petCenter.x - 50, y: petCenter.y + 39)

        leftFootNode.position = CGPoint(x: -20, y: -38)
        rightFootNode.position = CGPoint(x: 20, y: -38)
        leftEyeNode.position = CGPoint(x: -15, y: -2)
        rightEyeNode.position = CGPoint(x: 15, y: -2)
    }

    private func updateBehavior(at elapsed: TimeInterval) {
        guard elapsed >= nextBehaviorChange else { return }
        let next: Behavior
        switch behavior {
        case .watching:
            next = nextAmbientBehavior
            nextAmbientBehavior = nextAmbientBehavior == .thinking ? .daydreaming : .thinking
        case .thinking, .daydreaming:
            next = .watching
        }
        let duration: TimeInterval = next == .thinking
            ? 12
            : Double.random(in: 5.0...8.2)
        setBehavior(next, at: elapsed, duration: duration)
    }

    private func setBehavior(_ newBehavior: Behavior, at elapsed: TimeInterval, duration: TimeInterval) {
        behavior = newBehavior
        nextBehaviorChange = elapsed + duration
    }

    private func updateBlink(at elapsed: TimeInterval) {
        if blinkStartedAt == nil, elapsed >= nextBlink {
            blinkStartedAt = elapsed
        }
        guard let blinkStartedAt else {
            leftEyeNode.yScale = 1
            rightEyeNode.yScale = 1
            return
        }

        let progress = (elapsed - blinkStartedAt) / 0.18
        if progress >= 1 {
            self.blinkStartedAt = nil
            nextBlink = elapsed + Double.random(in: 2.0...4.6)
            leftEyeNode.yScale = 1
            rightEyeNode.yScale = 1
            return
        }

        let scale = max(0.08, abs(CGFloat(progress * 2 - 1)))
        leftEyeNode.yScale = scale
        rightEyeNode.yScale = scale
    }

    private func updateCursorTracking(delta: TimeInterval, elapsed: TimeInterval) {
        let desiredOffset: CGVector
        if behavior == .thinking {
            desiredOffset = CGVector(dx: -2.6 + sin(elapsed * 1.4), dy: 3.6)
        } else if behavior == .daydreaming {
            desiredOffset = CGVector(dx: 2.2 * sin(elapsed * 0.9), dy: 2.8)
        } else if let pointer = pointerPositionInScene() {
            let deltaX = pointer.x - characterNode.position.x
            let deltaY = pointer.y - characterNode.position.y
            let distance = max(hypot(deltaX, deltaY), 1)
            let proximity = min(distance / 150, 1)
            desiredOffset = CGVector(
                dx: (deltaX / distance) * (4.2 + 1.2 * proximity),
                dy: (deltaY / distance) * (3.8 + 0.8 * proximity)
            )
        } else {
            desiredOffset = .zero
        }

        let smoothing = min(CGFloat(delta * 11), 1)
        eyeOffset.dx += (desiredOffset.dx - eyeOffset.dx) * smoothing
        eyeOffset.dy += (desiredOffset.dy - eyeOffset.dy) * smoothing
        leftEyeNode.position = CGPoint(x: -15 + eyeOffset.dx, y: -2 + eyeOffset.dy)
        rightEyeNode.position = CGPoint(x: 15 + eyeOffset.dx, y: -2 + eyeOffset.dy)
    }

    private func updateCharacterAnimation(elapsed: TimeInterval, delta: TimeInterval) {
        let isReacting = elapsed < reactionEndsAt
        if !isReacting, characterNode.action(forKey: "reaction") == nil {
            let bob = sin(elapsed * 2.05) * 2.1
            let drift = sin(elapsed * 0.72) * 1.8
            characterNode.position = CGPoint(x: size.width / 2 + drift, y: 66 + bob)
            characterNode.zRotation = sin(elapsed * 0.83) * 0.025
            characterNode.xScale = 1 + sin(elapsed * 1.13) * 0.008
            characterNode.yScale = 1 - sin(elapsed * 1.13) * 0.008
        }

        let desiredBubbleAlpha: CGFloat = behavior == .thinking ? 1 : 0
        let blend = min(CGFloat(delta * 7), 1)
        bubbleAlpha += (desiredBubbleAlpha - bubbleAlpha) * blend
        thoughtBubbleNode.alpha = bubbleAlpha
        thoughtBubbleNode.setScale(0.84 + bubbleAlpha * 0.16)
        thoughtBubbleNode.position = CGPoint(
            x: characterNode.position.x - 50,
            y: characterNode.position.y + 39 + sin(elapsed * 3.2) * 1.8
        )

        let desiredGlow: CGFloat
        switch behavior {
        case .watching: desiredGlow = isReacting ? 0.95 : 0.48
        case .thinking: desiredGlow = 1
        case .daydreaming: desiredGlow = 0.68
        }
        glowIntensity += (desiredGlow - glowIntensity) * blend
        for (index, child) in glowNode.children.enumerated() {
            child.alpha = glowIntensity * (0.58 + CGFloat(index) * 0.11)
            let pulse = 1 + sin(elapsed * 1.25 + Double(index) * 0.45) * 0.018
            child.setScale(pulse)
        }
    }

    private func pointerPositionInScene() -> CGPoint? {
        guard let view, let window = view.window else { return nil }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let viewPoint = view.convert(windowPoint, from: nil)
        return convertPoint(fromView: viewPoint)
    }

    private func makeNotchPath(size: CGSize) -> CGPath {
        let radius: CGFloat = 26
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: size.height))
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: size.width, y: radius))
        path.addQuadCurve(to: CGPoint(x: size.width - radius, y: 0), control: CGPoint(x: size.width, y: 0))
        path.addLine(to: CGPoint(x: radius, y: 0))
        path.addQuadCurve(to: CGPoint(x: 0, y: radius), control: CGPoint(x: 0, y: 0))
        path.closeSubpath()
        return path
    }

    private func makeBodyPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 49))
        path.addCurve(
            to: CGPoint(x: 40, y: 9),
            control1: CGPoint(x: 25, y: 49),
            control2: CGPoint(x: 40, y: 31)
        )
        path.addCurve(
            to: CGPoint(x: 31, y: -31),
            control1: CGPoint(x: 40, y: -9),
            control2: CGPoint(x: 40, y: -23)
        )
        path.addCurve(
            to: CGPoint(x: 4, y: -39),
            control1: CGPoint(x: 23, y: -39),
            control2: CGPoint(x: 14, y: -38)
        )
        path.addCurve(
            to: CGPoint(x: -35, y: -26),
            control1: CGPoint(x: -15, y: -43),
            control2: CGPoint(x: -30, y: -37)
        )
        path.addCurve(
            to: CGPoint(x: -41, y: 7),
            control1: CGPoint(x: -42, y: -13),
            control2: CGPoint(x: -42, y: -2)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: 49),
            control1: CGPoint(x: -41, y: 31),
            control2: CGPoint(x: -23, y: 49)
        )
        path.closeSubpath()
        return path
    }
}
