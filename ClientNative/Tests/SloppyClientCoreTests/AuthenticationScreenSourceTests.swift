import Foundation
import Testing

@Suite("Authentication screen source")
struct AuthenticationScreenSourceTests {
    @Test("Uses the Sloppy logo and exposes login fields to Password AutoFill")
    func logoAndPasswordAutoFillSemantics() throws {
        let source = try String(contentsOf: authenticationScreenURL, encoding: .utf8)

        #expect(source.contains("SloppyAssets.projectLogo"))
        #expect(source.contains(".renderingMode(.template)"))
        #expect(source.contains(".foregroundColor(c.textMuted)"))
        #expect(source.contains(".textContentType(.username)"))
        #expect(source.contains(".textContentType(.password)"))
    }

    private var authenticationScreenURL: URL {
        packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("SloppyClient")
            .appendingPathComponent("Root")
            .appendingPathComponent("AuthenticationScreen.swift")
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
