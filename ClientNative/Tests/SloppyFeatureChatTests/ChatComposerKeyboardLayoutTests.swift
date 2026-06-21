import Testing

@testable import SloppyFeatureChat

@Suite("Chat composer keyboard layout")
struct ChatComposerKeyboardLayoutTests {
    @Test("phone composer keeps only a tight gap above the keyboard")
    func phoneComposerKeepsOnlyTightGapAboveKeyboard() {
        let inset = ChatComposerKeyboardLayout.phoneBottomInset(
            rootSafeAreaBottom: 34,
            effectiveSafeAreaBottom: 336,
            normalMinimumSpacing: 12,
            keyboardSpacing: 8
        )

        #expect(inset == 8)
    }

    @Test("phone composer preserves home indicator clearance without keyboard")
    func phoneComposerPreservesHomeIndicatorClearanceWithoutKeyboard() {
        let inset = ChatComposerKeyboardLayout.phoneBottomInset(
            rootSafeAreaBottom: 34,
            effectiveSafeAreaBottom: 34,
            normalMinimumSpacing: 12,
            keyboardSpacing: 8
        )

        #expect(inset == 42)
    }

    @Test("phone composer keeps minimum spacing on flat-bottom screens")
    func phoneComposerKeepsMinimumSpacingOnFlatBottomScreens() {
        let inset = ChatComposerKeyboardLayout.phoneBottomInset(
            rootSafeAreaBottom: 0,
            effectiveSafeAreaBottom: 0,
            normalMinimumSpacing: 12,
            keyboardSpacing: 8
        )

        #expect(inset == 12)
    }
}
