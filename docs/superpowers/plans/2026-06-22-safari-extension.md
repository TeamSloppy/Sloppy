# SafariExtension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `Apps/SafariExtension/`, a separate Apple app project that ships a Safari Web Extension with an in-page side panel for sending selected text and page metadata to a local/LAN Sloppy Core server.

**Architecture:** The extension uses a content-script drawer as the side panel instead of a browser-native side panel API, preserving portability across Safari on macOS, iOS, iPadOS, and visionOS. The drawer builds a typed browser-context request and posts it to a narrow Sloppy Core endpoint that creates or reuses an agent session and forwards a structured prompt through existing session orchestration. The containing SwiftUI app owns settings for Core URL, auth token, and default agent ID.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftUI, XcodeGen, Safari Web Extension resources, JavaScript ES modules, local/LAN HTTP API, existing Sloppy Core agent session APIs.

## Global Constraints

- Project path is `Apps/SafariExtension/`.
- Product and app name is `SafariExtension`.
- Keep the project separate from `Apps/Client/`.
- MVP side panel is a content-script drawer injected into the current page.
- macOS default Core URL is `http://127.0.0.1:25101`.
- iOS, iPadOS, and visionOS use a user-configured LAN URL such as `http://192.168.1.50:25101`.
- Send selected text plus page URL/title; do not transmit full page text by default.
- Do not automate Safari page interaction in the MVP.
- Do not rely on Chrome-only or non-portable side panel APIs as the core UI contract.
- Do not classify state, progress, intent, completion, tool use, or branching by matching model output phrases.
- First response path is blocking HTTP; this plan does not implement streaming.
- Auth token, Core URL, and default agent ID are edited in the containing app for the MVP.
- Context-menu actions are not part of the first implementation; toolbar/popup-triggered drawer is the MVP path.

---

## File Structure

- Create `Sources/Protocols/BrowserContextModels.swift`: shared typed request/response models for SafariExtension browser context.
- Modify `Package.swift`: include `Sources/Protocols/BrowserContextModels.swift` automatically through the existing `Protocols` target; no target list changes should be required unless the target uses explicit sources.
- Create `Sources/sloppy/CoreService+BrowserContext.swift`: service-level validation, session creation/reuse, prompt composition, and call into `postAgentSessionMessage`.
- Modify `Sources/sloppy/Gateway/Routers/AgentsAPIRouter.swift`: add `POST /v1/browser/context-message`.
- Modify `Sources/sloppy/Gateway/CoreRouter.swift` only if route error helpers need a browser-context-specific mapping; otherwise keep route handling local to `AgentsAPIRouter`.
- Create `Tests/ProtocolsTests/BrowserContextModelsTests.swift`: model coding defaults and round-trip tests.
- Add tests to `Tests/sloppyTests/CoreRouterTests.swift`: route validation and successful typed context post.
- Create `Apps/SafariExtension/project.yml`: XcodeGen project with macOS, iOS, iPadOS, and visionOS app targets plus matching Safari Web Extension targets.
- Create `Apps/SafariExtension/README.md`: build, generate, run, and platform notes.
- Create `Apps/SafariExtension/Sources/SafariExtensionApp/SafariExtensionApp.swift`: app entry point.
- Create `Apps/SafariExtension/Sources/SafariExtensionCore/ConnectionSettings.swift`: settings model and persistence.
- Create `Apps/SafariExtension/Sources/SafariExtensionCore/SettingsView.swift`: SwiftUI settings UI.
- Create `Apps/SafariExtension/Tests/SafariExtensionCoreTests/ConnectionSettingsTests.swift`: settings URL normalization tests.
- Create `Apps/SafariExtension/Extension/Resources/manifest.json`: Safari Web Extension manifest.
- Create `Apps/SafariExtension/Extension/Resources/background.js`: toolbar action handler and settings exchange.
- Create `Apps/SafariExtension/Extension/Resources/contentScript.js`: selection capture, drawer injection, message routing.
- Create `Apps/SafariExtension/Extension/Resources/panel.js`: panel state, form handling, request construction, fetch to Core.
- Create `Apps/SafariExtension/Extension/Resources/panel.css`: drawer styling.
- Create `Apps/SafariExtension/Extension/Resources/icons/icon.svg`: simple local icon asset.
- Create `Apps/SafariExtension/Extension/Tests/panelPayload.test.mjs`: JS unit test for typed payload construction and validation.
- Create `Apps/SafariExtension/Extension/Tests/contentSelection.test.mjs`: JS unit test for selection/page metadata helpers.
- Create `Apps/SafariExtension/Extension/package.json`: Node test script for extension helpers.
- Create `Apps/SafariExtension/SupportingFiles/macOS/Info.plist`.
- Create `Apps/SafariExtension/SupportingFiles/macOS/SafariExtension.entitlements`.
- Create `Apps/SafariExtension/SupportingFiles/iOS/Info.plist`.
- Create `Apps/SafariExtension/SupportingFiles/iOS/SafariExtension-iOS.entitlements`.
- Create `Apps/SafariExtension/SupportingFiles/iOS/SafariExtension-iPadOS.entitlements`.
- Create `Apps/SafariExtension/SupportingFiles/visionOS/Info.plist`.
- Create `Apps/SafariExtension/SupportingFiles/visionOS/SafariExtension-visionOS.entitlements`.

---

### Task 1: Core Browser Context API

**Files:**
- Create: `Sources/Protocols/BrowserContextModels.swift`
- Create: `Sources/sloppy/CoreService+BrowserContext.swift`
- Modify: `Sources/sloppy/Gateway/Routers/AgentsAPIRouter.swift`
- Test: `Tests/ProtocolsTests/BrowserContextModelsTests.swift`
- Test: `Tests/sloppyTests/CoreRouterTests.swift`

