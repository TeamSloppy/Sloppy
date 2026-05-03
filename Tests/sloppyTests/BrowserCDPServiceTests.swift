import Foundation
import Protocols
import Testing
@testable import sloppy

@Suite("BrowserCDPService")
struct BrowserCDPServiceTests {
    @Test("open launches configured browser and creates page")
    func openLaunchesAndCreatesPage() async throws {
        let transport = FakeBrowserCDPTransport()
        let service = BrowserCDPService(
            config: .init(enabled: true, executablePath: "/fake/chrome", profileName: "tests"),
            workspaceRootURL: FileManager.default.temporaryDirectory,
            launcher: FakeBrowserProcessLauncher(),
            transport: transport
        )

        let payload = try await service.open(sessionID: "session-1", url: "https://example.com")
        let object = payload.asObject ?? [:]

        #expect(object["browserSessionId"]?.asString?.hasPrefix("browser-") == true)
        #expect(object["pageId"]?.asString == "page-1")
        #expect(object["url"]?.asString == "https://example.com")
        #expect(object["profilePath"]?.asString?.hasSuffix("/.browser-profiles/tests") == true)
    }

    @Test("navigate click type and screenshot use fake CDP transport")
    func controlsPageThroughTransport() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("browser-cdp-\(UUID().uuidString)")
        let outputPath = temp.appendingPathComponent("shot.png").path
        let transport = FakeBrowserCDPTransport()
        let service = BrowserCDPService(
            config: .init(enabled: true, executablePath: "/fake/chrome"),
            workspaceRootURL: temp,
            launcher: FakeBrowserProcessLauncher(),
            transport: transport
        )

        _ = try await service.open(sessionID: "session-2", url: "about:blank")
        let navigated = try await service.navigate(sessionID: "session-2", pageID: nil, url: "https://sloppy.dev")
        let clicked = try await service.click(sessionID: "session-2", pageID: nil, selector: "#go")
        let typed = try await service.type(sessionID: "session-2", pageID: nil, selector: "input[name=q]", text: "hello")
        let shot = try await service.screenshot(sessionID: "session-2", pageID: nil, outputPath: outputPath)

        #expect(navigated.asObject?["url"]?.asString == "https://sloppy.dev")
        #expect(clicked.asObject?["selector"]?.asString == "#go")
        #expect(typed.asObject?["selector"]?.asString == "input[name=q]")
        #expect(shot.asObject?["path"]?.asString == outputPath)
        #expect(FileManager.default.fileExists(atPath: outputPath))
    }

    @Test("status and close report browser session lifecycle")
    func statusAndCloseReflectLifecycle() async throws {
        let service = BrowserCDPService(
            config: .init(enabled: true, executablePath: "/fake/chrome"),
            workspaceRootURL: FileManager.default.temporaryDirectory,
            launcher: FakeBrowserProcessLauncher(),
            transport: FakeBrowserCDPTransport()
        )

        _ = try await service.open(sessionID: "session-close", url: "https://example.com")
        let running = await service.status(sessionID: "session-close")
        #expect(running.asObject?["browserSessionId"]?.asString?.hasPrefix("browser-") == true)
        #expect(running.asObject?["pages"]?.asArray?.count == 1)

        let pageID = running.asObject?["pageId"]?.asString
        let pageClosed = try await service.close(sessionID: "session-close", pageID: pageID)
        #expect(pageClosed.asObject?["pages"]?.asArray?.isEmpty == true)

        _ = try await service.open(sessionID: "session-close-all", url: nil)
        let closed = try await service.close(sessionID: "session-close-all", pageID: nil)
        #expect(closed.asObject?["running"]?.asBool == false)
        #expect(closed.asObject?["browserSessionId"]?.asString?.hasPrefix("browser-") == true)
        #expect(await service.status(sessionID: "session-close-all").asObject?["running"]?.asBool == false)
    }

    @Test("disabled config rejects open")
    func disabledRejectsOpen() async {
        let service = BrowserCDPService(
            config: .init(enabled: false, executablePath: "/fake/chrome"),
            workspaceRootURL: FileManager.default.temporaryDirectory,
            launcher: FakeBrowserProcessLauncher(),
            transport: FakeBrowserCDPTransport()
        )

        await #expect(throws: BrowserCDPError.disabled) {
            _ = try await service.open(sessionID: "session-3", url: nil)
        }
    }
}

private struct FakeBrowserProcessLauncher: BrowserProcessLaunching {
    func launch(config _: CoreConfig.Browser, profileURL: URL) async throws -> BrowserLaunchResult {
        BrowserLaunchResult(process: Process(), port: 9222, profilePath: profileURL.path)
    }
}

private actor FakeBrowserCDPTransport: BrowserCDPTransport {
    private var counter = 0
    private var pages: [String: BrowserPageSnapshot] = [:]

    func newPage(port _: Int, url: String) async throws -> BrowserPageSnapshot {
        counter += 1
        let page = BrowserPageSnapshot(pageId: "page-\(counter)", url: url, title: "Fake")
        pages[page.pageId] = page
        return page
    }

    func command(pageID: String, method: String, params: JSONValue) async throws -> JSONValue {
        guard var page = pages[pageID] else {
            throw BrowserCDPError.pageNotFound
        }

        switch method {
        case "Page.navigate":
            page.url = params.asObject?["url"]?.asString ?? page.url
            pages[pageID] = page
            return .object(["result": .object([:])])
        case "Runtime.evaluate":
            return .object([
                "result": .object([
                    "result": .object([
                        "value": .object([
                            "ok": .bool(true),
                            "url": .string(page.url),
                            "title": .string(page.title),
                        ]),
                    ]),
                ]),
            ])
        case "Page.captureScreenshot":
            return .object([
                "result": .object([
                    "data": .string(Data([1, 2, 3, 4]).base64EncodedString()),
                ]),
            ])
        default:
            return .object(["result": .object([:])])
        }
    }

    func close(pageID: String) async {
        pages.removeValue(forKey: pageID)
    }
}
