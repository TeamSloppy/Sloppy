import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols

struct FALImageGenerationProvider: ImageGenerationProvider, Sendable {
    private let apiKey: String
    private let session: URLSession
    private let queueBaseURL: URL
    private let pollIntervalNanoseconds: UInt64

    init(
        apiKey: String,
        session: URLSession = .shared,
        queueBaseURL: URL = URL(string: "https://queue.fal.run")!,
        pollIntervalNanoseconds: UInt64 = 750_000_000
    ) {
        self.apiKey = apiKey
        self.session = session
        self.queueBaseURL = queueBaseURL
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
    }

    func generate(
        request: ImageGenerationRequest,
        model: ImageGenerationModelDefinition,
        timeoutMs: Int
    ) async throws -> ImageGenerationResult {
        let endpoint: String
        switch request.modality {
        case .textToImage:
            endpoint = model.id
        case .imageEdit:
            guard let editEndpoint = model.editEndpoint else {
                throw ImageGenerationProviderError.unsupportedModality
            }
            guard request.sourceImages.count <= model.maxReferenceImages else {
                throw ImageGenerationProviderError.invalidRequest("Too many reference images.")
            }
            endpoint = editEndpoint
        }

        let submitURL = queueBaseURL.appendingPathComponent(endpoint)
        let payload = payload(for: request)
        let submitResponse = try await performJSONRequest(url: submitURL, method: "POST", payload: payload)
        guard let object = submitResponse.asObject,
              let requestID = object["request_id"]?.asString,
              !requestID.isEmpty
        else {
            throw ImageGenerationProviderError.invalidResponse("FAL submit response did not contain request_id.")
        }

        let statusURL = try validatedQueueURL(
            object["status_url"]?.asString,
            fallback: submitURL.appendingPathComponent("requests").appendingPathComponent(requestID).appendingPathComponent("status")
        )
        let responseURL = try validatedQueueURL(
            object["response_url"]?.asString,
            fallback: submitURL.appendingPathComponent("requests").appendingPathComponent(requestID)
        )

        let timeout = UInt64(max(1, timeoutMs)) * 1_000_000
        let started = ContinuousClock.now
        while true {
            try Task.checkCancellation()
            if started.duration(to: .now) >= .nanoseconds(Int64(clamping: timeout)) {
                throw ImageGenerationProviderError.timeout
            }

            let statusPayload = try await performJSONRequest(url: statusURL, method: "GET", payload: nil)
            guard let status = statusPayload.asObject?["status"]?.asString?.uppercased() else {
                throw ImageGenerationProviderError.invalidResponse("FAL status response did not contain status.")
            }
            if status == "COMPLETED" {
                break
            }
            if ["FAILED", "CANCELLED"].contains(status) {
                let message = statusPayload.asObject?["error"]?.asString ?? "FAL request \(status.lowercased())."
                throw ImageGenerationProviderError.http(status: 502, message: message)
            }
            guard ["IN_QUEUE", "IN_PROGRESS"].contains(status) else {
                throw ImageGenerationProviderError.invalidResponse("Unknown FAL queue status: \(status).")
            }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        let resultPayload = try await performJSONRequest(url: responseURL, method: "GET", payload: nil)
        var result = try decodeResult(resultPayload)
        if result.seed == nil {
            result.seed = request.seed
        }
        return result
    }

    private func payload(for request: ImageGenerationRequest) -> JSONValue {
        var input: [String: JSONValue] = [
            "prompt": .string(request.prompt),
            "num_images": .number(1),
            "output_format": .string("png"),
            "enable_safety_checker": .bool(true),
        ]
        if let seed = request.seed {
            input["seed"] = .number(Double(seed))
        }
        if let aspectRatio = request.aspectRatio {
            input["image_size"] = .string(imageSize(for: aspectRatio))
        } else if request.modality == .textToImage {
            input["image_size"] = .string(imageSize(for: .landscape))
        }
        if !request.sourceImages.isEmpty {
            input["image_urls"] = .array(request.sourceImages.map(JSONValue.string))
        }
        return .object(input)
    }

    private func imageSize(for aspectRatio: ImageGenerationAspectRatio) -> String {
        switch aspectRatio {
        case .landscape: "landscape_16_9"
        case .square: "square_hd"
        case .portrait: "portrait_16_9"
        }
    }

    private func decodeResult(_ payload: JSONValue) throws -> ImageGenerationResult {
        let root = payload.asObject?["data"]?.asObject ?? payload.asObject
        guard let image = root?["images"]?.asArray?.first?.asObject,
              let rawURL = image["url"]?.asString,
              let url = URL(string: rawURL),
              url.scheme?.lowercased() == "https"
        else {
            throw ImageGenerationProviderError.invalidResponse("FAL result did not contain a valid HTTPS image URL.")
        }
        return ImageGenerationResult(
            imageURL: url,
            imageData: nil,
            width: image["width"]?.asNumber.map(Int.init),
            height: image["height"]?.asNumber.map(Int.init),
            mediaType: image["content_type"]?.asString,
            seed: root?["seed"]?.asNumber.map(Int.init)
        )
    }

    private func performJSONRequest(url: URL, method: String, payload: JSONValue?) async throws -> JSONValue {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ImageGenerationProviderError.http(status: 0, message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ImageGenerationProviderError.invalidResponse("FAL returned a non-HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = (try? JSONDecoder().decode(JSONValue.self, from: data))
            let message = body?.asObject?["detail"]?.asString
                ?? body?.asObject?["error"]?.asString
                ?? "FAL returned HTTP \(http.statusCode)."
            throw ImageGenerationProviderError.http(status: http.statusCode, message: message)
        }
        guard let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw ImageGenerationProviderError.invalidResponse("FAL returned malformed JSON.")
        }
        return decoded
    }

    private func validatedQueueURL(_ rawValue: String?, fallback: URL) throws -> URL {
        guard let rawValue, !rawValue.isEmpty else {
            return fallback
        }
        guard let url = URL(string: rawValue),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "queue.fal.run"
        else {
            throw ImageGenerationProviderError.invalidResponse("FAL returned an invalid queue URL.")
        }
        return url
    }
}
