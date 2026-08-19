import AnyLanguageModel
import Foundation
import Protocols

struct ImagesGenerateTool: CoreTool {
    let domain = "images"
    let title = "Generate image"
    let status = "fully_functional"
    let name = "images.generate"
    let description = "Generate one image from a text prompt, or edit source/reference images, using the image provider selected by the user. The result is saved as a durable local artifact and includes an artifact content URL."

    private let providerFactory: @Sendable (CoreConfig.ImageGeneration.ProviderID, String, URL?) -> any ImageGenerationProvider

    init(providerFactory: @escaping @Sendable (CoreConfig.ImageGeneration.ProviderID, String, URL?) -> any ImageGenerationProvider = { provider, apiKey, apiBaseURL in
        switch provider {
        case .fal:
            FALImageGenerationProvider(apiKey: apiKey)
        case .openAI:
            OpenAIImageGenerationProvider(
                apiKey: apiKey,
                apiBaseURL: apiBaseURL ?? URL(string: "https://api.openai.com/v1")!
            )
        }
    }) {
        self.providerFactory = providerFactory
    }

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "prompt", description: "Detailed prompt describing the desired image or edit.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "aspectRatio", description: "Optional output aspect ratio: landscape, square, or portrait. Omit during editing to preserve source proportions.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "sourceImage", description: "Optional primary HTTPS URL, data:image URL, or readable local image path to edit.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "referenceImages", description: "Optional additional reference image URLs or readable local paths. The configured model determines the maximum count.", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true),
            .init(name: "seed", description: "Optional integer seed for reproducible output when supported by the selected provider.", schema: DynamicGenerationSchema(type: Int.self), isOptional: true),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let prompt = arguments["prompt"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !prompt.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`prompt` is required.", retryable: false)
        }
        guard prompt.utf8.count <= 32_000 else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`prompt` is too large.", retryable: false)
        }

        let aspectRatio: ImageGenerationAspectRatio?
        if let rawAspect = arguments["aspectRatio"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawAspect.isEmpty {
            guard let parsed = ImageGenerationAspectRatio(rawValue: rawAspect.lowercased()) else {
                return toolFailure(tool: name, code: "invalid_arguments", message: "`aspectRatio` must be landscape, square, or portrait.", retryable: false)
            }
            aspectRatio = parsed
        } else {
            aspectRatio = nil
        }

        let seed: Int?
        if let rawSeed = arguments["seed"]?.asNumber {
            guard rawSeed.isFinite,
                  rawSeed.rounded() == rawSeed,
                  rawSeed >= Double(Int.min),
                  rawSeed <= Double(Int.max)
            else {
                return toolFailure(tool: name, code: "invalid_arguments", message: "`seed` must be an integer.", retryable: false)
            }
            seed = Int(rawSeed)
        } else {
            seed = nil
        }

        guard let configService = context.configService else {
            return toolFailure(tool: name, code: "not_configured", message: "Runtime configuration is unavailable.", retryable: false)
        }
        let runtimeConfig = await configService.runtimeConfig()
        let config = runtimeConfig.imageGeneration
        guard config.enabled else {
            return toolFailure(tool: name, code: "image_generation_disabled", message: "Image generation is disabled in Settings.", retryable: false)
        }
        guard let model = ImageGenerationCatalog.model(id: config.model), model.provider == config.provider else {
            return toolFailure(tool: name, code: "unsupported_model", message: "Configured image model is not supported.", retryable: false)
        }
        let credential = ImageGenerationCredentialResolver.resolve(
            provider: config.provider,
            config: config,
            models: runtimeConfig.models,
            environmentOverrides: context.environmentOverrides,
            processEnvironment: ProcessInfo.processInfo.environment
        )
        guard !credential.apiKey.isEmpty else {
            let message = config.provider == .openAI
                ? "Set OPENAI_API_KEY or configure an OpenAI API provider key in Settings."
                : "Set FAL_KEY or configure a FAL API key in Settings."
            return toolFailure(tool: name, code: "not_configured", message: message, retryable: false)
        }

        let rawSources = sourceArguments(arguments)
        guard rawSources.count <= model.maxReferenceImages else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "At most \(model.maxReferenceImages) source/reference images are supported.", retryable: false)
        }

        let sources: [String]
        do {
            sources = try resolveSourceImages(rawSources, context: context)
        } catch let error as SourceImageError {
            return toolFailure(tool: name, code: "invalid_arguments", message: error.message, retryable: false)
        } catch {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Failed to read a source image.", retryable: false)
        }

        let request = ImageGenerationRequest(
            prompt: prompt,
            aspectRatio: aspectRatio,
            sourceImages: sources,
            seed: seed
        )
        let provider = providerFactory(config.provider, credential.apiKey, credential.apiBaseURL)
        let generated: ImageGenerationResult
        do {
            generated = try await provider.generate(request: request, model: model, timeoutMs: config.timeoutMs)
        } catch is CancellationError {
            return toolFailure(tool: name, code: "provider_timeout", message: "Image generation was cancelled.", retryable: true)
        } catch let error as ImageGenerationProviderError {
            return providerFailure(error)
        } catch {
            context.logger.error("Image generation failed", metadata: ["error": .string(error.localizedDescription)])
            return toolFailure(tool: name, code: "provider_http_error", message: "Image provider request failed.", retryable: true)
        }

        let artifact: StoredImageArtifact
        do {
            if let imageData = generated.imageData {
                artifact = try ImageArtifactService.create(
                    data: imageData,
                    mediaType: generated.mediaType,
                    prompt: prompt,
                    provider: config.provider.rawValue,
                    model: model.id,
                    modality: request.modality,
                    seed: generated.seed,
                    width: generated.width,
                    height: generated.height,
                    workspaceRootURL: context.workspaceRootURL
                )
            } else if let imageURL = generated.imageURL {
                artifact = try await ImageArtifactService.create(
                    remoteURL: imageURL,
                    prompt: prompt,
                    provider: config.provider.rawValue,
                    model: model.id,
                    modality: request.modality,
                    seed: generated.seed,
                    width: generated.width,
                    height: generated.height,
                    workspaceRootURL: context.workspaceRootURL
                )
            } else {
                throw ImageArtifactService.ArtifactError.invalidImage
            }
        } catch {
            context.logger.error("Generated image artifact write failed", metadata: ["error": .string(error.localizedDescription)])
            return toolFailure(tool: name, code: "artifact_write_failed", message: "The generated image could not be saved.", retryable: true)
        }

        await context.store.persistArtifact(record: PersistedArtifactRecord(
            id: artifact.id,
            title: String(prompt.prefix(80)),
            kind: "image",
            mediaType: artifact.mediaType,
            content: artifact.manifestJSON,
            previewText: String(prompt.prefix(160)),
            bundlePath: ImageArtifactService.bundlePath(id: artifact.id),
            createdAt: Date()
        ))

        var data: [String: JSONValue] = [
            "provider": .string(config.provider.rawValue),
            "model": .string(model.id),
            "modality": .string(request.modality.rawValue),
            "artifact": .object([
                "id": .string(artifact.id),
                "kind": .string("image"),
                "mediaType": .string(artifact.mediaType),
                "path": .string(artifact.fileURL.path),
                "contentUrl": .string(artifact.contentURL),
                "width": artifact.width.map { .number(Double($0)) } ?? .null,
                "height": artifact.height.map { .number(Double($0)) } ?? .null,
            ]),
        ]
        if let resultSeed = generated.seed {
            data["seed"] = .number(Double(resultSeed))
        }
        return toolSuccess(tool: name, data: .object(data))
    }

    private func providerFailure(_ error: ImageGenerationProviderError) -> ToolInvocationResult {
        switch error {
        case .unsupportedModel:
            return toolFailure(tool: name, code: "unsupported_model", message: "Configured image model is not supported.", retryable: false)
        case .unsupportedModality:
            return toolFailure(tool: name, code: "unsupported_modality", message: "Configured image model does not support editing.", retryable: false)
        case .invalidRequest(let message):
            return toolFailure(tool: name, code: "invalid_arguments", message: message, retryable: false)
        case .http(let status, let message):
            return toolFailure(tool: name, code: "provider_http_error", message: message, retryable: status == 0 || status == 408 || status == 429 || status >= 500)
        case .timeout:
            return toolFailure(tool: name, code: "provider_timeout", message: "Image provider timed out.", retryable: true)
        case .invalidResponse(let message):
            return toolFailure(tool: name, code: "provider_invalid_response", message: message, retryable: true)
        }
    }
}

