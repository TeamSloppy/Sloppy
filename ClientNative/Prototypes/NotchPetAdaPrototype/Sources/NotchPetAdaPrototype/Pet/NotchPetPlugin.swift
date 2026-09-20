import AdaEngine
import AppKit
import Math

struct NotchPetAdaPlugin: Plugin {
    @MainActor
    func setup(in app: borrowing AppWorlds) {
        NotchPetStatusItem.shared.install()
        app.insertResource(NotchPetTextures())
        app.insertResource(NotchPetBehaviorState())
        app.addSystem(NotchPetSetupSystem.self, on: .startup)
        app.addSystem(NotchPetAnimateSystem.self)
    }
}

@System
@MainActor
func NotchPetSetup(
    _ commands: Commands,
    _ textures: Res<NotchPetTextures>
) {
    var camera = Camera()
    camera.backgroundColor = .clear
    camera.clearFlags = .solid
    commands.spawn("Camera", bundle: Camera2D(camera: camera))

    let panelColor = Color(red: 0.008, green: 0.008, blue: 0.012, alpha: 0.988)
    commands.spawn("Notch background top") {
        Sprite(
            texture: Texture2D.whiteTexture,
            tintColor: panelColor,
            size: Size(width: 348, height: 129)
        )
        Transform(position: [0, 13.5, 0])
    }
    commands.spawn("Notch background bottom") {
        Sprite(
            texture: Texture2D.whiteTexture,
            tintColor: panelColor,
            size: Size(width: 294, height: 27)
        )
        Transform(position: [0, -64.5, 0])
    }
    for side: Float in [-1, 1] {
        commands.spawn("Notch rounded corner") {
            Sprite(
                texture: textures.ellipse,
                tintColor: panelColor,
                size: Size(width: 54, height: 54)
            )
            Transform(position: [side * 147, -51, 0])
        }
    }

    let glowLayers: [(Float, Float)] = [
        (172, 0.035),
        (148, 0.050),
        (124, 0.075),
        (104, 0.105),
    ]
    for (diameter, alpha) in glowLayers {
        commands.spawn("Blue halo") {
            Sprite(
                texture: textures.ellipse,
                tintColor: Color(red: 0.04, green: 0.45, blue: 0.88, alpha: alpha),
                size: Size(width: diameter, height: diameter)
            )
            Transform(position: [0, -13, 1])
            PetGlow()
        }
    }

    for side: Float in [-1, 1] {
        commands.spawn("Foot") {
            Sprite(
                texture: textures.ellipse,
                tintColor: Color(red: 0.75, green: 0.77, blue: 0.80),
                size: Size(width: 27, height: 19)
            )
            Transform(position: [side * 20, -50, 2])
            PetFoot(side: side)
        }
    }

    commands.spawn("Body") {
        Sprite(
            texture: textures.body,
            tintColor: .white,
            size: Size(width: 88, height: 102)
        )
        Transform(position: [0, -12, 3])
        PetBody()
    }

    commands.spawn("Body highlight") {
        Sprite(
            texture: textures.ellipse,
            tintColor: Color(red: 1, green: 1, blue: 1, alpha: 0.16),
            size: Size(width: 31, height: 18)
        )
        Transform(
            rotation: Quat(axis: [0, 0, 1], angle: 0.38),
            position: [-13, 13, 4]
        )
        PetHighlight()
    }

    for side: Float in [-1, 1] {
        commands.spawn("Eye") {
            Sprite(
                texture: textures.capsule,
                tintColor: Color(red: 0.01, green: 0.01, blue: 0.014),
                size: Size(width: 12, height: 29)
            )
            Transform(position: [side * 15, -14, 5])
            PetEye(side: side)
        }
    }

    commands.spawn("Thought bubble") {
        Sprite(
            texture: textures.ellipse,
            tintColor: Color(red: 0.08, green: 0.62, blue: 0.94),
            size: Size(width: 28, height: 28)
        )
        Transform(scale: Vector3(0.001), position: [-45, 25, 6])
        PetThoughtBubble()
    }

    for offset: Float in [-5, 0, 5] {
        commands.spawn("Thought dot") {
            Sprite(
                texture: textures.ellipse,
                tintColor: Color(red: 0.01, green: 0.03, blue: 0.05, alpha: 0.86),
                size: Size(width: 3.2, height: 3.2)
            )
            Transform(scale: Vector3(0.001), position: [-45 + offset, 25, 7])
            PetThoughtDot(offset: offset)
        }
    }
}

