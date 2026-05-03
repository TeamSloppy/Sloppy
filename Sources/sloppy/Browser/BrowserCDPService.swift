import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols

enum BrowserCDPError: Error, LocalizedError, Sendable, Equatable {
    case disabled
    case executableMissing
    case launchFailed(String)
    case startupTimedOut
    case noPage
    case pageNotFound
    case selectorNotFound(String)
    case cdpFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "Browser automation is disabled in runtime config."
        case .executableMissing:
            return "Browser executable path is empty."
        case .launchFailed(let message):
            return "Failed to launch browser: \(message)"
        case .startupTimedOut:
            return "Browser did not expose a DevTools port before startup timeout."
        case .noPage:
            return "No browser page is available."
        case .pageNotFound:
            return "Browser page not found."
        case .selectorNotFound(let selector):
            return "Selector not found: \(selector)"
        case .cdpFailed(let message):
            return "Browser CDP command failed: \(message)"
        case .invalidResponse:
            return "Browser returned an invalid response."
        }
    }

    var code: String {
        switch self {
        case .disabled:
            return "browser_disabled"
        case .executableMissing:
            return "browser_executable_missing"
        case .launchFailed:
            return "browser_launch_failed"
        case .startupTimedOut:
            return "browser_startup_timed_out"
        case .noPage:
            return "browser_no_page"
        case .pageNotFound:
            return "browser_page_not_found"
        case .selectorNotFound:
            return "browser_selector_not_found"
        case .cdpFailed:
            return "browser_cdp_failed"
        case .invalidResponse:
            return "browser_invalid_response"
        }
    }
}

struct BrowserPageSnapshot: Sendable, Equatable {
    var pageId: String
    var url: String
    var title: String
}

struct BrowserLaunchResult: @unchecked Sendable {
    var process: Process
    var port: Int
    var profilePath: String
}

protocol BrowserProcessLaunching: Sendable {
    func launch(config: CoreConfig.Browser, profileURL: URL) async throws -> BrowserLaunchResult
}

protocol BrowserCDPTransport: Sendable {
    func newPage(port: Int, url: String) async throws -> BrowserPageSnapshot
    func command(pageID: String, method: String, params: JSONValue) async throws -> JSONValue
    func close(pageID: String) async
}

