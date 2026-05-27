import Testing
@testable import sloppy

@Test
func welcomeScreenStaysHiddenWhenAutoDismissLeavesSessionContent() {
    let shouldRender = SloppyTUIWelcomeVisibility.shouldRender(
        welcomeDismissed: false,
        hasPersistedSession: false,
        hasSessionCards: true,
        hasLiveAssistantDraft: false,
        hasQueuedMessages: false,
        hasLocalCards: false,
        hasTransientNotice: false
    )

    #expect(!shouldRender)
}

@Test
func welcomeScreenStaysHiddenForPersistedEmptySession() {
    let shouldRender = SloppyTUIWelcomeVisibility.shouldRender(
        welcomeDismissed: false,
        hasPersistedSession: true,
        hasSessionCards: false,
        hasLiveAssistantDraft: false,
        hasQueuedMessages: false,
        hasLocalCards: false,
        hasTransientNotice: false
    )

    #expect(!shouldRender)
}

@Test
func welcomeScreenRendersOnlyBeforeAnyTimelineContent() {
    let shouldRender = SloppyTUIWelcomeVisibility.shouldRender(
        welcomeDismissed: false,
        hasPersistedSession: false,
        hasSessionCards: false,
        hasLiveAssistantDraft: false,
        hasQueuedMessages: false,
        hasLocalCards: false,
        hasTransientNotice: false
    )

    #expect(shouldRender)
}

@Test
func transientNoticeDoesNotHideWelcomeScreen() {
    let shouldRender = SloppyTUIWelcomeVisibility.shouldRender(
        welcomeDismissed: false,
        hasPersistedSession: false,
        hasSessionCards: false,
        hasLiveAssistantDraft: false,
        hasQueuedMessages: false,
        hasLocalCards: false,
        hasTransientNotice: true
    )

    #expect(shouldRender)
}
