import AdaEngine

@Component
struct PetBody {}

@Component
struct PetGlow {}

@Component
struct PetFoot {
    let side: Float
}

@Component
struct PetEye {
    let side: Float
}

@Component
struct PetHighlight {}

@Component
struct PetThoughtBubble {}

@Component
struct PetThoughtDot {
    let offset: Float
}

struct NotchPetBehaviorState: Resource {
    enum Behavior: Sendable {
        case watching
        case thinking
        case daydreaming
    }

    var behavior: Behavior = .watching
    var nextAmbientBehavior: Behavior = .thinking
    var nextBehaviorChange: TimeInterval = 4.8
    var nextBlink: TimeInterval = 2.2
    var blinkStartedAt: TimeInterval?
    var reactionEndsAt: TimeInterval = 0
    var wasMousePressed = false
    var eyeOffset = Vector2.zero
}