struct ChromiumProcessLauncher: BrowserProcessLaunching {
    func launch(config: CoreConfig.Browser, profileURL: URL) async throws -> BrowserLaunchResult {
        let executable = config.executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !executable.isEmpty else {
            throw BrowserCDPError.executableMissing
        }

        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        let activePortURL = profileURL.appendingPathComponent("DevToolsActivePort")
        try? FileManager.default.removeItem(at: activePortURL)

        let process = Process()
        var arguments = [
            "--remote-debugging-port=0",
            "--user-data-dir=\(profileURL.path)",
            "--no-first-run",
            "--no-default-browser-check",
        ]
        if config.headless {
            arguments.append("--headless=new")
        }
        arguments.append(contentsOf: config.additionalArguments.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        arguments.append("about:blank")

        if executable.hasPrefix("/") || executable.hasPrefix("./") || executable.hasPrefix("../") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.environment = childProcessEnvironment()

        do {
            try process.run()
        } catch {
            throw BrowserCDPError.launchFailed(error.localizedDescription)
        }

        let timeoutNs = UInt64(max(500, config.startupTimeoutMs)) * 1_000_000
        let startedAt = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - startedAt < timeoutNs {
            if !process.isRunning {
                throw BrowserCDPError.launchFailed("process exited with code \(process.terminationStatus)")
            }
            if let port = readDevToolsPort(at: activePortURL) {
                return BrowserLaunchResult(process: process, port: port, profilePath: profileURL.path)
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        if process.isRunning {
            process.terminate()
        }
        throw BrowserCDPError.startupTimedOut
    }

    private func readDevToolsPort(at url: URL) -> Int? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return text
            .split(whereSeparator: \.isNewline)
            .first
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}

actor URLSessionBrowserCDPTransport: BrowserCDPTransport {
    private var clients: [String: CDPWebSocketClient] = [:]

    func newPage(port: Int, url: String) async throws -> BrowserPageSnapshot {
        let encodedURL = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "about:blank"
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/json/new?\(encodedURL)")!)
        request.httpMethod = "PUT"
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BrowserCDPError.cdpFailed("new page returned HTTP \(http.statusCode)")
        }
        let target = try JSONDecoder().decode(DevToolsTarget.self, from: data)
        guard let ws = target.webSocketDebuggerURL, let wsURL = URL(string: ws) else {
            throw BrowserCDPError.invalidResponse
        }
        let client = CDPWebSocketClient(url: wsURL)
        try await client.connect()
        clients[target.id] = client
        let info = try await pageInfo(pageID: target.id, client: client)
        return BrowserPageSnapshot(pageId: target.id, url: info.url, title: info.title)
    }

    func command(pageID: String, method: String, params: JSONValue) async throws -> JSONValue {
        guard let client = client(pageID: pageID) else {
            throw BrowserCDPError.pageNotFound
        }
        return try await client.send(method: method, params: params)
    }

    func close(pageID: String) async {
        let client = clients.removeValue(forKey: pageID)
        await client?.close()
    }

    private func client(pageID: String) -> CDPWebSocketClient? {
        clients[pageID]
    }

    private func pageInfo(pageID: String, client: CDPWebSocketClient) async throws -> BrowserPageSnapshot {
        let expression = "({ url: location.href, title: document.title })"
        let result = try await client.send(
            method: "Runtime.evaluate",
            params: .object([
                "expression": .string(expression),
                "returnByValue": .bool(true),
            ])
        )
        let value = result.asObject?["result"]?.asObject?["result"]?.asObject?["value"]?.asObject ?? [:]
        return BrowserPageSnapshot(
            pageId: pageID,
            url: value["url"]?.asString ?? "",
            title: value["title"]?.asString ?? ""
        )
    }
}

public actor BrowserCDPService {
    private struct BrowserSession {
        var id: String
        var sessionID: String
        var process: Process
        var port: Int
        var profilePath: String
        var pages: [String: BrowserPageSnapshot]
    }

    private var config: CoreConfig.Browser
    private var workspaceRootURL: URL
    private let launcher: any BrowserProcessLaunching
    private let transport: any BrowserCDPTransport
    private var sessionsByAgentSession: [String: BrowserSession] = [:]

    init(
        config: CoreConfig.Browser = CoreConfig.Browser(),
        workspaceRootURL: URL,
        launcher: any BrowserProcessLaunching = ChromiumProcessLauncher(),
        transport: any BrowserCDPTransport = URLSessionBrowserCDPTransport()
    ) {
        self.config = config
        self.workspaceRootURL = workspaceRootURL
        self.launcher = launcher
        self.transport = transport
    }

    func updateConfig(_ config: CoreConfig.Browser, workspaceRootURL: URL) async {
        self.config = config
        self.workspaceRootURL = workspaceRootURL
        if !config.enabled {
            shutdown()
        }
    }

    func open(sessionID: String, url: String?) async throws -> JSONValue {
        let session = try await ensureSession(sessionID: sessionID)
        let page = try await transport.newPage(port: session.port, url: normalizedURL(url))
        var updated = session
        updated.pages[page.pageId] = page
        sessionsByAgentSession[sessionID] = updated
        return sessionPayload(updated, activePage: page)
    }

    func navigate(sessionID: String, pageID: String?, url: String) async throws -> JSONValue {
        let pageID = try resolvePageID(sessionID: sessionID, pageID: pageID)
        _ = try await transport.command(
            pageID: pageID,
            method: "Page.navigate",
            params: .object(["url": .string(url)])
        )
        let page = try await pageInfo(pageID: pageID)
        updatePage(sessionID: sessionID, page: page)
        return pagePayload(page)
    }

    func click(sessionID: String, pageID: String?, selector: String) async throws -> JSONValue {
        let pageID = try resolvePageID(sessionID: sessionID, pageID: pageID)
        let result = try await evaluate(pageID: pageID, expression: clickExpression(selector: selector))
        try throwIfSelectorMissing(result, selector: selector)
        let page = try await pageInfo(pageID: pageID)
        updatePage(sessionID: sessionID, page: page)
        return pagePayload(page, extra: ["selector": .string(selector)])
    }

    func type(sessionID: String, pageID: String?, selector: String, text: String) async throws -> JSONValue {
        let pageID = try resolvePageID(sessionID: sessionID, pageID: pageID)
        let result = try await evaluate(pageID: pageID, expression: typeExpression(selector: selector, text: text))
        try throwIfSelectorMissing(result, selector: selector)
        let page = try await pageInfo(pageID: pageID)
        updatePage(sessionID: sessionID, page: page)
        return pagePayload(page, extra: ["selector": .string(selector)])
    }

    func screenshot(sessionID: String, pageID: String?, outputPath: String?) async throws -> JSONValue {
        let pageID = try resolvePageID(sessionID: sessionID, pageID: pageID)
        let response = try await transport.command(
            pageID: pageID,
            method: "Page.captureScreenshot",
            params: .object(["format": .string("png"), "fromSurface": .bool(true)])
        )
        guard let base64 = response.asObject?["result"]?.asObject?["data"]?.asString,
              let imageData = Data(base64Encoded: base64)
        else {
            throw BrowserCDPError.invalidResponse
        }
        let outputURL = URL(fileURLWithPath: outputPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("sloppy-browser-\(UUID().uuidString.lowercased()).png")
                .path)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try imageData.write(to: outputURL, options: .atomic)
        return .object([
            "pageId": .string(pageID),
            "path": .string(outputURL.path),
            "bytes": .number(Double(imageData.count)),
        ])
    }

    func status(sessionID: String) -> JSONValue {
        guard let session = sessionsByAgentSession[sessionID] else {
            return .object(["running": .bool(false), "pages": .array([])])
        }
        return sessionPayload(session, activePage: session.pages.values.sorted { $0.pageId < $1.pageId }.first)
    }

    func close(sessionID: String, pageID: String?) async throws -> JSONValue {
        guard var session = sessionsByAgentSession[sessionID] else {
            return .object(["running": .bool(false)])
        }
        if let pageID, !pageID.isEmpty {
            session.pages.removeValue(forKey: pageID)
            await transport.close(pageID: pageID)
            sessionsByAgentSession[sessionID] = session
            return sessionPayload(session, activePage: nil)
        }
        for pageID in session.pages.keys {
            await transport.close(pageID: pageID)
        }
        if session.process.isRunning {
            session.process.terminate()
        }
        sessionsByAgentSession.removeValue(forKey: sessionID)
        return .object(["running": .bool(false), "browserSessionId": .string(session.id)])
    }

    func cleanup(sessionID: String) async {
        _ = try? await close(sessionID: sessionID, pageID: nil)
    }

    func shutdown() {
        for (_, session) in sessionsByAgentSession {
            if session.process.isRunning {
                session.process.terminate()
            }
        }
        sessionsByAgentSession.removeAll()
    }

    private func ensureSession(sessionID: String) async throws -> BrowserSession {
        if let session = sessionsByAgentSession[sessionID], session.process.isRunning {
            return session
        }
        guard config.enabled else {
            throw BrowserCDPError.disabled
        }
        guard !config.executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BrowserCDPError.executableMissing
        }
        let profileURL = resolvedProfileURL(config: config)
        let launch = try await launcher.launch(config: config, profileURL: profileURL)
        let session = BrowserSession(
            id: "browser-\(UUID().uuidString.lowercased())",
            sessionID: sessionID,
            process: launch.process,
            port: launch.port,
            profilePath: launch.profilePath,
            pages: [:]
        )
        sessionsByAgentSession[sessionID] = session
        return session
    }

    private func resolvedProfileURL(config: CoreConfig.Browser) -> URL {
        let override = config.profilePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !override.isEmpty {
            return resolvePath(override, base: workspaceRootURL)
        }
        let safeName = config.profileName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "default"
        return workspaceRootURL
            .appendingPathComponent(".browser-profiles", isDirectory: true)
            .appendingPathComponent(safeName, isDirectory: true)
    }

    private func resolvePath(_ raw: String, base: URL) -> URL {
        if raw == "~" || raw.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let suffix = raw == "~" ? "" : String(raw.dropFirst(2))
            return suffix.isEmpty ? home : home.appendingPathComponent(suffix)
        }
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
        return base.appendingPathComponent(raw, isDirectory: true)
    }

