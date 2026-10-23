import Foundation

public struct ArtifactContentResponse: Codable, Sendable {
    public var id: String
    public var content: String

    public init(id: String, content: String) {
        self.id = id
        self.content = content
    }
}

public struct ArtifactWidgetMetadata: Codable, Sendable, Equatable {
    public var size: String
    public var width: Int
    public var height: Int
    public var entry: String

    public init(size: String, width: Int, height: Int, entry: String) {
        self.size = size
        self.width = width
        self.height = height
        self.entry = entry
    }
}

public struct ArtifactImageMetadata: Codable, Sendable, Equatable {
    public var width: Int?
    public var height: Int?
    public var fileName: String
    public var contentUrl: String

    public init(width: Int? = nil, height: Int? = nil, fileName: String, contentUrl: String) {
        self.width = width
        self.height = height
        self.fileName = fileName
        self.contentUrl = contentUrl
    }
}

public struct ArtifactRecord: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var kind: String
    public var mediaType: String
    public var createdAt: Date
    public var previewText: String?
    public var widget: ArtifactWidgetMetadata?
    public var image: ArtifactImageMetadata?

    public init(
        id: String,
        title: String,
        kind: String,
        mediaType: String,
        createdAt: Date,
        previewText: String? = nil,
        widget: ArtifactWidgetMetadata? = nil,
        image: ArtifactImageMetadata? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.mediaType = mediaType
        self.createdAt = createdAt
        self.previewText = previewText
        self.widget = widget
        self.image = image
    }
}

public struct ArtifactListResponse: Codable, Sendable, Equatable {
    public var artifacts: [ArtifactRecord]

    public init(artifacts: [ArtifactRecord]) {
        self.artifacts = artifacts
    }
}

public struct ArtifactDetailResponse: Codable, Sendable, Equatable {
    public var artifact: ArtifactRecord

    public init(artifact: ArtifactRecord) {
        self.artifact = artifact
    }
}

public struct WidgetArtifactGenerateRequest: Codable, Sendable, Equatable {
    public var prompt: String
    public var size: String
    public var html: String?

    public init(prompt: String, size: String, html: String? = nil) {
        self.prompt = prompt
        self.size = size
        self.html = html
    }
}

public struct WidgetArtifactGenerateResponse: Codable, Sendable, Equatable {
    public var artifact: ArtifactRecord
    public var sessionId: String?

    public init(artifact: ArtifactRecord, sessionId: String? = nil) {
        self.artifact = artifact
        self.sessionId = sessionId
    }
}

public struct WidgetArtifactContentResponse: Codable, Sendable, Equatable {
    public var id: String
    public var html: String
    public var size: String
    public var width: Int
    public var height: Int

    public init(id: String, html: String, size: String, width: Int, height: Int) {
        self.id = id
        self.html = html
        self.size = size
        self.width = width
        self.height = height
    }
}

public enum PublishedSiteVisibility: String, Codable, Sendable, Equatable, CaseIterable {
    case `private`
    case `public`
}

public struct PublishedSiteRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var slug: String
    public var title: String
    public var visibility: PublishedSiteVisibility
    public var ownerId: String
    public var projectId: String?
    public var entryFile: String
    public var revision: Int
    public var path: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        slug: String,
        title: String,
        visibility: PublishedSiteVisibility = .private,
        ownerId: String,
        projectId: String? = nil,
        entryFile: String = "index.html",
        revision: Int = 1,
        path: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.slug = slug
        self.title = title
        self.visibility = visibility
        self.ownerId = ownerId
        self.projectId = projectId
        self.entryFile = entryFile
        self.revision = revision
        self.path = path
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PublishedSiteListResponse: Codable, Sendable, Equatable {
    public var sites: [PublishedSiteRecord]

    public init(sites: [PublishedSiteRecord]) {
        self.sites = sites
    }
}

public struct PublishedSiteDetailResponse: Codable, Sendable, Equatable {
    public var site: PublishedSiteRecord

    public init(site: PublishedSiteRecord) {
        self.site = site
    }
}

public struct PublishedSiteUpdateRequest: Codable, Sendable, Equatable {
    public var title: String?
    public var slug: String?
    public var visibility: PublishedSiteVisibility?