@System
@MainActor
func NotchPetAnimate(
    _ state: ResMut<NotchPetBehaviorState>,
    _ time: Res<ElapsedTime>,
    _ deltaTime: Res<DeltaTime>,
    _ input: Res<Input>,
    _ bodies: Query<Ref<Transform>, PetBody>,
    _ glows: Query<Ref<Transform>, PetGlow>,
    _ feet: Query<Ref<Transform>, PetFoot>,
    _ eyes: Query<Ref<Transform>, PetEye>,
    _ highlights: Query<Ref<Transform>, PetHighlight>,
    _ bubbles: Query<Ref<Transform>, PetThoughtBubble>,
    _ dots: Query<Ref<Transform>, PetThoughtDot>
) {
    let elapsed = time.elapsedTime
    let delta = min(deltaTime.deltaTime, 1 / 15)
    updateBehavior(state: state, elapsed: elapsed)
    updateReaction(state: state, input: input, elapsed: elapsed)
    updateEyes(state: state, eyes: eyes, elapsed: elapsed, delta: delta)

    let bob = Math.sin(elapsed * 2.05) * 2.1
    let drift = Math.sin(elapsed * 0.72) * 1.8
    let breathing = Math.sin(elapsed * 1.13) * 0.008
    let reacting = elapsed < state.reactionEndsAt

    bodies.forEach { transform, _ in
        transform.position = [drift, -12 + bob + (reacting ? 4 : 0), 3]
        transform.rotation = Quat(axis: [0, 0, 1], angle: Math.sin(elapsed * 0.83) * 0.025)
        transform.scale = reacting
            ? Vector3(1.09, 0.92, 1)
            : Vector3(1 + breathing, 1 - breathing, 1)
    }

    feet.forEach { transform, foot in
        transform.position = [foot.side * 20 + drift, -50 + bob * 0.45, 2]
        transform.rotation = Quat(axis: [0, 0, 1], angle: -foot.side * 0.20)
    }

    highlights.forEach { transform, _ in
        transform.position = [-13 + drift, 13 + bob, 4]
        transform.rotation = Quat(axis: [0, 0, 1], angle: 0.38 + Math.sin(elapsed * 0.83) * 0.025)
    }

    glows.forEach { transform, _ in
        let emphasis: Float = switch state.behavior {
        case .watching: reacting ? 1.08 : 0.92
        case .thinking: 1.10
        case .daydreaming: 0.98
        }
        let pulse = emphasis + Math.sin(elapsed * 1.25) * 0.018
        transform.position = [drift * 0.35, -13 + bob * 0.3, 1]
        transform.scale = Vector3(pulse)
    }

    let thinkingScale: Float = state.behavior == .thinking
        ? 0.95 + Math.sin(elapsed * 3.2) * 0.035
        : 0.001
    bubbles.forEach { transform, _ in
        transform.position = [-45 + drift, 25 + bob + Math.sin(elapsed * 3.2) * 1.8, 6]
        transform.scale = Vector3(thinkingScale)
    }
    dots.forEach { transform, dot in
        transform.position = [-45 + dot.offset + drift, 25 + bob + Math.sin(elapsed * 3.2) * 1.8, 7]
        transform.scale = Vector3(thinkingScale)
    }
}

@MainActor
private func updateBehavior(
    state: ResMut<NotchPetBehaviorState>,
    elapsed: Float
) {
    guard elapsed >= state.nextBehaviorChange else { return }
    switch state.behavior {
    case .watching:
        state.behavior = state.nextAmbientBehavior
        state.nextAmbientBehavior = state.nextAmbientBehavior == .thinking ? .daydreaming : .thinking
        state.nextBehaviorChange = elapsed + 6.2
    case .thinking, .daydreaming:
        state.behavior = .watching
        state.nextBehaviorChange = elapsed + 5.2
    }
}

@MainActor
private func updateReaction(
    state: ResMut<NotchPetBehaviorState>,
    input: Res<Input>,
    elapsed: Float
) {
    let pressed = input.wrappedValue.isMouseButtonPressed(.left)
    if pressed, !state.wasMousePressed {
        state.reactionEndsAt = elapsed + 0.52
        state.behavior = .watching
        state.nextBehaviorChange = elapsed + 3.6
    }
    state.wasMousePressed = pressed
}

@MainActor
private func updateEyes(
    state: ResMut<NotchPetBehaviorState>,
    eyes: Query<Ref<Transform>, PetEye>,
    elapsed: Float,
    delta: Float
) {
    if state.blinkStartedAt == nil, elapsed >= state.nextBlink {
        state.blinkStartedAt = elapsed
    }

    var blinkScale: Float = 1
    if let blinkStartedAt = state.blinkStartedAt {
        let progress = (elapsed - blinkStartedAt) / 0.18
        if progress >= 1 {
            state.blinkStartedAt = nil
            state.nextBlink = elapsed + 3.2
        } else {
            blinkScale = max(0.08, abs(Float(progress * 2 - 1)))
        }
    }

    let desiredOffset: Vector2
    switch state.behavior {
    case .thinking:
        desiredOffset = Vector2(-2.6 + Math.sin(elapsed * 1.4), 3.6)
    case .daydreaming:
        desiredOffset = Vector2(2.2 * Math.sin(elapsed * 0.9), 2.8)
    case .watching:
        desiredOffset = pointerEyeOffset()
    }

    let smoothing = min(Float(delta * 11), 1)
    state.eyeOffset += (desiredOffset - state.eyeOffset) * smoothing
    let bob = Math.sin(elapsed * 2.05) * 2.1
    let drift = Math.sin(elapsed * 0.72) * 1.8
    eyes.forEach { transform, eye in
        transform.position = [
            eye.side * 15 + state.eyeOffset.x + drift,
            -14 + state.eyeOffset.y + bob,
            5,
        ]
        transform.scale = Vector3(1, blinkScale, 1)
    }
}

@MainActor
private func pointerEyeOffset() -> Vector2 {
    guard let window = NSApp.windows.first(where: { $0.title == "Ada Notch Pet" }) ?? NSApp.windows.first else {
        return .zero
    }
    let pointer = NSEvent.mouseLocation
    let character = CGPoint(x: window.frame.midX, y: window.frame.minY + 66)
    let deltaX = Float(pointer.x - character.x)
    let deltaY = Float(pointer.y - character.y)
    let distance = max((deltaX * deltaX + deltaY * deltaY).squareRoot(), 1)
    return Vector2(deltaX / distance * 5.2, deltaY / distance * 4.4)
}
