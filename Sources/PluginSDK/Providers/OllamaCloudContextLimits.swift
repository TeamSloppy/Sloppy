import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols

/// Cloud windows come from the serving model. Local architecture maxima are not
/// effective runner windows: local num_ctx can be smaller, so keep their fallback.
final class OllamaCloudContextLimits: @unchecked Sendable {
    private struct Tags: Decodable {
        struct Model: Decodable {
            var name: String
            var remoteHost: String?
            var remoteModel: String?

            enum CodingKeys: String, CodingKey {
                case name
                case remoteHost = "remote_host"
                case remoteModel = "remote_model"
            }
        }
        var models: [Model]
    }

    private struct Show: Decodable {
        var modelInfo: [String: JSONValue]

        enum CodingKeys: String, CodingKey {
            case modelInfo = "model_info"
        }
    }

    private let lock = NSLock()
    private var limits: [String: ModelContextLimits] = [:]
    private var localModels: Set<String> = []
    private struct ThinkingOptions { let values: [JSONValue]? }
    private var thinkingOptions: [String: ThinkingOptions] = [:]

    /// Native requests freeze declared controls once, independently of local/cloud window discovery.
    func discoverThinking(modelName: String, resolved: String, baseURL: URL, session: URLSession) async -> [JSONValue]? {
        if let cached = lock.withLock({ thinkingOptions[modelName] }) { return cached.values }
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("api/show"))
            request.httpMethod = "POST"
            request.timeoutInterval = 5
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["model": resolved])
            let (data, status) = try await load(request, session: session, nativeTransport: true)
            guard status == 200,
                  let object = try JSONDecoder().decode(JSONValue.self, from: data).asObject else { return nil }
            let values: [JSONValue]?
            if let thinking = object["thinking"] {
                guard let declared = thinking.asObject?["values"]?.asArray,
                      declared.allSatisfy({ value in
                          switch value { case .bool, .string: return true; default: return false }
                      }) else { return nil }
                values = declared
            } else if object["capabilities"]?.asArray?.contains(.string("thinking")) == true {
                values = [.bool(false), .bool(true)]
            } else { values = nil }
            lock.withLock { thinkingOptions[modelName] = ThinkingOptions(values: values) }
            return values
        } catch {
            // Inference without an effort override may use the serving model's default.
            // Explicit effort is rejected by the codec unless controls were declared.
            return nil
        }
    }

    func value(for model: String) -> ModelContextLimits? {
        lock.lock()
        defer { lock.unlock() }
        return limits[model]
    }

    private func alreadyDiscovered(_ model: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return limits[model] != nil || localModels.contains(model)
    }

    private func store(_ value: ModelContextLimits?, for model: String) {
        lock.lock()
        defer { lock.unlock() }
        if let value { limits[model] = value } else { localModels.insert(model) }
    }

    func discover(modelName: String, resolved: String, baseURL: URL, session: URLSession, nativeTransport: Bool = false) async {
        guard !alreadyDiscovered(modelName) else { return }
        do {
            var tagsRequest = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
            tagsRequest.timeoutInterval = 5
            let (tagsData, tagsStatus) = try await load(tagsRequest, session: session, nativeTransport: nativeTransport)
            guard tagsStatus == 200 else { return }
            let tags = try JSONDecoder().decode(Tags.self, from: tagsData)
            guard let model = tags.models.first(where: { $0.name == resolved }) else { return }
            guard model.remoteHost?.isEmpty == false, model.remoteModel?.isEmpty == false else {
                store(nil, for: modelName)
                return
            }
            var showRequest = URLRequest(url: baseURL.appendingPathComponent("api/show"))
            showRequest.httpMethod = "POST"
            showRequest.timeoutInterval = 5
            showRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            showRequest.httpBody = try JSONEncoder().encode(["model": resolved])
            let (showData, showStatus) = try await load(showRequest, session: session, nativeTransport: nativeTransport)
            guard showStatus == 200 else { return }
            let info = try JSONDecoder().decode(Show.self, from: showData).modelInfo
            guard let architecture = info["general.architecture"]?.asString,
                  case .number(let number)? = info[architecture + ".context_length"],
                  let window = Int(exactly: number), window > 0 else { return }
            store(.init(contextWindowTokens: window), for: modelName)
        } catch {
            // Discovery failure must not disable inference. Retry on the next session creation.
        }
    }

    private func load(_ request: URLRequest, session: URLSession, nativeTransport: Bool) async throws -> (Data, Int) {
        if !nativeTransport {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        var data = Data()
        var status = 0
        for try await event in ModelStepHTTPTransport(session: session).stream(request) {
            switch event {
            case .response(let code, _): status = code
            case .data(let chunk): data.append(chunk)
            }
        }
        return (data, status)
    }
}