    private func resolvePageID(sessionID: String, pageID: String?) throws -> String {
        guard let session = sessionsByAgentSession[sessionID] else {
            throw BrowserCDPError.noPage
        }
        if let pageID = pageID?.trimmingCharacters(in: .whitespacesAndNewlines), !pageID.isEmpty {
            guard session.pages[pageID] != nil else {
                throw BrowserCDPError.pageNotFound
            }
            return pageID
        }
        guard let first = session.pages.values.sorted(by: { $0.pageId < $1.pageId }).first else {
            throw BrowserCDPError.noPage
        }
        return first.pageId
    }

    private func pageInfo(pageID: String) async throws -> BrowserPageSnapshot {
        let result = try await evaluate(pageID: pageID, expression: "({ url: location.href, title: document.title })")
        let value = result.asObject?["result"]?.asObject?["result"]?.asObject?["value"]?.asObject ?? [:]
        return BrowserPageSnapshot(
            pageId: pageID,
            url: value["url"]?.asString ?? "",
            title: value["title"]?.asString ?? ""
        )
    }

    private func evaluate(pageID: String, expression: String) async throws -> JSONValue {
        let response = try await transport.command(
            pageID: pageID,
            method: "Runtime.evaluate",
            params: .object([
                "expression": .string(expression),
                "returnByValue": .bool(true),
                "awaitPromise": .bool(true),
            ])
        )
        if let exception = response.asObject?["result"]?.asObject?["exceptionDetails"] {
            throw BrowserCDPError.cdpFailed(String(describing: exception))
        }
        return response
    }

