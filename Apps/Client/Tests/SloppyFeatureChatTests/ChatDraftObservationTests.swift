import Observation
import Synchronization
import Testing
@testable import SloppyFeatureChat

@Suite("Chat draft observation")
@MainActor
struct ChatDraftObservationTests {
    @Test("choosing a starter prompt invalidates the composer")
    func observesProgrammaticDraftChanges() {
        let draft = ChatComposerDraft()
        let changed = Mutex(false)
        withObservationTracking {
            _ = draft.text
        } onChange: {
            changed.withLock { $0 = true }
        }
        draft.text = "Explore this project and explain how it is structured."
        #expect(changed.withLock { $0 })
    }
}