**Interfaces:**
- Consumes: `CoreService.createAgentSession(agentID:request:)`, `CoreService.postAgentSessionMessage(agentID:sessionID:request:)`, `AgentSessionPostMessageRequest`.
- Produces: `BrowserContextMessageRequest`, `BrowserContextMessageResponse`, `CoreService.postBrowserContextMessage(_:)`, `POST /v1/browser/context-message`.

- [ ] **Step 1: Write protocol model tests**

Add `Tests/ProtocolsTests/BrowserContextModelsTests.swift`:

```swift
import Foundation
import Protocols
import Testing

@Test
func browserContextMessageRequestRoundTripsWithDefaults() throws {
    let request = BrowserContextMessageRequest(
        page: BrowserContextPage(
            url: "https://example.com/article",
            title: "Example Article"
        ),
        selection: BrowserContextSelection(text: "Selected text"),
        prompt: "Explain this"
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(BrowserContextMessageRequest.self, from: data)

    #expect(decoded.source == "safari_extension")
    #expect(decoded.page.url == "https://example.com/article")
    #expect(decoded.page.title == "Example Article")
    #expect(decoded.selection.text == "Selected text")
    #expect(decoded.prompt == "Explain this")
    #expect(decoded.target.agentId == "sloppy")
    #expect(decoded.target.sessionId == nil)
    #expect(decoded.userId == "safari_extension")
}

@Test
func browserContextMessageResponseRoundTrips() throws {
    let response = BrowserContextMessageResponse(
        sessionId: "session-1",
        messageId: "message-1",
        status: "completed",
        text: "Agent response"
    )

    let data = try JSONEncoder().encode(response)
    let decoded = try JSONDecoder().decode(BrowserContextMessageResponse.self, from: data)

    #expect(decoded.sessionId == "session-1")
    #expect(decoded.messageId == "message-1")
    #expect(decoded.status == "completed")
    #expect(decoded.text == "Agent response")
}
```

- [ ] **Step 2: Run protocol tests and verify they fail**

Run:

```bash
swift test --filter BrowserContextModelsTests
```

Expected: FAIL with compiler errors that `BrowserContextMessageRequest`, `BrowserContextPage`, `BrowserContextSelection`, and `BrowserContextMessageResponse` are not in scope.

- [ ] **Step 3: Add protocol models**

Create `Sources/Protocols/BrowserContextModels.swift`:

```swift
import Foundation

public struct BrowserContextPage: Codable, Sendable, Equatable {
    public var url: String
    public var title: String?

    public init(url: String, title: String? = nil) {
        self.url = url
        self.title = title
    }
}

public struct BrowserContextSelection: Codable, Sendable, Equatable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public struct BrowserContextTarget: Codable, Sendable, Equatable {
    public var agentId: String
    public var sessionId: String?

    public init(agentId: String = "sloppy", sessionId: String? = nil) {
        self.agentId = agentId
        self.sessionId = sessionId
    }
}

public struct BrowserContextMessageRequest: Codable, Sendable, Equatable {
    public var source: String
    public var page: BrowserContextPage
    public var selection: BrowserContextSelection
    public var prompt: String
    public var target: BrowserContextTarget
    public var userId: String

    public init(
        source: String = "safari_extension",
        page: BrowserContextPage,
        selection: BrowserContextSelection,
        prompt: String,
        target: BrowserContextTarget = BrowserContextTarget(),
        userId: String = "safari_extension"
    ) {
        self.source = source
        self.page = page
        self.selection = selection
        self.prompt = prompt
        self.target = target
        self.userId = userId
    }
}

public struct BrowserContextMessageResponse: Codable, Sendable, Equatable {
    public var sessionId: String
    public var messageId: String?
    public var status: String
    public var text: String

    public init(sessionId: String, messageId: String? = nil, status: String, text: String) {
        self.sessionId = sessionId
        self.messageId = messageId
        self.status = status
        self.text = text
    }
}
```

- [ ] **Step 4: Run protocol tests and verify they pass**

Run:

```bash
swift test --filter BrowserContextModelsTests
```

Expected: PASS.

- [ ] **Step 5: Write router tests for the endpoint**

Append these tests near the existing agent session router tests in `Tests/sloppyTests/CoreRouterTests.swift`:

```swift
@Test
func browserContextMessageEndpointCreatesSessionAndPostsTypedContext() async throws {
    let harness = try await makeCoreRouterHarness()
    let router = harness.router
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let createAgentBody = try JSONEncoder().encode(
        AgentCreateRequest(
            id: "sloppy",
            name: "Sloppy",
            systemPrompt: "Reply briefly."
        )
    )
    let createAgentResponse = await router.handle(method: "POST", path: "/v1/agents", body: createAgentBody)
    #expect(createAgentResponse.status == 201)

    let request = BrowserContextMessageRequest(
        page: BrowserContextPage(url: "https://example.com/article", title: "Example Article"),
        selection: BrowserContextSelection(text: "Important selected text."),
        prompt: "Explain the selection",
        target: BrowserContextTarget(agentId: "sloppy")
    )
    let body = try JSONEncoder().encode(request)

    let response = await router.handle(method: "POST", path: "/v1/browser/context-message", body: body)
    #expect(response.status == 200)

    let payload = try decoder.decode(BrowserContextMessageResponse.self, from: response.body)
    #expect(!payload.sessionId.isEmpty)
    #expect(payload.status == "completed")

    let sessionResponse = await router.handle(
        method: "GET",
        path: "/v1/agents/sloppy/sessions/\(payload.sessionId)",
        body: nil
    )
    #expect(sessionResponse.status == 200)

    let detail = try decoder.decode(AgentSessionDetail.self, from: sessionResponse.body)
    let userText = detail.events
        .compactMap(\.message)
        .filter { $0.role == .user }
        .flatMap(\.segments)
        .compactMap(\.text)
        .joined(separator: "\n")

    #expect(userText.contains("Source: Safari Extension"))
    #expect(userText.contains("URL: https://example.com/article"))
    #expect(userText.contains("Title: Example Article"))
    #expect(userText.contains("Selected text:"))
    #expect(userText.contains("Important selected text."))
    #expect(userText.contains("User prompt:"))
    #expect(userText.contains("Explain the selection"))
}

@Test
func browserContextMessageEndpointRejectsEmptySelection() async throws {
    let harness = try await makeCoreRouterHarness()
    let router = harness.router

    let request = BrowserContextMessageRequest(
        page: BrowserContextPage(url: "https://example.com/article", title: "Example Article"),
        selection: BrowserContextSelection(text: "   "),
        prompt: "Explain this",
        target: BrowserContextTarget(agentId: "sloppy")
    )
    let body = try JSONEncoder().encode(request)

    let response = await router.handle(method: "POST", path: "/v1/browser/context-message", body: body)
    #expect(response.status == 400)
}
```