    private func updatePage(sessionID: String, page: BrowserPageSnapshot) {
        guard var session = sessionsByAgentSession[sessionID] else {
            return
        }
        session.pages[page.pageId] = page
        sessionsByAgentSession[sessionID] = session
    }

    private func throwIfSelectorMissing(_ response: JSONValue, selector: String) throws {
        let value = response.asObject?["result"]?.asObject?["result"]?.asObject?["value"]?.asObject
        if value?["ok"]?.asBool == false {
            throw BrowserCDPError.selectorNotFound(selector)
        }
    }

    private func normalizedURL(_ url: String?) -> String {
        let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "about:blank" : trimmed
    }

    private func sessionPayload(_ session: BrowserSession, activePage: BrowserPageSnapshot?) -> JSONValue {
        .object([
            "browserSessionId": .string(session.id),
            "running": .bool(session.process.isRunning),
            "pid": .number(Double(session.process.processIdentifier)),
            "port": .number(Double(session.port)),
            "profilePath": .string(session.profilePath),
            "pageId": activePage.map { .string($0.pageId) } ?? .null,
            "url": activePage.map { .string($0.url) } ?? .null,
            "title": activePage.map { .string($0.title) } ?? .null,
            "pages": .array(session.pages.values.sorted { $0.pageId < $1.pageId }.map { pagePayload($0) }),
        ])
    }

    private func pagePayload(_ page: BrowserPageSnapshot, extra: [String: JSONValue] = [:]) -> JSONValue {
        var payload = extra
        payload["pageId"] = .string(page.pageId)
        payload["url"] = .string(page.url)
        payload["title"] = .string(page.title)
        return .object(payload)
    }

    private func clickExpression(selector: String) -> String {
        """
        (() => {
          const el = document.querySelector(\(jsString(selector)));
          if (!el) return { ok: false };
          el.scrollIntoView({ block: "center", inline: "center" });
          const rect = el.getBoundingClientRect();
          const x = rect.left + rect.width / 2;
          const y = rect.top + rect.height / 2;
          const opts = { bubbles: true, cancelable: true, clientX: x, clientY: y, view: window };
          el.dispatchEvent(new MouseEvent("mouseover", opts));
          el.dispatchEvent(new MouseEvent("mousedown", opts));
          el.dispatchEvent(new MouseEvent("mouseup", opts));
          el.click();
          return { ok: true, x, y, url: location.href, title: document.title };
        })()
        """
    }

    private func typeExpression(selector: String, text: String) -> String {
        """
        (() => {
          const el = document.querySelector(\(jsString(selector)));
          if (!el) return { ok: false };
          el.focus();
          const value = \(jsString(text));
          if ("value" in el) {
            const start = typeof el.selectionStart === "number" ? el.selectionStart : el.value.length;
            const end = typeof el.selectionEnd === "number" ? el.selectionEnd : el.value.length;
            el.value = el.value.slice(0, start) + value + el.value.slice(end);
            const caret = start + value.length;
            if (typeof el.setSelectionRange === "function") el.setSelectionRange(caret, caret);
            el.dispatchEvent(new InputEvent("input", { bubbles: true, data: value, inputType: "insertText" }));
            el.dispatchEvent(new Event("change", { bubbles: true }));
          } else {
            document.execCommand("insertText", false, value);
          }
          return { ok: true, url: location.href, title: document.title };
        })()
        """
    }

    private func jsString(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

private struct DevToolsTarget: Decodable {
    var id: String
    var webSocketDebuggerURL: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case webSocketDebuggerURL = "webSocketDebuggerUrl"
    }
}

private actor CDPWebSocketClient {
    private let url: URL
    private var task: URLSessionWebSocketTask?
    private var nextID = 1

    init(url: URL) {
        self.url = url
    }

    func connect() async throws {
        let task = URLSession.shared.webSocketTask(with: url)
        self.task = task
        task.resume()
    }

    func send(method: String, params: JSONValue) async throws -> JSONValue {
        guard let task else {
            throw BrowserCDPError.cdpFailed("websocket is not connected")
        }
        let id = nextID
        nextID += 1
        let payload: JSONValue = .object([
            "id": .number(Double(id)),
            "method": .string(method),
            "params": params,
        ])
        let data = try JSONEncoder().encode(payload)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))

        while true {
            let message = try await task.receive()
            let text: String
            switch message {
            case .string(let value):
                text = value
            case .data(let data):
                text = String(decoding: data, as: UTF8.self)
            @unknown default:
                continue
            }
            guard let responseData = text.data(using: .utf8),
                  let response = try? JSONDecoder().decode(JSONValue.self, from: responseData),
                  response.asObject?["id"]?.asInt == id
            else {
                continue
            }
            if let error = response.asObject?["error"] {
                throw BrowserCDPError.cdpFailed(String(describing: error))
            }
            return response
        }
    }

    func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
