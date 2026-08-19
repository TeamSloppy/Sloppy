import Foundation
import Protocols

enum ImageGenerationModality: String, Codable, Sendable {
    case textToImage = "text_to_image"
    case imageEdit = "image_edit"
}

enum ImageGenerationAspectRatio: String, Codable, Sendable, CaseIterable {
    case landscape
    case square
    case portrait
}

struct ImageGenerationRequest: Sendable {
    var prompt: String
    var aspectRatio: ImageGenerationAspectRatio?
    var sourceImages: [String]
    var seed: Int?

    var modality: ImageGenerationModality {
        sourceImages.isEmpty ? .textToImage : .imageEdit
    }
}

struct ImageGenerationResult: Sendable {
    var imageURL: URL?
    var imageData: Data?
    var width: Int?
    var height: Int?
    var mediaType: String?
    var seed: Int?
}

struct ImageGenerationModelDefinition: Sendable, Equatable {
    var id: String
    var title: String
    var provider: CoreConfig.ImageGeneration.ProviderID
    var editEndpoint: String?
    var maxReferenceImages: Int

    var apiOption: ImageGenerationModelOption {
        ImageGenerationModelOption(
            id: id,
            title: title,
            provider: provider.rawValue,
            supportsEditing: editEndpoint != nil,
            maxReferenceImages: maxReferenceImages
        )
    }
}

enum ImageGenerationCatalog {
    static let models: [ImageGenerationModelDefinition] = [
        ImageGenerationModelDefinition(
            id: "fal-ai/flux-2",
            title: "FLUX 2",
            provider: .fal,
            editEndpoint: "fal-ai/flux-2/edit",
            maxReferenceImages: 4
        ),
        ImageGenerationModelDefinition(
            id: "fal-ai/flux-2-pro",
            title: "FLUX 2 Pro",
            provider: .fal,
            editEndpoint: "fal-ai/flux-2-pro/edit",
            maxReferenceImages: 4
        ),
        ImageGenerationModelDefinition(
            id: "gpt-image-2",
            title: "GPT Image 2",
            provider: .openAI,
            editEndpoint: "v1/images/edits",
            maxReferenceImages: 16
        ),
    ]

    static func model(id: String) -> ImageGenerationModelDefinition? {
        models.first { $0.id == id }
    }

    static func models(for provider: CoreConfig.ImageGeneration.ProviderID) -> [ImageGenerationModelDefinition] {
        models.filter { $0.provider == provider }
    }
}

enum ImageGenerationProviderError: Error, Sendable, Equatable {
    case unsupportedModel
    case unsupportedModality
    case invalidRequest(String)
    case http(status: Int, message: String)
    case timeout
    case invalidResponse(String)
}

protocol ImageGenerationProvider: Sendable {
    func generate(
        request: ImageGenerationRequest,
        model: ImageGenerationModelDefinition,
        timeoutMs: Int
    ) async throws -> ImageGenerationResult
}
