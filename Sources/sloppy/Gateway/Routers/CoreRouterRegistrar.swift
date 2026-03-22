final class CoreRouterRegistrar {
    private(set) var routes: [RouteDefinition] = []

    func register(
        path: String,
        method: HTTPRouteMethod,
        metadata: RouteMetadata? = nil,
        callback: @escaping (HTTPRequest) async -> CoreRouterResponse
    ) {
        routes.append(.init(method: method, path: path, metadata: metadata, callback: callback))
    }

    func get(_ path: String, metadata: RouteMetadata? = nil, callback: @escaping (HTTPRequest) async -> CoreRouterResponse) {
        register(path: path, method: .get, metadata: metadata, callback: callback)
    }

    func post(_ path: String, metadata: RouteMetadata? = nil, callback: @escaping (HTTPRequest) async -> CoreRouterResponse) {
        register(path: path, method: .post, metadata: metadata, callback: callback)
    }

    func put(_ path: String, metadata: RouteMetadata? = nil, callback: @escaping (HTTPRequest) async -> CoreRouterResponse) {
        register(path: path, method: .put, metadata: metadata, callback: callback)
    }

    func patch(_ path: String, metadata: RouteMetadata? = nil, callback: @escaping (HTTPRequest) async -> CoreRouterResponse) {
        register(path: path, method: .patch, metadata: metadata, callback: callback)
    }

    func delete(_ path: String, metadata: RouteMetadata? = nil, callback: @escaping (HTTPRequest) async -> CoreRouterResponse) {
        register(path: path, method: .delete, metadata: metadata, callback: callback)
    }
}
