//
//  Content.swift
//  ACPModel
//
//  Agent Client Protocol - Content Block Types
//

import Foundation

// MARK: - Annotations

public struct Annotations: Codable, Sendable {
    public let audience: [String]?
    public let lastModified: String?
    public let priority: Int?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case audience
        case lastModified
        case priority, _meta
    }

    public init(audience: [String]? = nil, lastModified: String? = nil, priority: Int? = nil, _meta: [String: AnyCodable]? = nil) {
        self.audience = audience
        self.lastModified = lastModified
        self.priority = priority
        self._meta = _meta
    }
}

// MARK: - Content Types

public enum ContentBlock: Codable, Sendable {
    case text(TextContent)
    case image(ImageContent)
    case audio(AudioContent)
    case resourceLink(ResourceLinkContent)
    case resource(ResourceContent)

    enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try TextContent(from: decoder))
        case "image":
            self = .image(try ImageContent(from: decoder))
        case "audio":
            self = .audio(try AudioContent(from: decoder))
        case "resource_link":
            self = .resourceLink(try ResourceLinkContent(from: decoder))
        case "resource":
            self = .resource(try ResourceContent(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let content):
            try content.encode(to: encoder)
        case .image(let content):
            try content.encode(to: encoder)
        case .audio(let content):
            try content.encode(to: encoder)
        case .resourceLink(let content):
            try content.encode(to: encoder)
        case .resource(let content):
            try content.encode(to: encoder)
        }
    }
}

// MARK: - Text Content

public struct TextContent: Codable, Sendable {
    public let type: String = "text"
    public let text: String
    public let annotations: Annotations?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case type, text, annotations, _meta
    }

    public init(text: String, annotations: Annotations? = nil, _meta: [String: AnyCodable]? = nil) {
        self.text = text
        self.annotations = annotations
        self._meta = _meta
    }
}

// MARK: - Image Content

public struct ImageContent: Codable, Sendable {
    public let type: String = "image"
    public let data: String
    public let mimeType: String
    public let uri: String?
    public let annotations: Annotations?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case type, data, uri, mimeType, annotations, _meta
    }

    public init(data: String, mimeType: String, uri: String? = nil, annotations: Annotations? = nil, _meta: [String: AnyCodable]? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.uri = uri
        self.annotations = annotations
        self._meta = _meta
    }
}

// MARK: - Audio Content

public struct AudioContent: Codable, Sendable {
    public let type: String = "audio"
    public let data: String
    public let mimeType: String
    public let annotations: Annotations?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case type, data, mimeType, annotations, _meta
    }

    public init(data: String, mimeType: String, annotations: Annotations? = nil, _meta: [String: AnyCodable]? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.annotations = annotations
        self._meta = _meta
    }
}

// MARK: - Resource Link Content

public struct ResourceLinkContent: Codable, Sendable {
    public let type: String = "resource_link"
    public let uri: String
    public let name: String
    public let title: String?
    public let description: String?
    public let mimeType: String?
    public let size: Int?
    public let annotations: Annotations?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case type, uri, name, title, description, mimeType, size, annotations, _meta
    }

    public init(uri: String, name: String, title: String? = nil, description: String? = nil, mimeType: String? = nil, size: Int? = nil, annotations: Annotations? = nil, _meta: [String: AnyCodable]? = nil) {
        self.uri = uri
        self.name = name
        self.title = title
        self.description = description
        self.mimeType = mimeType
        self.size = size
        self.annotations = annotations
        self._meta = _meta
    }
}

// MARK: - Embedded Resource Types

public enum EmbeddedResourceType: Codable, Sendable {
    case text(EmbeddedTextResourceContents)
    case blob(EmbeddedBlobResourceContents)

    enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try EmbeddedTextResourceContents(from: decoder))
        case "blob":
            self = .blob(try EmbeddedBlobResourceContents(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown resource type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let content):
            try content.encode(to: encoder)
        case .blob(let content):
            try content.encode(to: encoder)
        }
    }
}

public struct EmbeddedTextResourceContents: Codable, Sendable {
    public let type: String = "text"
    public let text: String
    public let mimeType: String?
    public let uri: String
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case type, text, mimeType, uri, _meta
    }

    public init(text: String, uri: String, mimeType: String? = nil, _meta: [String: AnyCodable]? = nil) {
        self.text = text
        self.uri = uri
        self.mimeType = mimeType
        self._meta = _meta
    }
}

public struct EmbeddedBlobResourceContents: Codable, Sendable {
    public let type: String = "blob"
    public let blob: String
    public let mimeType: String?
    public let uri: String
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case type, blob, mimeType, uri, _meta
    }

    public init(blob: String, uri: String, mimeType: String? = nil, _meta: [String: AnyCodable]? = nil) {
        self.blob = blob
        self.uri = uri
        self.mimeType = mimeType
        self._meta = _meta
    }
}

// MARK: - Resource Content

public struct ResourceContent: Codable, Sendable {
    public let type: String = "resource"
    public let resource: EmbeddedResourceType
    public let annotations: Annotations?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case type, resource, annotations, _meta
    }

    public init(resource: EmbeddedResourceType, annotations: Annotations? = nil, _meta: [String: AnyCodable]? = nil) {
        self.resource = resource
        self.annotations = annotations
        self._meta = _meta
    }
}

extension EmbeddedResourceType {
    public var uri: String? {
        switch self {
        case .text(let contents): return contents.uri
        case .blob(let contents): return contents.uri
        }
    }

    public var mimeType: String? {
        switch self {
        case .text(let contents): return contents.mimeType
        case .blob(let contents): return contents.mimeType
        }
    }

    public var text: String? {
        switch self {
        case .text(let contents): return contents.text
        case .blob: return nil
        }
    }
}

// MARK: - ContentBlock helpers

extension ContentBlock {
    public func toDictionary() -> [String: any Sendable] {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: any Sendable] else {
            return [:]
        }
        return dict
    }
}