Before adding these tests, inspect the nearest passing agent session endpoint test in `Tests/sloppyTests/CoreRouterTests.swift` and use its exact `makeCoreRouterHarness()` and `AgentCreateRequest` construction style. Keep the browser-context request, route path, and assertions above unchanged.

- [ ] **Step 6: Run router tests and verify they fail**

Run:

```bash
swift test --filter browserContextMessageEndpoint
```

Expected: FAIL because `/v1/browser/context-message` is not registered.

- [ ] **Step 7: Implement service method**

Create `Sources/sloppy/CoreService+BrowserContext.swift`:

```swift
import Foundation
import Protocols

extension CoreService {
    public enum BrowserContextError: Error {
        case invalidPayload
        case invalidAgentID
        case invalidSessionID
        case agentNotFound
    }

    public func postBrowserContextMessage(_ request: BrowserContextMessageRequest) async throws -> BrowserContextMessageResponse {
        let agentID = request.target.agentId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !agentID.isEmpty else {
            throw BrowserContextError.invalidAgentID
        }

        let selection = request.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let pageURL = request.page.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selection.isEmpty, !prompt.isEmpty, !pageURL.isEmpty else {
            throw BrowserContextError.invalidPayload
        }

        let sessionID: String
        if let existingSessionID = request.target.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existingSessionID.isEmpty {
            _ = try getAgentSession(agentID: agentID, sessionID: existingSessionID)
            sessionID = existingSessionID
        } else {
            let hostTitle = URL(string: pageURL)?.host ?? "Safari"
            let created = try await createAgentSession(
                agentID: agentID,
                request: AgentSessionCreateRequest(title: "Safari: \(hostTitle)")
            )
            sessionID = created.id
        }

        let message = Self.browserContextPrompt(
            page: request.page,
            selection: selection,
            prompt: prompt
        )
        let response = try await postAgentSessionMessage(
            agentID: agentID,
            sessionID: sessionID,
            request: AgentSessionPostMessageRequest(
                userId: request.userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "safari_extension" : request.userId,
                content: message,
                spawnSubSession: false,
                mode: .ask
            )
        )
        let assistantText = Self.latestAssistantText(from: response.appendedEvents)
        let messageID = response.appendedEvents.last(where: { $0.message?.role == .assistant })?.message?.id
            ?? response.appendedEvents.last?.id

        return BrowserContextMessageResponse(
            sessionId: sessionID,
            messageId: messageID,
            status: "completed",
            text: assistantText
        )
    }

    static func browserContextPrompt(page: BrowserContextPage, selection: String, prompt: String) -> String {
        var lines: [String] = [
            "Source: Safari Extension",
            "URL: \(page.url)"
        ]
        if let title = page.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            lines.append("Title: \(title)")
        }
        lines.append("")
        lines.append("Selected text:")
        lines.append(selection)
        lines.append("")
        lines.append("User prompt:")
        lines.append(prompt)
        return lines.joined(separator: "\n")
    }
}
```

This intentionally reuses `latestAssistantText(from:)` already present in `CoreService+Agents.swift`.

- [ ] **Step 8: Register the route**

In `Sources/sloppy/Gateway/Routers/AgentsAPIRouter.swift`, add this route after the agent session `GET /v1/agents/:agentId/sessions` route and before session-specific routes:

```swift
        router.post("/v1/browser/context-message", metadata: RouteMetadata(summary: "Post browser context message", description: "Posts selected Safari page context to an agent session", tags: ["Agents"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: BrowserContextMessageRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let response = try await service.postBrowserContextMessage(payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch CoreService.BrowserContextError.invalidPayload {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            } catch CoreService.BrowserContextError.invalidAgentID {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidAgentId])
            } catch CoreService.BrowserContextError.invalidSessionID {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidSessionId])
            } catch CoreService.AgentStorageError.notFound {
                return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.agentNotFound])
            } catch CoreService.AgentSessionError.notFound {
                return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.sessionNotFound])
            } catch let error as CoreService.AgentSessionError {
                return CoreRouter.agentSessionErrorResponse(error, fallback: ErrorCode.sessionWriteFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.sessionWriteFailed])
            }
        }
```

If `CoreService.AgentSessionError` does not expose a `.notFound` case in the current enum, remove that specific catch and let `CoreRouter.agentSessionErrorResponse` map it.

- [ ] **Step 9: Run focused Swift tests**

Run:

```bash
swift test --filter BrowserContextModelsTests
swift test --filter browserContextMessageEndpoint
```

Expected: PASS for both commands.

- [ ] **Step 10: Commit**

```bash
git add Sources/Protocols/BrowserContextModels.swift Sources/sloppy/CoreService+BrowserContext.swift Sources/sloppy/Gateway/Routers/AgentsAPIRouter.swift Tests/ProtocolsTests/BrowserContextModelsTests.swift Tests/sloppyTests/CoreRouterTests.swift
git commit -m "Add browser context message API"
```

