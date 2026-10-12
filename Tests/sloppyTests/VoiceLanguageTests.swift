import Testing
@testable import sloppy

@Suite("Voice language normalization")
struct VoiceLanguageTests {
    @Test("Locale identifiers reduce to the ISO code Whisper APIs accept")
    func localeIdentifiers() {
        #expect(VoiceLanguage.normalize("ru_RU") == "ru")
        #expect(VoiceLanguage.normalize("ru-RU") == "ru")
        #expect(VoiceLanguage.normalize(" EN_us ") == "en")
        #expect(VoiceLanguage.normalize("de") == "de")
        #expect(VoiceLanguage.normalize("zh-Hans-CN") == "zh")
    }

    @Test("Auto, empty and malformed values mean automatic detection")
    func automatic() {
        #expect(VoiceLanguage.normalize(nil) == nil)
        #expect(VoiceLanguage.normalize("") == nil)
        #expect(VoiceLanguage.normalize("auto") == nil)
        #expect(VoiceLanguage.normalize("AUTO") == nil)
        #expect(VoiceLanguage.normalize("_") == nil)
        #expect(VoiceLanguage.normalize("123") == nil)
    }
}
