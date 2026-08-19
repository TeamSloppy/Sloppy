import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols

struct OpenAIImageGenerationProvider: ImageGenerationProvider, Sendable {
    private let apiKey: String
    private let session: URLSession
    private let apiBaseURL: URL

    init(
        apiKey: String,
        apiBaseURL: URL = URL(string: "https://api.openai.com/v1")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.apiBaseURL = apiBaseURL
        self.session = session
    }

    func generate(
        request: ImageGenerationRequest,
        model: ImageGenerationModelDefinition,
        timeoutMs: Int
    ) async throws -> ImageGenerationResult {
        guard model.provider == .openAI else {
            throw ImageGenerationProviderError.unsupportedModel
        }
        guard request.sourceImages.count <= model.maxReferenceImages else {
            throw ImageGenerationProviderError.invalidRequest("Too many reference images.")
        }

        let endpoint: String
        var payload: [String: JSONValue] = [
            "model": .string(model.id),
            "prompt": .string(request.prompt),
            "n": .number(1),
            "quality": .string("medium"),
            "output_format": .string("png"),
            "moderation": .string("auto"),
        ]
        if request.sourceImages.isEmpty {
            endpoint = "images/generations"
            payload["size"] = .string(size(for: request.aspectRatio ?? .landscape))
        } else {
            endpoint = "images/edits"
            payload["images"] = .array(request.sourceImages.map { source in
                .object(["image_url": .string(source)])
            })
            payload["input_fidelity"] = .string("high")
            payload["size"] = .string(request.aspectRatio.map(size(for:)) ?? "auto")
        }

        let response = try await performJSONRequest(
            url: apiBaseURL.appendingPathComponent(endpoint),
            payload: .object(payload),
            timeoutMs: timeoutMs
        )
        guard let root = response.asObject,
              let encoded = root["data"]?.asArray?.first?.asObject?["b64_json"]?.asString,
              let imageData = Data(base64Encoded: encoded),
              !imageData.isEmpty
        else {
            throw ImageGenerationProviderError.invalidResponse("OpenAI response did not contain a valid base64 image.")
        }
        let dimensions = parseSize(root["size"]?.asString)
            ?? parseSize(payload["size"]?.asString)
        return ImageGenerationResult(
            imageURL: nil,
            imageData: imageData,
            width: dimensions?.width,
            height: dimensions?.height,
            mediaType: mediaType(for: root["output_format"]?.asString ?? "png"),
            seed: nil
        )
    }

    private func performJSONRequest(url: URL, payload: JSONValue, timeoutMs: Int) async throws -> JSONValue {
        guard url.scheme?.lowercased() == "https", url.host?.isEmpty == false else {
            throw ImageGenerationProviderError.invalidRequest("OpenAI image endpoint must use HTTPS.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Double(max(1, timeoutMs)) / 1_000
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw ImageGenerationProviderError.timeout
        } catch {
            throw ImageGenerationProviderError.http(status: 0, message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ImageGenerationProviderError.invalidResponse("OpenAI returned a non-HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let errorPayload = try? JSONDecoder().decode(JSONValue.self, from: data)
            let message = errorPayload?.asObject?["error"]?.asObject?["message"]?.asString
                ?? errorPayload?.asObject?["message"]?.asString
                ?? "OpenAI returned HTTP \(http.statusCode)."
            throw ImageGenerationProviderError.http(status: http.statusCode, message: message)
        }
        guard let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw ImageGenerationProviderError.invalidResponse("OpenAI returned malformed JSON.")
        }
        return decoded
    }

    private func size(for aspectRatio: ImageGenerationAspectRatio) -> String {
        switch aspectRatio {
        case .landscape: "1536x1024"
        case .square: "1024x1024"
        case .portrait: "1024x1536"
        }
    }

    private func parseSize(_ value: String?) -> (width: Int, height: Int)? {
        guard let parts = value?.split(separator: "x", maxSplits: 1),
              parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1])
        else {
            return nil
        }
        return (width, height)
    }

    private func mediaType(for outputFormat: String) -> String {
        switch outputFormat.lowercased() {
        case "jpeg", "jpg": "image/jpeg"
        case "webp": "image/webp"
        default: "image/png"
        }
    }
}
