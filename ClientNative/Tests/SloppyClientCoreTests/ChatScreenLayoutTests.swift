import Foundation
import Testing

@Suite("Chat screen layout")
struct ChatScreenLayoutTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("phone chat layout avoids geometry reader on first render")
    func phoneChatLayoutAvoidsGeometryReaderOnFirstRender() throws {
        let source = try source("Sources", "SloppyFeatureChat", "ChatScreen.swift")

        #expect(source.contains("if idiom == .phone"))
        #expect(source.contains("chromeLayout(contentWidth: phoneContentWidth)"))
        #expect(source.contains("private var phoneContentWidth: CGFloat"))
        #expect(source.contains("screenPointWidth - rootSafeAreaInsets.leading - rootSafeAreaInsets.trailing"))
    }

    @Test("mobile composer expands to available width with dedicated circle buttons")
    func mobileComposerExpandsToAvailableWidthWithDedicatedCircleButtons() throws {
        let source = try source("Sources", "SloppyFeatureChat", "ChatComposerView.swift")

        #expect(source.contains("private struct MobileComposerCircleButton"))
        #expect(source.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(source.contains(".frame(width: ChatComposerView.phoneCircleSize, height: ChatComposerView.phoneCircleSize)"))
        #expect(source.contains(".buttonStyle(DefaultButtonStyle())"))
        #expect(source.contains(".glassEffect(.regular, in: GlassShape.capsule)"))
        #expect(!source.contains(".debugOverlay(.layoutBounds)"))
    }

    @Test("agent picker uses liquid glass styling")
    func agentPickerUsesLiquidGlassStyling() throws {
        let source = try source("Sources", "SloppyFeatureChat", "AgentPickerView.swift")

        #expect(source.contains("glassEffect(.regular.tint("))
        #expect(source.contains("RoundedRectangle(cornerRadius: 28)"))
        #expect(source.contains("private struct AgentPickerRow"))
    }
}
