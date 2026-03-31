@_spi(Internal) import AdaEngine
import AdaMCPCore
import AdaMCPServer
import Foundation
import MCP
import Testing

#if canImport(System)
import System
#else
@preconcurrency import SystemPackage
#endif

@MainActor
@Suite("AdaMCP Tests")
struct AdaMCPTests {
    struct InspectableSettings: Codable, Sendable, AdaEngine.Resource {
        var label: String
    }

    struct HiddenResource: Sendable, AdaEngine.Resource {
        var token: Int
    }

    struct HiddenComponent: Sendable, Component {
        var token: Int
    }

    @MainActor
    final class UITapRecorder {
        var tapCount = 0
    }

    @MainActor
    final class TestWindowManager: UIWindowManager {
        private var cursorShape: Input.CursorShape = .arrow
        private var mouseMode: Input.MouseMode = .visible

        override func showWindow(_ window: UIWindow, isFocused: Bool) {
            if isFocused {
                self.setActiveWindow(window)
            }
            window.windowDidAppear()
        }

        override func closeWindow(_ window: UIWindow) { }

        override func setWindowMode(_ window: UIWindow, mode: UIWindow.Mode) {
            window.isFullscreen = (mode == .fullscreen)
        }

        override func setMinimumSize(_ size: Size, for window: UIWindow) { }

        override func resizeWindow(_ window: UIWindow, size: Size) { }

        override func getScreen(for window: UIWindow) -> Screen? {
            nil
        }

        override func setCursorShape(_ shape: Input.CursorShape) {
            self.cursorShape = shape
        }

        override func getCursorShape() -> Input.CursorShape {
            self.cursorShape
        }

        override func setCursorImage(for shape: Input.CursorShape, texture: Texture2D?, hotspot: Vector2) { }

        override func setMouseMode(_ mode: Input.MouseMode) {
            self.mouseMode = mode
        }

        override func getMouseMode() -> Input.MouseMode {
            self.mouseMode
        }

        override func updateCursor() { }
    }

    @MainActor
    struct UITestRootView: View {
        let recorder: UITapRecorder

        var body: some View {
            ScrollView {
                VStack(spacing: 12) {
                    Button(action: { }) {
                        Divider().frame(width: 140, height: 18)
                    }
                    .accessibilityIdentifier("button.first")
                    Button(action: { }) {
                        Divider().frame(width: 140, height: 18)
                    }
                    .accessibilityIdentifier("button.second")
                    Divider()
                        .frame(height: 320)
                        .accessibilityIdentifier("spacer.large")
                    Button(action: {
                        recorder.tapCount += 1
                    }) {
                        Divider().frame(width: 140, height: 18)
                    }
                    .accessibilityIdentifier("button.tap")
                    Button(action: { }) {
                        Divider().frame(width: 100, height: 14)
                    }
                        .accessibilityIdentifier("duplicate.node")
                    Button(action: { }) {
                        Divider().frame(width: 100, height: 14)
                    }
                        .accessibilityIdentifier("duplicate.node")
                }
            }
            .frame(width: 220, height: 140)
            .accessibilityIdentifier("scroll.root")
        }
    }

    @Test("Registry registers and serializes codable types")
    func registryRegistersAndSerializesCodableTypes() throws {
        let registry = MCPIntrospectionRegistry()
        registry.registerCodable(
            InspectableSettings.self,
            kind: .resource,
            fields: [.init(name: "label", typeName: "String")]
        )

        let descriptor = try #require(registry.descriptor(named: String(reflecting: InspectableSettings.self)))
        #expect(descriptor.kind == .resource)
        #expect(descriptor.serialization == .codable)

        let serialized = try #require(try registry.serialize(InspectableSettings(label: "debug")))
        #expect(serialized.objectValue?["label"]?.stringValue == "debug")
    }

