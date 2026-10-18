import SwiftUI
import SloppyClientCore

public typealias ChatComposerReferenceOpenHandler = @MainActor @Sendable (ChatComposerReference, ChatScreenViewModel) -> Void

public extension EnvironmentValues {
    @Entry var chatComposerReferenceOpenHandler: ChatComposerReferenceOpenHandler? = nil
}