---

### Task 2: SafariExtension App Skeleton And Settings

**Files:**
- Create: `Apps/SafariExtension/project.yml`
- Create: `Apps/SafariExtension/README.md`
- Create: `Apps/SafariExtension/Sources/SafariExtensionApp/SafariExtensionApp.swift`
- Create: `Apps/SafariExtension/Sources/SafariExtensionCore/ConnectionSettings.swift`
- Create: `Apps/SafariExtension/Sources/SafariExtensionCore/SettingsView.swift`
- Create: `Apps/SafariExtension/Tests/SafariExtensionCoreTests/ConnectionSettingsTests.swift`
- Create: `Apps/SafariExtension/SupportingFiles/macOS/Info.plist`
- Create: `Apps/SafariExtension/SupportingFiles/macOS/SafariExtension.entitlements`
- Create: `Apps/SafariExtension/SupportingFiles/iOS/Info.plist`
- Create: `Apps/SafariExtension/SupportingFiles/iOS/SafariExtension-iOS.entitlements`
- Create: `Apps/SafariExtension/SupportingFiles/iOS/SafariExtension-iPadOS.entitlements`
- Create: `Apps/SafariExtension/SupportingFiles/visionOS/Info.plist`
- Create: `Apps/SafariExtension/SupportingFiles/visionOS/SafariExtension-visionOS.entitlements`

**Interfaces:**
- Consumes: no prior app code.
- Produces: `ConnectionSettings`, `ConnectionSettingsStore`, `SettingsView`, `SafariExtensionApp`, XcodeGen project targets for macOS/iOS/iPadOS/visionOS.

- [ ] **Step 1: Write settings tests**

Create `Apps/SafariExtension/Tests/SafariExtensionCoreTests/ConnectionSettingsTests.swift`:

```swift
import Testing
@testable import SafariExtensionCore

@Test
func connectionSettingsNormalizeBareHost() {
    var settings = ConnectionSettings(coreURLString: "192.168.1.50:25101", authToken: "", defaultAgentID: "sloppy")
    settings.normalize()

    #expect(settings.coreURLString == "http://192.168.1.50:25101")
    #expect(settings.defaultAgentID == "sloppy")
}

@Test
func connectionSettingsTrimTokenAndAgent() {
    var settings = ConnectionSettings(coreURLString: " http://127.0.0.1:25101 ", authToken: " secret ", defaultAgentID: " sloppy ")
    settings.normalize()

    #expect(settings.coreURLString == "http://127.0.0.1:25101")
    #expect(settings.authToken == "secret")
    #expect(settings.defaultAgentID == "sloppy")
}

@Test
func connectionSettingsFallbacksEmptyAgent() {
    var settings = ConnectionSettings(coreURLString: "", authToken: "", defaultAgentID: " ")
    settings.normalize()

    #expect(settings.coreURLString == "http://127.0.0.1:25101")
    #expect(settings.defaultAgentID == "sloppy")
}
```

- [ ] **Step 2: Run settings tests and verify they fail**

Run:

```bash
cd Apps/SafariExtension && swift test --filter ConnectionSettingsTests
```

Expected: FAIL because the package/project and `ConnectionSettings` do not exist yet.

- [ ] **Step 3: Create Swift package for testable app code**

Create `Apps/SafariExtension/Package.swift` even though the spec file structure did not list it; this keeps settings testable with SwiftPM like `Apps/Client`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SafariExtension",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "SafariExtensionCore", targets: ["SafariExtensionCore"])
    ],
    targets: [
        .target(
            name: "SafariExtensionCore",
            path: "Sources/SafariExtensionCore"
        ),
        .testTarget(
            name: "SafariExtensionCoreTests",
            dependencies: ["SafariExtensionCore"],
            path: "Tests/SafariExtensionCoreTests"
        )
    ]
)
```

- [ ] **Step 4: Implement settings model**

Create `Apps/SafariExtension/Sources/SafariExtensionCore/ConnectionSettings.swift`:

```swift
import Foundation
import SwiftUI

public struct ConnectionSettings: Codable, Equatable, Sendable {
    public var coreURLString: String
    public var authToken: String
    public var defaultAgentID: String

    public init(
        coreURLString: String = "http://127.0.0.1:25101",
        authToken: String = "",
        defaultAgentID: String = "sloppy"
    ) {
        self.coreURLString = coreURLString
        self.authToken = authToken
        self.defaultAgentID = defaultAgentID
    }

    public mutating func normalize() {
        var url = coreURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty {
            url = "http://127.0.0.1:25101"
        } else if !url.contains("://") {
            url = "http://\(url)"
        }
        coreURLString = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        authToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let agent = defaultAgentID.trimmingCharacters(in: .whitespacesAndNewlines)
        defaultAgentID = agent.isEmpty ? "sloppy" : agent
    }
}

public final class ConnectionSettingsStore: ObservableObject {
    @Published public var settings: ConnectionSettings

    private let userDefaults: UserDefaults
    private let key = "SafariExtension.connectionSettings"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(ConnectionSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = ConnectionSettings()
        }
    }

    public func save() {
        var normalized = settings
        normalized.normalize()
        settings = normalized
        if let data = try? JSONEncoder().encode(normalized) {
            userDefaults.set(data, forKey: key)
        }
    }
}
```

- [ ] **Step 5: Implement SwiftUI app and settings view**

Create `Apps/SafariExtension/Sources/SafariExtensionApp/SafariExtensionApp.swift`:

```swift
import SwiftUI
import SafariExtensionCore

@main
struct SafariExtensionApp: App {
    @StateObject private var store = ConnectionSettingsStore()