    public init(
        title: String? = nil,
        slug: String? = nil,
        visibility: PublishedSiteVisibility? = nil
    ) {
        self.title = title
        self.slug = slug
        self.visibility = visibility
    }
}

public struct PublishedSiteDeleteResponse: Codable, Sendable, Equatable {
    public var deleted: Bool

    public init(deleted: Bool) {
        self.deleted = deleted
    }
}

public struct PublishedSiteLaunchResponse: Codable, Sendable, Equatable {
    public var url: String
    public var expiresAt: Date?

    public init(url: String, expiresAt: Date? = nil) {
        self.url = url
        self.expiresAt = expiresAt
    }
}

public struct BoardCanvasViewport: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var scale: Double

    public init(x: Double, y: Double, scale: Double) {
        self.x = x
        self.y = y
        self.scale = scale
    }
}

public struct BoardCanvasItem: Codable, Sendable, Equatable {
    public var id: String
    public var type: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var title: String
    public var zIndex: Int
    public var groupId: String?
    public var artifactId: String?
    public var url: String?
    public var text: String?
    public var assetPath: String?
    public var mediaType: String?

    public init(
        id: String,
        type: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        title: String,
        zIndex: Int,
        groupId: String? = nil,
        artifactId: String? = nil,
        url: String? = nil,
        text: String? = nil,
        assetPath: String? = nil,
        mediaType: String? = nil
    ) {
        self.id = id
        self.type = type
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.title = title
        self.zIndex = zIndex
        self.groupId = groupId
        self.artifactId = artifactId
        self.url = url
        self.text = text
        self.assetPath = assetPath
        self.mediaType = mediaType
    }
}

public struct BoardCanvasGroup: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var collapsed: Bool
    public var color: String?

    public init(
        id: String,
        title: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        collapsed: Bool,
        color: String? = nil
    ) {
        self.id = id
        self.title = title
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.collapsed = collapsed
        self.color = color
    }
}

public struct BoardArtifactRecord: Codable, Sendable, Equatable {
    public var id: String
    public var version: Int
    public var viewport: BoardCanvasViewport
    public var items: [BoardCanvasItem]
    public var groups: [BoardCanvasGroup]

    public init(
        id: String,
        version: Int,
        viewport: BoardCanvasViewport,
        items: [BoardCanvasItem],
        groups: [BoardCanvasGroup]
    ) {
        self.id = id
        self.version = version
        self.viewport = viewport
        self.items = items
        self.groups = groups
    }
}

public struct BoardArtifactResponse: Codable, Sendable, Equatable {
    public var board: BoardArtifactRecord

    public init(board: BoardArtifactRecord) {
        self.board = board
    }
}

public struct BoardAssetUploadRequest: Codable, Sendable, Equatable {
    public var filename: String
    public var mediaType: String
    public var dataBase64: String

    public init(filename: String, mediaType: String, dataBase64: String) {
        self.filename = filename
        self.mediaType = mediaType
        self.dataBase64 = dataBase64
    }
}

public struct BoardAssetUploadResponse: Codable, Sendable, Equatable {
    public var path: String
    public var mediaType: String
    public var sizeBytes: Int

    public init(path: String, mediaType: String, sizeBytes: Int) {
        self.path = path
        self.mediaType = mediaType
        self.sizeBytes = sizeBytes
    }
}

public struct PlanArtifactRecord: Codable, Sendable, Equatable {
    public var projectId: String
    public var projectName: String
    public var agentId: String
    public var sessionId: String
    public var messageEventId: String
    public var planName: String
    public var createdAt: Date
    public var storageKind: String
    public var markdownPath: String
    public var webUrl: String

    public init(
        projectId: String,
        projectName: String,
        agentId: String,
        sessionId: String,
        messageEventId: String,
        planName: String,
        createdAt: Date = Date(),
        storageKind: String,
        markdownPath: String,
        webUrl: String
    ) {
        self.projectId = projectId
        self.projectName = projectName
        self.agentId = agentId
        self.sessionId = sessionId
        self.messageEventId = messageEventId
        self.planName = planName
        self.createdAt = createdAt
        self.storageKind = storageKind
        self.markdownPath = markdownPath
        self.webUrl = webUrl
    }
}