    @Test("Runtime inspects entities, resources, and screenshots")
    func runtimeInspectsEntitiesResourcesAndScreenshots() async throws {
        let fixture = self.makeFixture()

        let entityResult = await fixture.runtime.callTool(
            name: "entity.get_by_name",
            arguments: ["name": .string("Player")]
        )
        let entityPayload = try self.decodeToolPayload(entityResult)
        #expect(entityPayload.objectValue?["name"]?.stringValue == "Player")
        #expect(entityPayload.objectValue?["world"]?.stringValue == AppWorldName.main.rawValue)

        let components = entityPayload.objectValue?["components"]?.arrayValue ?? []
        #expect(
            components.contains {
                $0.objectValue?["type"]?.stringValue == String(reflecting: Transform.self)
            }
        )

        let diagnostics = entityPayload.objectValue?["diagnostics"]?.arrayValue ?? []
        #expect(diagnostics.count == 2)

        let componentResult = await fixture.runtime.callTool(
            name: "component.get",
            arguments: [
                "entityId": .int(fixture.player.id),
                "componentType": .string(String(reflecting: Transform.self))
            ]
        )
        let componentPayload = try self.decodeToolPayload(componentResult)
        #expect(componentPayload.objectValue?["type"]?.stringValue == String(reflecting: Transform.self))