    var body: some Scene {
        WindowGroup {
            SettingsView(store: store)
        }
    }
}
```

Create `Apps/SafariExtension/Sources/SafariExtensionCore/SettingsView.swift`:

```swift
import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var store: ConnectionSettingsStore

    public init(store: ConnectionSettingsStore) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("Sloppy Core") {
                TextField("Core URL", text: $store.settings.coreURLString)
                    #if os(iOS) || os(visionOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                SecureField("Auth token", text: $store.settings.authToken)
                TextField("Default agent", text: $store.settings.defaultAgentID)
                    #if os(iOS) || os(visionOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                Button("Save") {
                    store.save()
                }
            }

            Section("Safari") {
                Text("Enable SafariExtension in Safari settings, then open a page, select text, and use the toolbar item.")
                    .font(.callout)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 260)
    }
}
```

- [ ] **Step 6: Create XcodeGen project**

Create `Apps/SafariExtension/project.yml`:

```yaml
name: SafariExtension

options:
  bundleIdPrefix: team.sloppy
  deploymentTarget:
    macOS: "14.0"
    iOS: "17.0"
    visionOS: "1.0"
  createIntermediateGroups: true

packages:
  SafariExtension:
    path: .

targets:
  SafariExtension-macOS:
    type: application
    platform: macOS
    sources:
      - Sources/SafariExtensionApp
    dependencies:
      - package: SafariExtension
        product: SafariExtensionCore
      - target: SafariExtensionWebExtension-macOS
    info:
      path: SupportingFiles/macOS/Info.plist
      properties:
        CFBundleDisplayName: SafariExtension
        CFBundleIdentifier: team.sloppy.safariextension
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        NSPrincipalClass: NSApplication
        NSLocalNetworkUsageDescription: SafariExtension connects to Sloppy Core on your local network.
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
    entitlements:
      path: SupportingFiles/macOS/SafariExtension.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.network.client: true
    settings:
      base:
        DEVELOPMENT_TEAM: 8PYCRS3EA3
        CODE_SIGN_STYLE: Automatic
        PRODUCT_BUNDLE_IDENTIFIER: team.sloppy.safariextension

  SafariExtension-iOS:
    type: application
    platform: iOS
    sources:
      - Sources/SafariExtensionApp
    dependencies:
      - package: SafariExtension
        product: SafariExtensionCore
      - target: SafariExtensionWebExtension-iOS
    info:
      path: SupportingFiles/iOS/Info.plist
      properties:
        CFBundleDisplayName: SafariExtension
        CFBundleIdentifier: team.sloppy.safariextension
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        UILaunchScreen: {}
        NSLocalNetworkUsageDescription: SafariExtension connects to Sloppy Core on your local network.
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
    entitlements:
      path: SupportingFiles/iOS/SafariExtension-iOS.entitlements
      properties:
        com.apple.security.app-sandbox: false
    settings:
      base:
        DEVELOPMENT_TEAM: 8PYCRS3EA3
        CODE_SIGN_STYLE: Automatic
        PRODUCT_BUNDLE_IDENTIFIER: team.sloppy.safariextension
        TARGETED_DEVICE_FAMILY: "1"

  SafariExtension-iPadOS:
    type: application
    platform: iOS
    sources:
      - Sources/SafariExtensionApp
    dependencies:
      - package: SafariExtension
        product: SafariExtensionCore
      - target: SafariExtensionWebExtension-iOS
    info:
      path: SupportingFiles/iOS/Info.plist
      properties:
        CFBundleDisplayName: SafariExtension
        CFBundleIdentifier: team.sloppy.safariextension
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        UILaunchScreen: {}
        NSLocalNetworkUsageDescription: SafariExtension connects to Sloppy Core on your local network.
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
    entitlements:
      path: SupportingFiles/iOS/SafariExtension-iPadOS.entitlements
      properties:
        com.apple.security.app-sandbox: false
    settings:
      base:
        DEVELOPMENT_TEAM: 8PYCRS3EA3
        CODE_SIGN_STYLE: Automatic
        PRODUCT_BUNDLE_IDENTIFIER: team.sloppy.safariextension
        TARGETED_DEVICE_FAMILY: "2"

  SafariExtension-visionOS:
    type: application
    platform: visionOS
    sources:
      - Sources/SafariExtensionApp
    dependencies:
      - package: SafariExtension
        product: SafariExtensionCore
      - target: SafariExtensionWebExtension-visionOS
    info:
      path: SupportingFiles/visionOS/Info.plist
      properties:
        CFBundleDisplayName: SafariExtension
        CFBundleIdentifier: team.sloppy.safariextension
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        UILaunchScreen: {}
        NSLocalNetworkUsageDescription: SafariExtension connects to Sloppy Core on your local network.
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
    entitlements:
      path: SupportingFiles/visionOS/SafariExtension-visionOS.entitlements
      properties:
        com.apple.security.app-sandbox: false
    settings:
      base:
        DEVELOPMENT_TEAM: 8PYCRS3EA3
        CODE_SIGN_STYLE: Automatic
        PRODUCT_BUNDLE_IDENTIFIER: team.sloppy.safariextension

  SafariExtensionWebExtension-macOS:
    type: app-extension
    platform: macOS
    sources:
      - Extension/Resources
    info:
      path: SupportingFiles/macOS/Info.plist
      properties:
        CFBundleDisplayName: SafariExtension
        CFBundleIdentifier: team.sloppy.safariextension.webextension
        NSExtension:
          NSExtensionPointIdentifier: com.apple.Safari.web-extension
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: team.sloppy.safariextension.webextension

  SafariExtensionWebExtension-iOS:
    type: app-extension
    platform: iOS
    sources:
      - Extension/Resources
    info:
      path: SupportingFiles/iOS/Info.plist
      properties:
        CFBundleDisplayName: SafariExtension
        CFBundleIdentifier: team.sloppy.safariextension.webextension
        NSExtension:
          NSExtensionPointIdentifier: com.apple.Safari.web-extension
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: team.sloppy.safariextension.webextension

  SafariExtensionWebExtension-visionOS:
    type: app-extension
    platform: visionOS
    sources:
      - Extension/Resources
    info:
      path: SupportingFiles/visionOS/Info.plist
      properties:
        CFBundleDisplayName: SafariExtension
        CFBundleIdentifier: team.sloppy.safariextension.webextension
        NSExtension:
          NSExtensionPointIdentifier: com.apple.Safari.web-extension
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: team.sloppy.safariextension.webextension

