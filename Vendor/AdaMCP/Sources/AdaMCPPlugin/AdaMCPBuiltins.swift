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
            [
                "isActive": camera.isActive,
                "renderOrder": camera.renderOrder,
                "viewport": try Value(camera.viewport),
                "logicalViewport": try Value(camera.logicalViewport),
                "backgroundColor": try Value(camera.backgroundColor),
                "clearFlags": Int(camera.clearFlags.rawValue),
                "renderTarget": Self.renderTargetDescription(camera.renderTarget),
                "projection": String(describing: camera.projection)
            ]
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
            [
                "hasMainTexture": value.mainTexture != nil,
                "hasOutputTexture": value.outputTexture != nil
            ]
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
            return [
                "kind": "window",
                "value": String(describing: windowRef)
            ]
        case .texture(let assetHandle):
            return [
                "kind": "texture",
                "assetPath": assetHandle.assetPath
            ]
        }
    }
}