        let resourceResult = await fixture.runtime.callTool(name: "resource.list", arguments: [:])
        let resourcePayload = try self.decodeToolPayload(resourceResult)
        let resources = resourcePayload.objectValue?["resources"]?.arrayValue ?? []
        #expect(
            resources.contains {
                $0.objectValue?["type"]?.stringValue == String(reflecting: InspectableSettings.self)
            }
        )
        let resourceDiagnostics = resourcePayload.objectValue?["diagnostics"]?.arrayValue ?? []
        #expect(resourceDiagnostics.count == 1)

        let screenshotResult = await fixture.runtime.callTool(
            name: "render.capture_screenshot",
            arguments: ["cameraName": .string("Primary")]
        )
        let screenshotPayload = try self.decodeToolPayload(screenshotResult)
        #expect(screenshotPayload.objectValue?["path"]?.stringValue == "/tmp/adamcp-test.png")
        #expect(screenshotPayload.objectValue?["cameraName"]?.stringValue == "Primary")
    }

    @Test("Server exposes tools, resources, and templates over MCP")
    func serverExposesToolsResourcesAndTemplates() async throws {
        let fixture = self.makeFixture()
        let server = await AdaMCPServerFactory.makeServer(
            runtime: fixture.runtime,
            configuration: MCPServerConfiguration(
                serverName: "adamcp-tests",
                serverVersion: "1.0.0"
            )
        )

        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "AdaMCPTests", version: "1.0.0")

        try await server.start(transport: serverTransport)
        _ = try await client.connect(transport: clientTransport)

        let (tools, _) = try await client.listTools()
        #expect(tools.contains { $0.name == "entity.get_by_name" })
        #expect(tools.contains { $0.name == "render.capture_screenshot" })

        let (resources, _) = try await client.listResources()
        #expect(resources.contains { $0.uri == "ada://worlds" })
        #expect(resources.contains { $0.uri == "ada://world/Main" })

        let (templates, _) = try await client.listResourceTemplates()
        #expect(templates.contains { $0.uriTemplate == "ada://entity/{world}/{id}" })

        let worldContents = try await client.readResource(uri: "ada://worlds")
        let worldsPayload = try self.decodeResourcePayload(worldContents)
        let worlds = worldsPayload.objectValue?["worlds"]?.arrayValue ?? []
        #expect(worlds.isEmpty == false)

        let componentCall = try await client.callTool(
            name: "component.get",
            arguments: [
                "entityId": .int(fixture.player.id),
                "componentType": .string(String(reflecting: Transform.self))
            ]
        )
        let componentPayload = try self.decodeToolPayload(componentCall.content)
        #expect(componentPayload.objectValue?["type"]?.stringValue == String(reflecting: Transform.self))

        await client.disconnect()
        await server.stop()
        await clientTransport.disconnect()
        await serverTransport.disconnect()
    }

    @Test("Server supports stdio transport roundtrip")
    func serverSupportsStdioTransportRoundtrip() async throws {
        let fixture = self.makeFixture()
        let server = await AdaMCPServerFactory.makeServer(
            runtime: fixture.runtime,
            configuration: MCPServerConfiguration(
                enableHTTP: false,
                enableStdio: true,
                serverName: "adamcp-stdio-tests",
                serverVersion: "1.0.0"
            )
        )

        let (clientToServerRead, clientToServerWrite) = try FileDescriptor.pipe()
        let (serverToClientRead, serverToClientWrite) = try FileDescriptor.pipe()
        let serverTransport = StdioTransport(
            input: clientToServerRead,
            output: serverToClientWrite,
            logger: nil
        )
        let clientTransport = StdioTransport(
            input: serverToClientRead,
            output: clientToServerWrite,
            logger: nil
        )
        let client = Client(name: "AdaMCPTests", version: "1.0.0")

        try await server.start(transport: serverTransport)
        _ = try await client.connect(transport: clientTransport)

        let (templates, _) = try await client.listResourceTemplates()
        #expect(templates.contains { $0.uriTemplate == "ada://entity/{world}/{id}" })

        let entityContents = try await client.readResource(uri: "ada://entity/Main/\(fixture.player.id)")
        let entityPayload = try self.decodeResourcePayload(entityContents)
        #expect(entityPayload.objectValue?["name"]?.stringValue == "Player")
        #expect(entityPayload.objectValue?["id"]?.intValue == fixture.player.id)

        await client.disconnect()
        await server.stop()
        try? clientToServerRead.close()
        try? clientToServerWrite.close()
        try? serverToClientRead.close()
        try? serverToClientWrite.close()
    }

    @Test("Runtime exposes AdaUI inspection and safe actions")
    func runtimeInspectsAdaUIAndPerformsActions() async throws {
        let fixture = self.makeUIFixture()

        let listWindowsResult = await fixture.runtime.callTool(name: "ui.list_windows", arguments: [:])
        let listWindowsPayload = try self.decodeToolPayload(listWindowsResult)
        let windows = listWindowsPayload.objectValue?["windows"]?.arrayValue ?? []
        #expect(windows.count == 1)
        #expect(windows.first?.objectValue?["windowId"]?.intValue == fixture.window.id.id)

        let treeResult = await fixture.runtime.callTool(
            name: "ui.get_tree",
            arguments: ["windowId": .int(fixture.window.id.id)]
        )
        let treePayload = try self.decodeToolPayload(treeResult)
        let roots = treePayload.objectValue?["roots"]?.arrayValue ?? []
        #expect(roots.isEmpty == false)

        let foundNodeResult = await fixture.runtime.callTool(
            name: "ui.find_nodes",
            arguments: [
                "windowId": .int(fixture.window.id.id),
                "accessibilityIdentifier": .string("button.first")
            ]
        )
        let foundNodePayload = try self.decodeToolPayload(foundNodeResult)
        let foundNodes = foundNodePayload.objectValue?["nodes"]?.arrayValue ?? []
        #expect(foundNodes.count == 1)
        let primaryAbsoluteFrame = try #require(foundNodes.first?.objectValue?["absoluteFrame"]?.objectValue)
        let primaryOrigin = try #require(primaryAbsoluteFrame["origin"]?.objectValue)
        let primarySize = try #require(primaryAbsoluteFrame["size"]?.objectValue)
        let hitX = self.numericDouble(primaryOrigin["x"]) + self.numericDouble(primarySize["width"]) * 0.5
        let hitY = self.numericDouble(primaryOrigin["y"]) + self.numericDouble(primarySize["height"]) * 0.5

        let hitTestResult = await fixture.runtime.callTool(
            name: "ui.hit_test",
            arguments: [
                "windowId": .int(fixture.window.id.id),
                "x": .double(hitX),
                "y": .double(hitY)
            ]
        )
        let hitTestPayload = try self.decodeToolPayload(hitTestResult)
        let hitPath = hitTestPayload.objectValue?["path"]?.arrayValue ?? []
        #expect(
            hitPath.contains {
                $0.objectValue?["accessibilityIdentifier"]?.stringValue == "button.first"
            }
        )

        let focusNodeResult = await fixture.runtime.callTool(
            name: "ui.focus_node",
            arguments: [
                "windowId": .int(fixture.window.id.id),
                "accessibilityIdentifier": .string("button.first")
            ]
        )
        let focusNodePayload = try self.decodeToolPayload(focusNodeResult)
        #expect(focusNodePayload.objectValue?["focusedNode"]?.objectValue?["accessibilityIdentifier"]?.stringValue == "button.first")

        let focusNextResult = await fixture.runtime.callTool(
            name: "ui.focus_next",
            arguments: ["windowId": .int(fixture.window.id.id)]
        )
        let focusNextPayload = try self.decodeToolPayload(focusNextResult)
        #expect(focusNextPayload.objectValue?["focusedNode"]?.objectValue?["accessibilityIdentifier"]?.stringValue == "button.second")

        let focusPreviousResult = await fixture.runtime.callTool(
            name: "ui.focus_previous",
            arguments: ["windowId": .int(fixture.window.id.id)]
        )
        let focusPreviousPayload = try self.decodeToolPayload(focusPreviousResult)
        #expect(focusPreviousPayload.objectValue?["focusedNode"]?.objectValue?["accessibilityIdentifier"]?.stringValue == "button.first")

        let diagnosticsResult = await fixture.runtime.callTool(
            name: "ui.get_layout_diagnostics",
            arguments: [
                "windowId": .int(fixture.window.id.id),
                "accessibilityIdentifier": .string("button.tap"),
                "subtreeDepth": .int(1)
            ]
        )
        let diagnosticsPayload = try self.decodeToolPayload(diagnosticsResult)
        #expect(diagnosticsPayload.objectValue?["hasScrollContainer"]?.boolValue == true)
        #expect(diagnosticsPayload.objectValue?["target"]?.objectValue?["accessibilityIdentifier"]?.stringValue == "button.tap")

        let overlayResult = await fixture.runtime.callTool(
            name: "ui.set_debug_overlay",
            arguments: [
                "windowId": .int(fixture.window.id.id),
                "mode": .string("layout_bounds")
            ]
        )
        let overlayPayload = try self.decodeToolPayload(overlayResult)
        #expect(overlayPayload.objectValue?["overlayMode"]?.stringValue == "layout_bounds")

        let scrollResult = await fixture.runtime.callTool(
            name: "ui.scroll_to_node",
            arguments: [
                "windowId": .int(fixture.window.id.id),
                "accessibilityIdentifier": .string("button.tap")
            ]
        )
        let scrollPayload = try self.decodeToolPayload(scrollResult)
        #expect(scrollPayload.objectValue?["target"]?.objectValue?["accessibilityIdentifier"]?.stringValue == "button.tap")

        let tapResult = await fixture.runtime.callTool(
            name: "ui.tap_node",
            arguments: [
                "windowId": .int(fixture.window.id.id),
                "accessibilityIdentifier": .string("button.tap")
            ]
        )
        let tapPayload = try self.decodeToolPayload(tapResult)
        #expect(tapPayload.objectValue?["target"]?.objectValue?["accessibilityIdentifier"]?.stringValue == "button.tap")
        #expect(fixture.recorder.tapCount == 1)

        let ambiguousResult = await fixture.runtime.callTool(
            name: "ui.tap_node",
            arguments: [
                "windowId": .int(fixture.window.id.id),
                "accessibilityIdentifier": .string("duplicate.node")
            ]
        )
        #expect(ambiguousResult.isError == true)
        let ambiguousPayload = try self.decodeToolPayload(ambiguousResult)
        #expect(ambiguousPayload.objectValue?["code"]?.stringValue == "ui_node_ambiguous")

        let missingResult = await fixture.runtime.callTool(
            name: "ui.tap_node",
            arguments: [
                "windowId": .int(fixture.window.id.id),
                "accessibilityIdentifier": .string("missing.node")
            ]
        )
        #expect(missingResult.isError == true)
        let missingPayload = try self.decodeToolPayload(missingResult)
        #expect(missingPayload.objectValue?["code"]?.stringValue == "ui_node_not_found")
    }

    private func makeFixture() -> (runtime: AdaMCPRuntime, player: Entity) {
        Transform.registerComponent()
        InspectableSettings.registerResource()
        HiddenResource.registerResource()

        let world = World(name: "MainWorld")
        let player = world.spawn("Player") {
            Transform(position: [1, 2, 3])
            HiddenComponent(token: 7)
        }
        world.insertResource(InspectableSettings(label: "debug"))
        world.insertResource(HiddenResource(token: 99))

        let appWorlds = AppWorlds(main: world)
        let registry = MCPIntrospectionRegistry()
        registry.registerCodable(Transform.self, kind: .component)
        registry.registerCodable(
            InspectableSettings.self,
            kind: .resource,
            fields: [.init(name: "label", typeName: "String")]
        )

        let captureService = RenderCaptureService(
            appWorlds: appWorlds,
            captureOverride: { _, cameraEntityID, cameraName, _, _ in
                ScreenshotCaptureResult(
                    world: AppWorldName.main.rawValue,
                    cameraEntityID: cameraEntityID ?? 0,
                    cameraName: cameraName ?? "Primary",
                    width: 128,
                    height: 72,
                    path: "/tmp/adamcp-test.png",
                    timestamp: "2026-03-30T00:00:00Z"
                )
            }
        )

        let runtime = AdaMCPRuntime(
            appWorlds: appWorlds,
            registry: registry,
            renderCaptureService: captureService
        )
        return (runtime, player)
    }

    private func makeUIFixture() -> (runtime: AdaMCPRuntime, window: UIWindow, recorder: UITapRecorder) {
        let manager = TestWindowManager()
        UIWindowManager.setShared(manager)
        let world = World(name: "MainWorld")
        let appWorlds = AppWorlds(main: world)
        world.insertResource(WindowManagerResource(windowManager: manager))

        let registry = MCPIntrospectionRegistry()
        let captureService = RenderCaptureService(
            appWorlds: appWorlds,
            captureOverride: { _, _, _, _, _ in
                ScreenshotCaptureResult(
                    world: AppWorldName.main.rawValue,
                    cameraEntityID: 0,
                    cameraName: "Primary",
                    width: 1,
                    height: 1,
                    path: "/tmp/adamcp-ui-test.png",
                    timestamp: "2026-03-30T00:00:00Z"
                )
            }
        )

        let recorder = UITapRecorder()
        let window = UIWindow()
        window.frame = Rect(x: 0, y: 0, width: 240, height: 180)
        let container = UIContainerView(rootView: UITestRootView(recorder: recorder))
        container.frame = window.bounds
        window.addSubview(container)
        window.showWindow(makeFocused: true)
        window.layoutIfNeeded()

        let runtime = AdaMCPRuntime(
            appWorlds: appWorlds,
            registry: registry,
            renderCaptureService: captureService
        )

        return (runtime, window, recorder)
    }

    private func decodeToolPayload(_ result: CallTool.Result) throws -> Value {
        try self.decodeToolPayload(result.content)
    }

    private func numericDouble(_ value: Value?) -> Double {
        value?.doubleValue ?? value?.intValue.map(Double.init) ?? 0
    }

    private func decodeToolPayload(_ content: [Tool.Content]) throws -> Value {
        let text = try #require(self.firstToolText(in: content))
        let data = try #require(text.data(using: .utf8))
        return try JSONDecoder().decode(Value.self, from: data)
    }

    private func decodeResourcePayload(_ contents: [MCP.Resource.Content]) throws -> Value {
        let text = try #require(contents.first?.text)
        let data = try #require(text.data(using: .utf8))
        return try JSONDecoder().decode(Value.self, from: data)
    }

    private func firstToolText(in content: [Tool.Content]) -> String? {
        for item in content {
            if case .text(let text, _, _) = item {
                return text
            }
        }
        return nil
    }
}