schemes:
  SafariExtension-macOS:
    build:
      targets:
        SafariExtension-macOS: all
    run:
      config: Debug
      executable: SafariExtension-macOS
    archive:
      config: Release
```

If XcodeGen rejects the Safari Web Extension target settings, replace only the app-extension target syntax with XcodeGen's generated Safari extension template output and preserve bundle IDs, resource paths, and app dependencies.

- [ ] **Step 7: Create supporting files**

Create each Info.plist as a minimal plist. For macOS, `Apps/SafariExtension/SupportingFiles/macOS/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

Use the same plist content for:

```text
Apps/SafariExtension/SupportingFiles/iOS/Info.plist
Apps/SafariExtension/SupportingFiles/visionOS/Info.plist
```

Create each entitlements file with the same minimal plist body:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

Files:

```text
Apps/SafariExtension/SupportingFiles/macOS/SafariExtension.entitlements
Apps/SafariExtension/SupportingFiles/iOS/SafariExtension-iOS.entitlements
Apps/SafariExtension/SupportingFiles/iOS/SafariExtension-iPadOS.entitlements
Apps/SafariExtension/SupportingFiles/visionOS/SafariExtension-visionOS.entitlements
```

- [ ] **Step 8: Add README**

Create `Apps/SafariExtension/README.md`:

```markdown
# SafariExtension

SafariExtension is a standalone Apple app project that packages the Sloppy Safari Web Extension.

## Build Settings Code

```bash
cd Apps/SafariExtension
swift test
```

## Generate Xcode Project

Requires XcodeGen:

```bash
cd Apps/SafariExtension
xcodegen generate
open SafariExtension.xcodeproj
```

## Runtime

macOS defaults to `http://127.0.0.1:25101`.

iOS, iPadOS, and visionOS need a LAN URL for the Mac or host running Sloppy Core, such as `http://192.168.1.50:25101`.
```

- [ ] **Step 9: Run app settings tests**

Run:

```bash
cd Apps/SafariExtension && swift test
```

Expected: PASS.

- [ ] **Step 10: Generate project if XcodeGen is installed**

Run:

```bash
cd Apps/SafariExtension && xcodegen generate
```

Expected: PASS and `Apps/SafariExtension/SafariExtension.xcodeproj` exists. If `xcodegen` is not installed, record that verification was skipped and continue; do not hand-edit the generated Xcode project.

- [ ] **Step 11: Commit**

```bash
git add Apps/SafariExtension
git commit -m "Add SafariExtension app skeleton"
```

---

### Task 3: Extension Drawer, Payload Helpers, And JavaScript Tests

**Files:**
- Create: `Apps/SafariExtension/Extension/package.json`
- Create: `Apps/SafariExtension/Extension/Resources/manifest.json`
- Create: `Apps/SafariExtension/Extension/Resources/background.js`
- Create: `Apps/SafariExtension/Extension/Resources/contentScript.js`
- Create: `Apps/SafariExtension/Extension/Resources/panel.js`
- Create: `Apps/SafariExtension/Extension/Resources/panel.css`
- Create: `Apps/SafariExtension/Extension/Resources/icons/icon.svg`
- Create: `Apps/SafariExtension/Extension/Tests/panelPayload.test.mjs`
- Create: `Apps/SafariExtension/Extension/Tests/contentSelection.test.mjs`

**Interfaces:**
- Consumes: `POST /v1/browser/context-message` request shape from Task 1.
- Produces: `buildBrowserContextPayload(settings, page, selection, prompt)`, `extractPageContext(documentLike, selectionText)`, injected drawer UI.

- [ ] **Step 1: Write JS payload tests**

Create `Apps/SafariExtension/Extension/Tests/panelPayload.test.mjs`:

```javascript
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildBrowserContextPayload, normalizeCoreURL } from "../Resources/panel.js";

test("normalizeCoreURL adds http scheme and removes trailing slashes", () => {
  assert.equal(normalizeCoreURL("192.168.1.50:25101/"), "http://192.168.1.50:25101");
});

test("buildBrowserContextPayload creates typed Safari context payload", () => {
  const payload = buildBrowserContextPayload(
    { defaultAgentID: "sloppy" },
    { url: "https://example.com/a", title: "Article" },
    "Selected text",
    "Explain this"
  );

  assert.deepEqual(payload, {
    source: "safari_extension",
    page: {
      url: "https://example.com/a",
      title: "Article"
    },
    selection: {
      text: "Selected text"
    },
    prompt: "Explain this",
    target: {
      agentId: "sloppy",
      sessionId: null
    },
    userId: "safari_extension"
  });
});
```

Create `Apps/SafariExtension/Extension/Tests/contentSelection.test.mjs`:

```javascript
import assert from "node:assert/strict";
import { test } from "node:test";
import { extractPageContext } from "../Resources/contentScript.js";

