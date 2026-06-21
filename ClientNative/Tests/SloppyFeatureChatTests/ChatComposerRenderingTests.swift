import Foundation
import Testing

@Suite("ChatComposer rendering")
struct ChatComposerRenderingTests {
    private var chatComposerSource: String {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let sourceURL = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppyFeatureChat")
                .appendingPathComponent("ChatComposerView.swift")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
    }

    @Test("composer text field uses white caret")
    func composerTextFieldUsesWhiteCaret() throws {
        let source = try chatComposerSource

        #expect(source.contains(".accentColor(.white)"))
    }

    @Test("mobile composer action buttons are circular")
    func mobileComposerActionButtonsAreCircular() throws {
        let source = try chatComposerSource

        #expect(source.contains("private struct MobileComposerCircleButton"))
        #expect(source.contains(".frame(width: ChatComposerView.phoneCircleSize, height: ChatComposerView.phoneCircleSize)"))
        #expect(source.contains("Circle()"))
        #expect(source.contains(".glassEffect(.regular, in: Circle())"))
        #expect(source.contains(".buttonStyle(DefaultButtonStyle())"))
        #expect(!source.contains(".buttonStyle(.glass)"))
    }
}
