import Foundation
import Testing

@Suite("Sloppy shell rendering")
struct SloppyShellRenderingTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("main split layout is wrapped in immersive glass shell")
    func mainSplitLayoutIsWrappedInImmersiveGlassShell() throws {
        let mainView = try source("Sources", "SloppyClient", "MainView.swift")
        let shell = try source("Sources", "SloppyClient", "SloppyGlassShell.swift")

        #expect(mainView.contains("SloppyGlassShell"))
        #expect(shell.contains("RoundedRectangle(cornerRadius: Self.cornerRadius)"))
        #expect(shell.contains(".mask(shape)"))
        #expect(shell.contains(".allowsHitTesting(false)"))
    }

    @Test("glass shell composes blur and edge glow")
    func glassShellComposesBlurAndEdgeGlow() throws {
        let shell = try source("Sources", "SloppyClient", "SloppyGlassShell.swift")

        #expect(shell.contains("glassEffect("))
        #expect(shell.contains("SloppyShaderEffects.edgeGlow"))
        #expect(shell.contains("LinearGradient"))
    }
}