test("extractPageContext trims selected text and reads page metadata", () => {
  const context = extractPageContext(
    {
      location: { href: "https://example.com/page" },
      title: "Example Page"
    },
    "  Selected text  "
  );

  assert.deepEqual(context, {
    page: {
      url: "https://example.com/page",
      title: "Example Page"
    },
    selection: "Selected text"
  });
});
```

- [ ] **Step 2: Run JS tests and verify they fail**

Run:

```bash
cd Apps/SafariExtension/Extension && npm test
```

Expected: FAIL because `package.json`, `panel.js`, and `contentScript.js` do not exist.

- [ ] **Step 3: Add package and manifest**

Create `Apps/SafariExtension/Extension/package.json`:

```json
{
  "name": "sloppy-safari-extension",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "node --test Tests/*.test.mjs"
  }
}
```

Create `Apps/SafariExtension/Extension/Resources/manifest.json`:

```json
{
  "manifest_version": 3,
  "name": "SafariExtension",
  "version": "0.1.0",
  "description": "Send selected Safari page context to Sloppy.",
  "permissions": ["activeTab", "storage", "scripting"],
  "host_permissions": ["http://127.0.0.1:25101/*", "http://localhost:25101/*", "http://192.168.0.0/16"],
  "background": {
    "service_worker": "background.js",
    "type": "module"
  },
  "action": {
    "default_title": "Open SafariExtension"
  },
  "content_scripts": [
    {
      "matches": ["http://*/*", "https://*/*"],
      "js": ["contentScript.js"],
      "css": ["panel.css"]
    }
  ],
  "icons": {
    "128": "icons/icon.svg"
  }
}
```

If Safari rejects CIDR-style `host_permissions`, replace `http://192.168.0.0/16` with `<all_urls>` for the MVP and document in `README.md` that page access remains user-triggered by active tab and selection.

- [ ] **Step 4: Implement content script**

Create `Apps/SafariExtension/Extension/Resources/contentScript.js`:

```javascript
export function extractPageContext(documentLike = document, selectionText = "") {
  return {
    page: {
      url: documentLike.location.href,
      title: documentLike.title || null
    },
    selection: String(selectionText || "").trim()
  };
}

function selectedText() {
  return String(globalThis.getSelection?.() || "").trim();
}

function ensurePanel() {
  let frame = document.getElementById("sloppy-safari-extension-panel");
  if (frame) {
    return frame;
  }

  frame = document.createElement("aside");
  frame.id = "sloppy-safari-extension-panel";
  frame.innerHTML = `
    <div class="sloppy-safari-extension-header">
      <strong>SafariExtension</strong>
      <button type="button" data-sloppy-close aria-label="Close">x</button>
    </div>
    <div class="sloppy-safari-extension-meta"></div>
    <textarea data-sloppy-selection readonly></textarea>
    <textarea data-sloppy-prompt placeholder="Ask Sloppy about the selection"></textarea>
    <button type="button" data-sloppy-send>Send</button>
    <pre data-sloppy-output></pre>
  `;
  document.documentElement.appendChild(frame);
  frame.querySelector("[data-sloppy-close]").addEventListener("click", () => frame.remove());
  return frame;
}

async function openPanel() {
  const selection = selectedText();
  const context = extractPageContext(document, selection);
  const panel = ensurePanel();
  panel.querySelector("[data-sloppy-selection]").value = context.selection;
  panel.querySelector("[data-sloppy-prompt]").value = "";
  panel.querySelector("[data-sloppy-output]").textContent = "";
  panel.querySelector("[data-sloppy-send]").onclick = async () => {
    const prompt = panel.querySelector("[data-sloppy-prompt]").value;
    const response = await chrome.runtime.sendMessage({
      type: "sloppy.browserContext.send",
      page: context.page,
      selection: context.selection,
      prompt
    });
    panel.querySelector("[data-sloppy-output]").textContent = response?.text || response?.error || "";
  };
  panel.querySelector("[data-sloppy-prompt]").focus();
}

if (typeof chrome !== "undefined" && chrome.runtime?.onMessage) {
  chrome.runtime.onMessage.addListener((message) => {
    if (message?.type === "sloppy.panel.open") {
      void openPanel();
    }
  });
}
```

- [ ] **Step 5: Implement panel helpers and background**

Create `Apps/SafariExtension/Extension/Resources/panel.js`:

```javascript
export function normalizeCoreURL(value) {
  let url = String(value || "").trim();
  if (!url) {
    url = "http://127.0.0.1:25101";
  }
  if (!url.includes("://")) {
    url = `http://${url}`;
  }
  return url.replace(/\/+$/, "");
}

export function buildBrowserContextPayload(settings, page, selection, prompt) {
  return {
    source: "safari_extension",
    page: {
      url: page.url,
      title: page.title || null
    },
    selection: {
      text: String(selection || "").trim()
    },
    prompt: String(prompt || "").trim(),
    target: {
      agentId: String(settings.defaultAgentID || "sloppy").trim() || "sloppy",
      sessionId: settings.sessionId || null
    },
    userId: "safari_extension"
  };
}

export async function postBrowserContext(settings, page, selection, prompt, fetchImpl = fetch) {
  const coreURL = normalizeCoreURL(settings.coreURLString);
  const payload = buildBrowserContextPayload(settings, page, selection, prompt);
  const headers = { "content-type": "application/json" };
  if (settings.authToken) {
    headers.authorization = `Bearer ${settings.authToken}`;
  }
  const response = await fetchImpl(`${coreURL}/v1/browser/context-message`, {
    method: "POST",
    headers,
    body: JSON.stringify(payload)
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.error || `request_failed_${response.status}`);
  }
  return body;
}
```

Create `Apps/SafariExtension/Extension/Resources/background.js`:

```javascript
import { postBrowserContext } from "./panel.js";

const defaultSettings = {
  coreURLString: "http://127.0.0.1:25101",
  authToken: "",
  defaultAgentID: "sloppy"
};

async function loadSettings() {
  const stored = await chrome.storage.local.get(defaultSettings);
  return { ...defaultSettings, ...stored };
}

