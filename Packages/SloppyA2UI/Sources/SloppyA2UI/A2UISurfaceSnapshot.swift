import Foundation

/// A materialized Sloppy surface, not an A2UI transport envelope.
/// This first catalog supports literal Text and Column components only.
public struct A2UIComponent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case text = "Text"
        case column = "Column"
    }

    public var id: String
    public var component: Kind
    public var text: String?
    public var children: [String]?

    public init(id: String, component: Kind, text: String? = nil, children: [String]? = nil) {
        self.id = id
        self.component = component
        self.text = text
        self.children = children
    }
}

public struct A2UISurfaceSnapshot: Codable, Sendable, Equatable {
    public static let supportedProtocolVersion = "0.9.1"
    public static let supportedCatalogID = "urn:sloppy:a2ui:catalog:v1"

    public var protocolVersion: String
    public var catalogId: String
    public var surfaceId: String
    public var revision: Int
    public var fallbackText: String
    public var components: [A2UIComponent]

    public init(
        surfaceId: String, revision: Int, fallbackText: String, components: [A2UIComponent],
        protocolVersion: String = Self.supportedProtocolVersion,
        catalogId: String = Self.supportedCatalogID
    ) {
        self.protocolVersion = protocolVersion
        self.catalogId = catalogId
        self.surfaceId = surfaceId
        self.revision = revision
        self.fallbackText = fallbackText
        self.components = components
    }

    public enum ValidationError: Error, Sendable, Equatable {
        case unsupportedProtocol
        case unsupportedCatalog
        case invalidMetadata
        case sizeLimit
        case invalidComponent(String)
        case invalidTree
    }

    /// Validate at every trust boundary before persisting or presenting a surface.
    /// Decoding alone preserves unknown versions for callers to reject without losing fallback text.
    public func validate() throws {
        guard protocolVersion == Self.supportedProtocolVersion else { throw ValidationError.unsupportedProtocol }
        guard catalogId == Self.supportedCatalogID else { throw ValidationError.unsupportedCatalog }
        guard Self.validID(surfaceId), revision > 0,
              !fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.invalidMetadata
        }
        guard (1...128).contains(components.count), fallbackText.utf8.count <= 16_384,
              try JSONEncoder().encode(self).count <= 65_536 else { throw ValidationError.sizeLimit }

        var byID: [String: A2UIComponent] = [:]
        for item in components {
            guard Self.validID(item.id), byID[item.id] == nil else {
                throw ValidationError.invalidComponent(item.id)
            }
            switch item.component {
            case .text:
                guard let text = item.text, text.utf8.count <= 16_384, item.children == nil else {
                    throw ValidationError.invalidComponent(item.id)
                }
            case .column:
                guard item.text == nil, let children = item.children, children.count <= 128 else {
                    throw ValidationError.invalidComponent(item.id)
                }
            }
            byID[item.id] = item
        }

        var visited: Set<String> = []
        func visit(_ id: String, depth: Int) throws {
            guard depth <= 16, let item = byID[id], visited.insert(id).inserted else {
                throw ValidationError.invalidTree
            }
            for child in item.children ?? [] { try visit(child, depth: depth + 1) }
        }
        // A2UI uses the reserved component ID "root" as the entry point.
        try visit("root", depth: 1)
        guard visited.count == components.count else { throw ValidationError.invalidTree }
    }

    private static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
}