private enum SourceImageError: Error {
    case invalid(String)

    var message: String {
        switch self {
        case .invalid(let message): message
        }
    }
}

enum ImageGenerationCredentialResolver {
    struct Credential: Sendable, Equatable {
        var apiKey: String
        var apiBaseURL: URL?
    }

    static func resolve(
        provider: CoreConfig.ImageGeneration.ProviderID,
        config: CoreConfig.ImageGeneration,
        models: [CoreConfig.ModelConfig],
        environmentOverrides: [String: String],
        processEnvironment: [String: String]
    ) -> Credential {
        switch provider {
        case .fal:
            let candidates = [
                environmentOverrides["FAL_KEY"],
                processEnvironment["FAL_KEY"],
                config.fal.apiKey,
            ]
            let key = candidates.compactMap(trimmed).first { !$0.isEmpty } ?? ""
            return Credential(apiKey: key, apiBaseURL: nil)
        case .openAI:
            let configured = models.first { model in
                model.providerCatalogId == "openai-api"
                    && !model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } ?? models.first { model in
                URL(string: model.apiUrl)?.host?.lowercased() == "api.openai.com"
                    && !model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let candidates = [
                environmentOverrides["OPENAI_API_KEY"],
                processEnvironment["OPENAI_API_KEY"],
                configured?.apiKey,
            ]
            let key = candidates.compactMap(trimmed).first { !$0.isEmpty } ?? ""
            let configuredURL = configured.flatMap { URL(string: $0.apiUrl) }
            let baseURL = configuredURL?.scheme?.lowercased() == "https"
                ? configuredURL
                : URL(string: "https://api.openai.com/v1")
            return Credential(apiKey: key, apiBaseURL: baseURL)
        }
    }

    private static func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func sourceArguments(_ arguments: [String: JSONValue]) -> [String] {
    var sources: [String] = []
    if let source = arguments["sourceImage"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty {
        sources.append(source)
    }
    if let references = arguments["referenceImages"]?.asArray {
        sources.append(contentsOf: references.compactMap { value in
            let source = value.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return source.isEmpty ? nil : source
        })
    }
    return sources
}

private func resolveSourceImages(_ sources: [String], context: ToolContext) throws -> [String] {
    let maximumImageBytes = 10 * 1024 * 1024
    let maximumTotalBytes = 20 * 1024 * 1024
    var totalBytes = 0
    return try sources.map { source in
        if source.lowercased().hasPrefix("data:") {
            let parsed = try validatedImageDataURL(source)
            guard parsed.byteCount <= maximumImageBytes else {
                throw SourceImageError.invalid("Each source image must be 10 MB or smaller.")
            }
            totalBytes += parsed.byteCount
            guard totalBytes <= maximumTotalBytes else {
                throw SourceImageError.invalid("Source images must be 20 MB or smaller in total.")
            }
            return source
        }
        if let url = URL(string: source), url.scheme != nil {
            guard url.scheme?.lowercased() == "https", url.host?.isEmpty == false else {
                throw SourceImageError.invalid("Remote source images must use HTTPS.")
            }
            return source
        }
        guard let fileURL = context.resolveReadablePath(source),
              FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL)
        else {
            throw SourceImageError.invalid("Source image path is outside readable roots or does not exist.")
        }
        guard data.count <= maximumImageBytes else {
            throw SourceImageError.invalid("Each source image must be 10 MB or smaller.")
        }
        guard let mediaType = localImageMediaType(fileURL: fileURL, data: data) else {
            throw SourceImageError.invalid("Source files must be PNG, JPEG, or WebP images.")
        }
        totalBytes += data.count
        guard totalBytes <= maximumTotalBytes else {
            throw SourceImageError.invalid("Source images must be 20 MB or smaller in total.")
        }
        return "data:\(mediaType);base64,\(data.base64EncodedString())"
    }
}

private func validatedImageDataURL(_ value: String) throws -> (byteCount: Int, mediaType: String) {
    guard let comma = value.firstIndex(of: ",") else {
        throw SourceImageError.invalid("Invalid image data URL.")
    }
    let header = String(value[..<comma]).lowercased()
    guard header.hasSuffix(";base64"),
          let mediaType = header.dropFirst("data:".count).split(separator: ";").first.map(String.init),
          ["image/png", "image/jpeg", "image/webp"].contains(mediaType),
          let data = Data(base64Encoded: String(value[value.index(after: comma)...])),
          !data.isEmpty
    else {
        throw SourceImageError.invalid("Image data URLs must contain base64 PNG, JPEG, or WebP data.")
    }
    return (data.count, mediaType)
}

private func localImageMediaType(fileURL: URL, data: Data) -> String? {
    switch fileURL.pathExtension.lowercased() {
    case "png": return data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : nil
    case "jpg", "jpeg": return data.starts(with: [0xFF, 0xD8, 0xFF]) ? "image/jpeg" : nil
    case "webp":
        let bytes = [UInt8](data.prefix(12))
        guard bytes.count >= 12,
              String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: bytes[8..<12], encoding: .ascii) == "WEBP"
        else { return nil }
        return "image/webp"
    default: return nil
    }
}