chrome.action.onClicked.addListener(async (tab) => {
  if (!tab.id) {
    return;
  }
  await chrome.tabs.sendMessage(tab.id, { type: "sloppy.panel.open" });
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== "sloppy.browserContext.send") {
    return false;
  }
  void (async () => {
    try {
      if (!String(message.selection || "").trim()) {
        sendResponse({ error: "Select text on the page first." });
        return;
      }
      if (!String(message.prompt || "").trim()) {
        sendResponse({ error: "Enter a prompt first." });
        return;
      }
      const settings = await loadSettings();
      const result = await postBrowserContext(settings, message.page, message.selection, message.prompt);
      sendResponse(result);
    } catch (error) {
      sendResponse({ error: error.message || "Sloppy Core unavailable." });
    }
  })();
  return true;
});
```

- [ ] **Step 6: Add drawer styles and icon**

Create `Apps/SafariExtension/Extension/Resources/panel.css`:

```css
#sloppy-safari-extension-panel {
  position: fixed;
  z-index: 2147483647;
  top: 0;
  right: 0;
  width: min(420px, 92vw);
  height: 100vh;
  box-sizing: border-box;
  padding: 14px;
  color: #f5f5f5;
  background: #15171a;
  border-left: 1px solid #3a3f45;
  box-shadow: -12px 0 30px rgba(0, 0, 0, 0.28);
  font: 14px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}

#sloppy-safari-extension-panel textarea,
#sloppy-safari-extension-panel pre {
  width: 100%;
  box-sizing: border-box;
  margin: 10px 0;
  padding: 10px;
  color: #f5f5f5;
  background: #20242a;
  border: 1px solid #454b53;
  border-radius: 8px;
}

#sloppy-safari-extension-panel [data-sloppy-selection] {
  min-height: 90px;
}

#sloppy-safari-extension-panel [data-sloppy-prompt] {
  min-height: 110px;
}

#sloppy-safari-extension-panel button {
  appearance: none;
  padding: 8px 12px;
  color: #101214;
  background: #a9ff68;
  border: 0;
  border-radius: 8px;
  font-weight: 700;
}

.sloppy-safari-extension-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
```

Create `Apps/SafariExtension/Extension/Resources/icons/icon.svg`:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
  <rect width="128" height="128" rx="24" fill="#15171a"/>
  <path d="M30 78c12 14 56 14 68 0" fill="none" stroke="#a9ff68" stroke-width="12" stroke-linecap="round"/>
  <circle cx="45" cy="50" r="8" fill="#f5f5f5"/>
  <circle cx="83" cy="50" r="8" fill="#f5f5f5"/>
</svg>
```

- [ ] **Step 7: Run JS tests**

Run:

```bash
cd Apps/SafariExtension/Extension && npm test
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Apps/SafariExtension/Extension
git commit -m "Add SafariExtension drawer resources"
```

---

### Task 4: End-To-End Verification And Packaging Fixes

**Files:**
- Modify: `Apps/SafariExtension/project.yml`
- Modify: `Apps/SafariExtension/README.md`
- Modify: `Apps/SafariExtension/Extension/Resources/manifest.json`
- Modify: `Apps/SafariExtension/Extension/Resources/background.js`
- Modify: `Apps/SafariExtension/Extension/Resources/contentScript.js`
- Modify: `Apps/SafariExtension/Extension/Resources/panel.js`
- Modify: `Apps/SafariExtension/Extension/Resources/panel.css`

**Interfaces:**
- Consumes: app skeleton, extension resources, Core browser context endpoint.
- Produces: verified build/test commands and documented manual smoke path.

- [ ] **Step 1: Run full focused verification**

Run:

```bash
swift test --filter BrowserContextModelsTests
swift test --filter browserContextMessageEndpoint
cd Apps/SafariExtension && swift test
cd Apps/SafariExtension/Extension && npm test
```

Expected: all commands PASS.

- [ ] **Step 2: Generate Xcode project**

Run:

```bash
cd Apps/SafariExtension && xcodegen generate
```

Expected: PASS. If this fails on Safari Web Extension target syntax, fix only `Apps/SafariExtension/project.yml` until XcodeGen emits `SafariExtension.xcodeproj`.

- [ ] **Step 3: Build macOS target without signing**

Run:

```bash
cd Apps/SafariExtension && xcodebuild -project SafariExtension.xcodeproj -scheme SafariExtension-macOS build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: PASS. If it fails because Safari Web Extensions require signing for embedding, rerun without `CODE_SIGNING_ALLOWED=NO` on the developer machine and record the signing requirement in `Apps/SafariExtension/README.md`.

- [ ] **Step 4: Run Core release build**

Run:

```bash
swift build -c release --product sloppy
```

Expected: PASS.

- [ ] **Step 5: Update README with verified commands**

If any verification command required an adjustment, update `Apps/SafariExtension/README.md` with the exact working command. Keep the README sections:

```markdown
## Verify

```bash
cd Apps/SafariExtension
swift test
xcodegen generate
xcodebuild -project SafariExtension.xcodeproj -scheme SafariExtension-macOS build -destination 'platform=macOS'
```

```bash
cd Apps/SafariExtension/Extension
npm test
```
```

- [ ] **Step 6: Commit**

```bash
git add Apps/SafariExtension docs/superpowers/plans/2026-06-22-safari-extension.md
git commit -m "Verify SafariExtension packaging"
```

---

## Plan Self-Review

- Spec coverage: Task 1 covers typed Core API and no prose parsing. Task 2 covers separate `Apps/SafariExtension/` project, platform shape, settings, Core URL defaults, and LAN configuration. Task 3 covers content-script drawer, selection capture, typed payloads, local/LAN HTTP request, and privacy boundary of selected text only. Task 4 covers XcodeGen/Xcode packaging and verification.
- Placeholder scan: no task uses forbidden placeholder markers or unspecified implementation steps; where platform tooling may vary, the plan gives exact fallback action bounded to `project.yml`, extension resource files, or README.
- Type consistency: request/response names are `BrowserContextMessageRequest` and `BrowserContextMessageResponse` throughout; JS payload keys match Swift model keys; endpoint path is consistently `/v1/browser/context-message`.
