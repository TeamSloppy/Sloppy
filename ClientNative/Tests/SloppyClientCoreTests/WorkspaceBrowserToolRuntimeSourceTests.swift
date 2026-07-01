import Foundation
import Testing

@Suite("Workspace browser tool runtime source")
struct WorkspaceBrowserToolRuntimeSourceTests {
    private func source(_ path: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("browser runtime exposes the planned command surface")
    func browserRuntimeExposesPlannedCommandSurface() throws {
        let runtime = try source("Sources/SloppyClient/WorkspaceBrowserToolRuntime.swift")

        #expect(runtime.contains("final class WorkspaceBrowserToolRuntime"))
        #expect(runtime.contains("func open(url: String) async throws"))
        #expect(runtime.contains("func read() async throws"))
        #expect(runtime.contains("func click(selector: String) async throws"))
        #expect(runtime.contains("func type(selector: String, text: String) async throws"))
        #expect(runtime.contains("func scroll(x: Double, y: Double) async throws"))
        #expect(runtime.contains("func scrollTo(selector: String) async throws"))
        #expect(runtime.contains("func screenshot() async throws"))
    }

    @Test("browser runtime stays out of chat screen view model")
    func browserRuntimeStaysOutOfChatScreenViewModel() throws {
        let chatVM = try source("Sources/SloppyFeatureChat/ChatScreenViewModel.swift")
        #expect(!chatVM.contains("WorkspaceBrowserToolRuntime"))
    }
}
