import Foundation
import Testing

@Suite("Root shell theme source")
struct RootShellThemeSourceTests {
    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("root shell keeps app theme and system color scheme aligned")
    func rootShellKeepsAppThemeAndSystemColorSchemeAligned() throws {
        let source = try source("Sources/SloppyClient/Root/RootShellView.swift")

        #expect(source.contains(".theme(viewModel.settings.colorScheme.appTheme)"))
        #expect(source.contains(".preferredColorScheme(viewModel.settings.colorScheme.systemColorScheme)"))
        #expect(source.contains("var systemColorScheme: ColorScheme"))
        #expect(source.contains("theme.colors.background"))
        #expect(source.contains(".ignoresSafeArea()"))
    }
}
