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

    func discover(modelName: String, resolved: String, baseURL: URL, session: URLSession) async {
        guard !alreadyDiscovered(modelName) else { return }
        do {
            var tagsRequest = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
            tagsRequest.timeoutInterval = 5
            let (tagsData, tagsResponse) = try await session.data(for: tagsRequest)
            guard (tagsResponse as? HTTPURLResponse)?.statusCode == 200 else { return }
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
            let (showData, showResponse) = try await session.data(for: showRequest)
            guard (showResponse as? HTTPURLResponse)?.statusCode == 200 else { return }
            let info = try JSONDecoder().decode(Show.self, from: showData).modelInfo
            guard let architecture = info["general.architecture"]?.asString,
                  case .number(let number)? = info[architecture + ".context_length"],
                  let window = Int(exactly: number), window > 0 else { return }
            store(.init(contextWindowTokens: window), for: modelName)
        } catch {
            // Discovery failure must not disable inference. Retry on the next session creation.
        }
    }
}
