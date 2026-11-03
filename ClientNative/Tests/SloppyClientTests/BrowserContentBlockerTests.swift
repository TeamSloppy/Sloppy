#if os(macOS)
import Foundation
import AppKit
import WebKit
import Testing
import SloppyClientCore
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser ad blocking", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserContentBlockerTests {
    nonisolated private static let rules = """
    [{"trigger":{"url-filter":"/ad-resource"},"action":{"type":"block"}},
     {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".advert"}}]
    """

    private func fixture(json: String = Self.rules,
                         fetch: @escaping BrowserFilterRepository.Fetch = { _ in throw URLError(.notConnectedToInternet) }) throws
        -> (BrowserContentBlocker, BrowserFilterRepository, UserDefaults, URL) {
        let root = URL.temporaryDirectory.appending(path: "sloppy-blocker-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bundle = root.appending(path: "bundle.json")
        try Data(json.utf8).write(to: bundle)
        let repository = BrowserFilterRepository(cacheURL: root.appending(path: "cache.json"), bundledURL: bundle, fetch: fetch)
        let defaults = try #require(UserDefaults(suiteName: "sloppy-blocker-tests.\(UUID())"))
        let blocker = BrowserContentBlocker(defaults: defaults, repository: repository,
                                            identifierPrefix: "sloppy-blocker-tests.\(UUID()).")
        blocker.setAutomaticUpdates(false)
        return (blocker, repository, defaults, root)
    }

    @Test func blocksRequestsAndHidesAdsBeforeFirstNavigationAndSupportsSiteExceptions() async throws {
        let (blocker, _, defaults, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = try BrowserHTTPFixture(responseDelay: 0, html: "<div class='advert'>Ad</div><div class='other'>Other extension</div><p>Article</p>")
        let url = try await server.start()
        let runtime = WorkspaceBrowserToolRuntime(contentBlocker: blocker)
        try server.allowHTTP(in: runtime)
        let external = try #require(try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "sloppy-external-test.\(UUID())", encodedContentRuleList:
                "[{\"trigger\":{\"url-filter\":\".*\"},\"action\":{\"type\":\"css-display-none\",\"selector\":\".other\"}}]"))
        runtime.webView.configuration.userContentController.add(external)
        runtime.webView.configuration.userContentController.addUserScript(WKUserScript(source: "window.otherScript = 42;", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        _ = try await runtime.open(url: url.absoluteString)
        #expect(blocker.isReady)
        #expect(try await fetchAd(runtime) == false)
        #expect(try await runtime.evaluate(expression: "getComputedStyle(document.querySelector('.advert')).display") == .string("none"))

        await blocker.setSiteEnabled(false, for: url)
        _ = try await runtime.open(url: url.absoluteString)
        #expect(try await fetchAd(runtime) == true)
        #expect(try await runtime.evaluate(expression: "getComputedStyle(document.querySelector('.advert')).display") != .string("none"))
        let restored = BrowserContentBlocker(defaults: defaults)
        #expect(!restored.isSiteEnabled(url))
        #expect(restored.disabledSites == ["127.0.0.1"])

        await blocker.removeException("127.0.0.1")
        _ = try await runtime.open(url: url.absoluteString)
        #expect(try await fetchAd(runtime) == false)
        await blocker.setEnabled(false)
        _ = try await runtime.open(url: url.absoluteString)
        #expect(try await fetchAd(runtime) == true)
        #expect(try await runtime.evaluate(expression: "getComputedStyle(document.querySelector('.other')).display") == .string("none"))
        #expect(try await runtime.evaluate(expression: "window.otherScript") == .number(42))
        await blocker.setEnabled(true)
        _ = try await runtime.open(url: url.absoluteString)
        #expect(try await fetchAd(runtime) == false)
    }

    @Test func siteExceptionAppliesToCrossOriginFramesAndDoesNotFollowNavigationToOtherHosts() async throws {
        let (blocker, _, _, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let child = try BrowserHTTPFixture(responseDelay: 0, html: """
        <script>fetch('/ad-resource').then(() => parent.postMessage('allowed', '*')).catch(() => parent.postMessage('blocked', '*'));</script>
        """)
        let childURL = try await child.start()
        let parent = try BrowserHTTPFixture(responseDelay: 0, html: """
        <script>addEventListener('message', e => window.frameResult = e.data);</script>
        <iframe src='\(childURL)'></iframe>
        """)
        let url = try await parent.start()
        var components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        components.host = "localhost"
        let localhost = try #require(components.url)
        await blocker.setSiteEnabled(false, for: localhost)
        let runtime = WorkspaceBrowserToolRuntime(contentBlocker: blocker)
        try parent.allowHTTP(in: runtime)
        _ = try await runtime.open(url: localhost.absoluteString)
        #expect(try await frameResult(runtime) == .string("allowed"))
        _ = try await runtime.open(url: url.absoluteString)
        #expect(try await frameResult(runtime) == .string("blocked"))
    }

    @Test func exceptionsMatchDomainBoundariesAndSubdomains() async throws {
        let (blocker, _, _, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let site = try #require(URL(string: "https://Example.COM./news"))
        await blocker.setSiteEnabled(false, for: site)
        #expect(!blocker.isSiteEnabled(URL(string: "https://shop.example.com")))
        #expect(blocker.isSiteEnabled(URL(string: "https://example.com.evil.org")))
        #expect(blocker.isSiteEnabled(URL(string: "https://notexample.com")))
        let rules = try BrowserContentBlocker.rules(Self.rules, excluding: blocker.disabledSites)
        let objects = try #require(JSONSerialization.jsonObject(with: Data(rules.utf8)) as? [[String: Any]])
        let trigger = try #require(objects.last?["trigger"] as? [String: Any])
        let pattern = try #require((trigger["if-top-url"] as? [String])?.first)
        let regex = try NSRegularExpression(pattern: pattern)
        for address in ["https://example.com/", "https://a.example.com:8080/", "http://example.com./"] {
            #expect(regex.firstMatch(in: address, range: NSRange(address.startIndex..., in: address)) != nil)
        }
        for address in ["https://example.com.evil.org/", "https://evil.org/example.com/", "https://notexample.com/"] {
            #expect(regex.firstMatch(in: address, range: NSRange(address.startIndex..., in: address)) == nil)
        }
    }

    @Test func failedOrUncompilableUpdatePreservesWorkingCacheAndProtection() async throws {
        let bad = Data("[{\"trigger\":{\"url-filter\":\"[\"},\"action\":{\"type\":\"block\"}}]".utf8)
        let (blocker, repository, _, root) = try fixture(fetch: { request in
            (bad, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        defer { try? FileManager.default.removeItem(at: root) }
        let original = BrowserFilterRepository.Snapshot(json: Self.rules, checkedAt: Date(timeIntervalSince1970: 100))
        try await repository.save(original)
        await blocker.prepare()
        await blocker.update()
        #expect(blocker.isReady)
        #expect(blocker.lastError != nil)
        #expect(blocker.lastCheckedAt == original.checkedAt)
        #expect(await repository.cached()?.json == original.json)
        let server = try BrowserHTTPFixture(responseDelay: 0)
        let url = try await server.start()
        let runtime = WorkspaceBrowserToolRuntime(contentBlocker: blocker)
        try server.allowHTTP(in: runtime)
        _ = try await runtime.open(url: url.absoluteString)
        #expect(try await fetchAd(runtime) == false)
    }

    @Test func successfulUpdateIsSavedAndConditional304RetainsRules() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let log = FilterRequestLog()
        let (blocker, repository, _, root) = try fixture(fetch: { request in
            await log.record(request)
            if request.value(forHTTPHeaderField: "If-None-Match") == "fixture-v1" {
                return (Data(), HTTPURLResponse(url: request.url!, statusCode: 304, httpVersion: nil, headerFields: nil)!)
            }
            return (Data(Self.rules.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                                          headerFields: ["ETag": "fixture-v1"])!)
        })
        defer { try? FileManager.default.removeItem(at: root) }
        await blocker.update(now: now)
        #expect(blocker.lastError == nil)
        #expect(await repository.cached()?.etag == "fixture-v1")
        await blocker.update(now: now.addingTimeInterval(30))
        #expect(blocker.lastCheckedAt == now.addingTimeInterval(30))
        #expect(await log.requests.count == 2)
        #expect(await log.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "fixture-v1")
    }

    @Test func bundledEasyListCompilesWithoutNetwork() async throws {
        let defaults = try #require(UserDefaults(suiteName: "sloppy-blocker-bundle.\(UUID())"))
        let root = URL.temporaryDirectory.appending(path: "sloppy-blocker-bundle-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let bundledURL = try #require(BrowserContentBlocker.bundledFilterURL)
        let repository = BrowserFilterRepository(cacheURL: root.appending(path: "cache.json"), bundledURL: bundledURL)
        let blocker = BrowserContentBlocker(defaults: defaults, repository: repository, identifierPrefix: "sloppy-bundle-tests.")
        blocker.setAutomaticUpdates(false)
        await blocker.prepare()
        #expect(blocker.isReady)
        #expect(blocker.ruleCount > 40_000)
        #expect(blocker.lastError == nil)
    }

    @Test func rejectsInvalidFilterData() throws {
        for invalid in ["[]", "<html>error</html>", "[{\"action\":{\"type\":\"block\"}}]",
                        "[{\"trigger\":{\"url-filter\":\".*\"},\"action\":{\"type\":\"redirect\"}}]"] {
            #expect(throws: (any Error).self) { try BrowserFilterRepository.validatedJSON(Data(invalid.utf8)) }
        }
    }

    @Test(arguments: [0, 404, 503])
    func networkAndHTTPFailuresKeepProtection(status: Int) async throws {
        let (blocker, repository, _, root) = try fixture(fetch: { request in
            if status == 0 { throw URLError(.notConnectedToInternet) }
            return (Data("unavailable".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        defer { try? FileManager.default.removeItem(at: root) }
        // Corrupt disk cache must fall back to the bundled list.
        try Data("broken cache".utf8).write(to: root.appending(path: "cache.json"))
        await blocker.prepare()
        #expect(blocker.isReady)
        #expect(blocker.ruleCount == 2)
        await blocker.update()
        #expect(blocker.isReady)
        #expect(blocker.lastError != nil)
        #expect(blocker.lastCheckedAt == nil)
        #expect(await repository.cached() == nil)
    }

    @Test func automaticUpdatesCheckDailyAndCoalesceOverlappingRequests() async throws {
        let log = FilterRequestLog()
        let (blocker, _, _, root) = try fixture(fetch: { request in
            await log.record(request)
            try await Task.sleep(for: .milliseconds(25))
            return (Data(Self.rules.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        defer { try? FileManager.default.removeItem(at: root) }
        await blocker.prepare()
        let now = Date()
        blocker.setAutomaticUpdates(true)
        await blocker.update(now: now)
        #expect(await log.requests.count == 1)
        blocker.scheduleAutomaticUpdate(now: now.addingTimeInterval(120))
        try await Task.sleep(for: .milliseconds(50))
        #expect(await log.requests.count == 1)
        blocker.scheduleAutomaticUpdate(now: now.addingTimeInterval(24 * 60 * 60 + 1))
        for _ in 0..<200 {
            if await log.requests.count == 2, !blocker.isUpdating { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await log.requests.count == 2)
        #expect(blocker.lastError == nil)
        blocker.setAutomaticUpdates(false)
        blocker.scheduleAutomaticUpdate(now: now.addingTimeInterval(3 * 24 * 60 * 60))
        try await Task.sleep(for: .milliseconds(50))
        #expect(await log.requests.count == 2)
    }

    private func fetchAd(_ runtime: WorkspaceBrowserToolRuntime) async throws -> Bool {
        try await runtime.evaluate(expression: "fetch('/ad-resource', {cache:'no-store'}).then(() => true).catch(() => false)") == .bool(true)
    }

    private func frameResult(_ runtime: WorkspaceBrowserToolRuntime) async throws -> WorkspaceBrowserJSONValue {
        try await runtime.evaluate(expression: """
        new Promise(resolve => {
          let attempts = 0;
          const timer = setInterval(() => {
            if (window.frameResult || ++attempts > 100) { clearInterval(timer); resolve(window.frameResult || 'timeout'); }
          }, 30);
        })
        """)
    }
}

private actor FilterRequestLog {
    var requests: [URLRequest] = []
    func record(_ request: URLRequest) { requests.append(request) }
}
#endif
