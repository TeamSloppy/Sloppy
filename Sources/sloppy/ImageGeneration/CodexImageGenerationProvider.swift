import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(ImageIO)
import ImageIO
#endif

struct CodexImageGenerationProvider: ImageGenerationProvider {
    typealias Credentials = (accessToken: String, accountID: String)
    var credentials: @Sendable (Bool) async throws -> Credentials
    let hostModel: String
    var session: URLSession = Self.defaultSession
    private static let defaultSession = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)

    func generate(
        request: ImageGenerationRequest,
        model: ImageGenerationModelDefinition,
        timeoutMs: Int
    ) async throws -> ImageGenerationResult {
        guard model.provider == .codex else { throw ImageGenerationProviderError.unsupportedModel }
        guard request.seed == nil else {
            throw ImageGenerationProviderError.invalidRequest("Codex image generation does not support a seed.")
        }
        guard request.sourceImages.count <= model.maxReferenceImages else {
            throw ImageGenerationProviderError.invalidRequest("Too many reference images.")
        }
        guard let endpoint = URL(string: "https://chatgpt.com/backend-api/codex/responses") else {
            throw ImageGenerationProviderError.invalidResponse("Invalid Codex endpoint.")
        }

        let size: String
        switch request.aspectRatio {
        case .landscape: size = "1536x1024"
        case .square: size = "1024x1024"
        case .portrait: size = "1024x1536"
        case nil: size = request.sourceImages.isEmpty ? "1536x1024" : "auto"
        }
        let input = [["type": "input_text", "text": request.prompt]] + request.sourceImages.map {
            ["type": "input_image", "image_url": $0, "detail": "auto"]
        }
        let tool = [
            "type": "image_generation",
            "model": model.id,
            "size": size,
            "quality": "medium",
            "background": "opaque",
            "output_format": "png",
            "action": request.sourceImages.isEmpty ? "generate" : "edit",
        ]
        let body = try JSONSerialization.data(withJSONObject: [
            "model": hostModel,
            "instructions": "Fulfill the request using the image_generation tool.",
            "store": false,
            "stream": true,
            "input": [["type": "message", "role": "user", "content": input]],
            "tools": [tool],
            "tool_choice": ["type": "allowed_tools", "mode": "required", "tools": [["type": "image_generation"]]],
        ])
        var originalAccountID: String?
        for refresh in [false, true] {
            try Task.checkCancellation()
            let account = try await credentials(refresh)
            guard originalAccountID == nil || originalAccountID == account.accountID else {
                throw ImageGenerationProviderError.http(status: 401, message: "The connected Codex account changed. Start image generation again.")
            }
            originalAccountID = account.accountID
            var httpRequest = URLRequest(url: endpoint, timeoutInterval: Double(timeoutMs) / 1000)
            httpRequest.httpMethod = "POST"
            httpRequest.httpBody = body
            httpRequest.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "Authorization")
            httpRequest.setValue(account.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
            httpRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            httpRequest.setValue("sloppy", forHTTPHeaderField: "originator")
            httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: httpRequest)
            } catch let error as URLError where error.code == .timedOut {
                throw ImageGenerationProviderError.timeout
            }
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else {
                throw ImageGenerationProviderError.invalidResponse("Codex returned a non-HTTP response.")
            }
            if http.statusCode == 401, !refresh { continue }
            guard (200..<300).contains(http.statusCode) else {
                let message = switch http.statusCode {
                case 401, 403: "Reconnect Codex under Settings → Providers."
                case 429: "Codex image generation is rate limited."
                default: "Codex rejected the image request (HTTP \(http.statusCode))."
                }
                throw ImageGenerationProviderError.http(status: http.statusCode, message: message)
            }
            let png = try Self.completedImage(in: data)
            let dimensions = try Self.pngDimensions(png)
            return .init(imageData: png, width: dimensions.width, height: dimensions.height, mediaType: "image/png")
        }
        throw ImageGenerationProviderError.http(status: 401, message: "Reconnect Codex under Settings → Providers.")
    }

    private struct Event: Decodable {
        struct Item: Decodable {
            var type: String
            var result: String?
        }
        struct Response: Decodable { var output: [Item]? }
        var type: String
        var item: Item?
        var response: Response?
    }

    static func completedImage(in data: Data) throws -> Data {
        let decoder = JSONDecoder()
        var encoded: String?
        for line in data.split(separator: 10) {
            guard line.starts(with: "data:".utf8),
                  let event = try? decoder.decode(Event.self, from: Data(line.dropFirst(5))) else { continue }
            switch event.type {
            case "response.output_item.done":
                if event.item?.type == "image_generation_call", let result = event.item?.result, !result.isEmpty {
                    encoded = result
                }
            case "response.completed":
                let final = event.response?.output?.first { $0.type == "image_generation_call" && $0.result?.isEmpty == false }
                guard let image = final?.result ?? encoded,
                      let decoded = Data(base64Encoded: image),
                      decoded.count <= ImageArtifactService.maximumOutputBytes else {
                    throw ImageGenerationProviderError.invalidResponse("Codex returned no valid final image.")
                }
                return decoded
            case "response.failed", "response.incomplete", "error":
                throw ImageGenerationProviderError.invalidResponse("Codex did not complete image generation.")
            default:
                continue
            }
        }
        throw ImageGenerationProviderError.invalidResponse("Codex image stream ended before completion.")
    }

    private static func pngDimensions(_ data: Data) throws -> (width: Int, height: Int) {
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard data.count >= 45, data.starts(with: signature),
              data[8..<16].elementsEqual([0, 0, 0, 13, 73, 72, 68, 82]),
              data.suffix(12).elementsEqual([0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]) else {
            throw ImageGenerationProviderError.invalidResponse("Codex returned an invalid PNG.")
        }
        let width = data[16..<20].reduce(0) { ($0 << 8) | Int($1) }
        let height = data[20..<24].reduce(0) { ($0 << 8) | Int($1) }
        guard (1...8192).contains(width), (1...8192).contains(height) else {
            throw ImageGenerationProviderError.invalidResponse("Codex returned invalid PNG dimensions.")
        }
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw ImageGenerationProviderError.invalidResponse("Codex returned an unreadable PNG.")
        }
        #endif
        return (width, height)
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) { completionHandler(nil) }
    }

}
