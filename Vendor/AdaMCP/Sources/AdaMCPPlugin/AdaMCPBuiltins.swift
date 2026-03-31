import AdaEngine
import AdaMCPCore
import MCP

@MainActor
enum AdaMCPBuiltins {
    static func registerDefaultTypes(in registry: MCPIntrospectionRegistry) {
        registry.registerCodable(Transform.self, kind: .component)
        registry.registerCodable(GlobalTransform.self, kind: .component)
        registry.registerCodable(SimulationControl.self, kind: .resource)
        registry.registerDescriptor(
            MCPTypeDescriptor(
                name: String(reflecting: Camera.self),
                kind: .component,
                fields: [
                    .init(name: "isActive", typeName: "Bool"),
                    .init(name: "renderOrder", typeName: "Int"),
                    .init(name: "viewport", typeName: String(reflecting: Viewport.self)),
                    .init(name: "logicalViewport", typeName: String(reflecting: Viewport.self))
                ],
                serialization: .custom
            )
        )
        registry.register(Camera.self, descriptor: MCPTypeDescriptor(
            name: String(reflecting: Camera.self),
            kind: .component,
            fields: [
                .init(name: "isActive", typeName: "Bool"),
                .init(name: "renderOrder", typeName: "Int"),
                .init(name: "viewport", typeName: String(reflecting: Viewport.self)),
                .init(name: "logicalViewport", typeName: String(reflecting: Viewport.self))
            ],
            serialization: .custom
        )) { camera in
            .object([
                "isActive": .bool(camera.isActive),
                "renderOrder": .int(camera.renderOrder),
                "viewport": try Value(camera.viewport),
                "logicalViewport": try Value(camera.logicalViewport),
                "backgroundColor": try Value(camera.backgroundColor),
                "clearFlags": .int(Int(camera.clearFlags.rawValue)),
                "projection": .string(String(describing: camera.projection))
            ])
        }

        registry.register(RenderViewTarget.self, descriptor: MCPTypeDescriptor(
            name: String(reflecting: RenderViewTarget.self),
            kind: .component,
            fields: [
                .init(name: "hasMainTexture", typeName: "Bool"),
                .init(name: "hasOutputTexture", typeName: "Bool")
            ],
            serialization: .custom
        )) { value in
            .object([
                "hasMainTexture": .bool(value.mainTexture != nil),
                "hasOutputTexture": .bool(value.outputTexture != nil)
            ])
        }
    }

    static func registerAssetDescriptors(in registry: MCPIntrospectionRegistry) {
        for typeName in AssetsManager.registeredAssetTypes().keys.sorted() {
            if registry.descriptor(named: typeName) == nil {
                registry.registerDescriptor(
                    MCPTypeDescriptor(
                        name: typeName,
                        kind: .asset,
                        serialization: .descriptorOnly
                    )
                )
            }
        }
    }

    private static func renderTargetDescription(_ renderTarget: Camera.RenderTarget) -> Value {
        switch renderTarget {
        case .window(let windowRef):
            return .object([
                "kind": .string("window"),
                "value": .string(String(describing: windowRef))
            ])
        case .texture(let assetHandle):
            return .object([
                "kind": .string("texture"),
                "assetPath": .string(assetHandle.assetPath)
            ])
        }
    }
}
