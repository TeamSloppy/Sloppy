import Testing

@testable import SloppyFeatureChat

@Suite("Chat overlay layout")
struct ChatOverlayLayoutTests {
    @Test("desktop picker starts below the current top safe area")
    func desktopPickerStartsBelowCurrentTopSafeArea() {
        let inset = ChatOverlayLayout.pickerTopInset(
            isPhone: false,
            rootSafeAreaTop: 0,
            effectiveSafeAreaTop: 144
        )

        #expect(inset == 144)
    }

    @Test("phone picker keeps mobile navigation clearance")
    func phonePickerKeepsMobileNavigationClearance() {
        let inset = ChatOverlayLayout.pickerTopInset(
            isPhone: true,
            rootSafeAreaTop: 47,
            effectiveSafeAreaTop: 139
        )

        #expect(inset == 99)
    }
}
