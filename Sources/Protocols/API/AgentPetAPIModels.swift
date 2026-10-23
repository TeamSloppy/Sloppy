import Foundation

public enum AgentPetRarityTier: String, Codable, Sendable, Equatable {
    case common
    case uncommon
    case rare
    case legendary
}

public struct AgentPetParts: Codable, Sendable, Equatable {
    public var headId: String
    public var bodyId: String
    public var legsId: String
    public var faceId: String
    public var accessoryId: String

    public init(headId: String, bodyId: String, legsId: String, faceId: String = "face-default", accessoryId: String = "acc-none") {
        self.headId = headId
        self.bodyId = bodyId
        self.legsId = legsId
        self.faceId = faceId
        self.accessoryId = accessoryId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        headId = try container.decode(String.self, forKey: .headId)
        bodyId = try container.decode(String.self, forKey: .bodyId)
        legsId = try container.decode(String.self, forKey: .legsId)
        faceId = try container.decodeIfPresent(String.self, forKey: .faceId) ?? "face-default"
        accessoryId = try container.decodeIfPresent(String.self, forKey: .accessoryId) ?? "acc-none"
    }
}

public struct AgentPetPartRarities: Codable, Sendable, Equatable {
    public var head: AgentPetRarityTier
    public var body: AgentPetRarityTier
    public var legs: AgentPetRarityTier
    public var face: AgentPetRarityTier
    public var accessory: AgentPetRarityTier

    public init(head: AgentPetRarityTier, body: AgentPetRarityTier, legs: AgentPetRarityTier, face: AgentPetRarityTier = .common, accessory: AgentPetRarityTier = .common) {
        self.head = head
        self.body = body
        self.legs = legs
        self.face = face
        self.accessory = accessory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        head = try container.decode(AgentPetRarityTier.self, forKey: .head)
        body = try container.decode(AgentPetRarityTier.self, forKey: .body)
        legs = try container.decode(AgentPetRarityTier.self, forKey: .legs)
        face = try container.decodeIfPresent(AgentPetRarityTier.self, forKey: .face) ?? .common
        accessory = try container.decodeIfPresent(AgentPetRarityTier.self, forKey: .accessory) ?? .common
    }
}

public struct AgentPetStats: Codable, Sendable, Equatable {
    public var wisdom: Int
    public var debugging: Int
    public var patience: Int
    public var snark: Int
    public var chaos: Int

    public init(
        wisdom: Int = 0,
        debugging: Int = 0,
        patience: Int = 0,
        snark: Int = 0,
        chaos: Int = 0
    ) {
        self.wisdom = wisdom
        self.debugging = debugging
        self.patience = patience
        self.snark = snark
        self.chaos = chaos
    }
}

public struct AgentPetTerminalFaceSet: Codable, Sendable, Equatable {
    public var idle: String
    public var happy: String
    public var sad: String
    public var sleep: String

    public init(
        idle: String,
        happy: String,
        sad: String,
        sleep: String
    ) {
        self.idle = idle
        self.happy = happy
        self.sad = sad
        self.sleep = sleep
    }
}

public enum AgentPetAnimationState: String, Codable, Sendable, Equatable, CaseIterable {
    case idle
    case walk
    case happy
    case sad
    case interacted
    case sleep
    case avatar
}

public struct AgentPetFrameSize: Codable, Sendable, Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct AgentPetFrameRange: Codable, Sendable, Equatable {
    public var start: Int
    public var end: Int
    public var fps: Int
    public var loop: Bool

    public init(start: Int, end: Int, fps: Int, loop: Bool) {
        self.start = start
        self.end = end
        self.fps = fps
        self.loop = loop
    }
}

public struct AgentPetStageAsset: Codable, Sendable, Equatable {
    public var stage: Int
    public var spriteSheetPath: String
    public var frameSize: AgentPetFrameSize
    public var stateFrameRanges: [String: AgentPetFrameRange]

    public init(
        stage: Int,
        spriteSheetPath: String,
        frameSize: AgentPetFrameSize = AgentPetFrameSize(width: 256, height: 256),
        stateFrameRanges: [String: AgentPetFrameRange]
    ) {
        self.stage = stage
        self.spriteSheetPath = spriteSheetPath
        self.frameSize = frameSize
        self.stateFrameRanges = stateFrameRanges
    }
}

public struct AgentPetVisualSummary: Codable, Sendable, Equatable {
    public var paletteId: String?
    public var speciesId: String
    public var displayName: String
    public var source: String
    public var assetBaseURL: String
    public var currentStage: Int
    public var stageCount: Int
    public var terminalFaceSet: AgentPetTerminalFaceSet

    public init(
        speciesId: String,
        displayName: String,
        source: String,
        assetBaseURL: String,
        currentStage: Int,
        stageCount: Int,
        terminalFaceSet: AgentPetTerminalFaceSet,
        paletteId: String? = nil
    ) {
        self.paletteId = paletteId
        self.speciesId = speciesId
        self.displayName = displayName
        self.source = source
        self.assetBaseURL = assetBaseURL
        self.currentStage = currentStage
        self.stageCount = stageCount
        self.terminalFaceSet = terminalFaceSet
    }
}

public struct AgentPetEvolutionSummary: Codable, Sendable, Equatable {
    public var totalXp: Int
    public var stageXp: Int
    public var nextStageXp: Int?
    public var isMaxStage: Bool

    public init(totalXp: Int, stageXp: Int, nextStageXp: Int?, isMaxStage: Bool) {
        self.totalXp = totalXp
        self.stageXp = stageXp
        self.nextStageXp = nextStageXp
        self.isMaxStage = isMaxStage
    }
}

public struct AgentPetProgressCounters: Codable, Sendable, Equatable {
    public var directMessageCount: Int
    public var externalMessageCount: Int
    public var automatedMessageCount: Int
    public var successfulRunCount: Int
    public var failedRunCount: Int
    public var interruptedRunCount: Int
    public var toolCallCount: Int
    public var toolFailureCount: Int

    public init(
        directMessageCount: Int = 0,
        externalMessageCount: Int = 0,
        automatedMessageCount: Int = 0,
        successfulRunCount: Int = 0,
        failedRunCount: Int = 0,
        interruptedRunCount: Int = 0,
        toolCallCount: Int = 0,
        toolFailureCount: Int = 0
    ) {
        self.directMessageCount = directMessageCount
        self.externalMessageCount = externalMessageCount
        self.automatedMessageCount = automatedMessageCount
        self.successfulRunCount = successfulRunCount
        self.failedRunCount = failedRunCount
        self.interruptedRunCount = interruptedRunCount
        self.toolCallCount = toolCallCount
        self.toolFailureCount = toolFailureCount
    }
}

public struct AgentPetProgressWatermark: Codable, Sendable, Equatable {
    public var sourceKind: String?
    public var channelId: String?
    public var sessionId: String?
    public var eventKind: String?
    public var processedAt: Date?

    public init(
        sourceKind: String? = nil,
        channelId: String? = nil,
        sessionId: String? = nil,
        eventKind: String? = nil,
        processedAt: Date? = nil
    ) {
        self.sourceKind = sourceKind
        self.channelId = channelId
        self.sessionId = sessionId
        self.eventKind = eventKind
        self.processedAt = processedAt
    }
}

public struct AgentPetProgressState: Codable, Sendable, Equatable {
    public var version: Int
    public var currentStats: AgentPetStats
    public var totalXp: Int
    public var counters: AgentPetProgressCounters
    public var dailyChannelGainBuckets: [String: AgentPetStats]
    public var dailyGlobalGainBuckets: [String: AgentPetStats]
    public var processedWatermark: AgentPetProgressWatermark
    public var createdAt: Date
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case version
        case currentStats
        case totalXp
        case counters
        case dailyChannelGainBuckets
        case dailyGlobalGainBuckets
        case processedWatermark
        case createdAt
        case updatedAt
    }

    public init(
        version: Int = 1,
        currentStats: AgentPetStats,
        totalXp: Int = 0,
        counters: AgentPetProgressCounters = .init(),
        dailyChannelGainBuckets: [String: AgentPetStats] = [:],
        dailyGlobalGainBuckets: [String: AgentPetStats] = [:],
        processedWatermark: AgentPetProgressWatermark = .init(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.currentStats = currentStats
        self.totalXp = totalXp
        self.counters = counters
        self.dailyChannelGainBuckets = dailyChannelGainBuckets
        self.dailyGlobalGainBuckets = dailyGlobalGainBuckets
        self.processedWatermark = processedWatermark
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        currentStats = try container.decode(AgentPetStats.self, forKey: .currentStats)
        totalXp = try container.decodeIfPresent(Int.self, forKey: .totalXp) ?? 0
        counters = try container.decodeIfPresent(AgentPetProgressCounters.self, forKey: .counters) ?? .init()
        dailyChannelGainBuckets = try container.decodeIfPresent([String: AgentPetStats].self, forKey: .dailyChannelGainBuckets) ?? [:]
        dailyGlobalGainBuckets = try container.decodeIfPresent([String: AgentPetStats].self, forKey: .dailyGlobalGainBuckets) ?? [:]
        processedWatermark = try container.decodeIfPresent(AgentPetProgressWatermark.self, forKey: .processedWatermark) ?? .init()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

public struct AgentPetSummary: Codable, Sendable, Equatable {
    public var petId: String
    public var genomeHex: String
    public var parts: AgentPetParts
    public var partRarities: AgentPetPartRarities
    public var rarity: AgentPetRarityTier
    public var baseStats: AgentPetStats
    public var currentStats: AgentPetStats
    public var transferable: Bool
    public var visual: AgentPetVisualSummary?
    public var evolution: AgentPetEvolutionSummary?
    public var stageAssets: [AgentPetStageAsset]

    enum CodingKeys: String, CodingKey {
        case petId
        case genomeHex
        case parts
        case partRarities
        case rarity
        case baseStats
        case currentStats
        case transferable
        case visual
        case evolution
        case stageAssets
    }

    public init(
        petId: String,
        genomeHex: String,
        parts: AgentPetParts,
        partRarities: AgentPetPartRarities,
        rarity: AgentPetRarityTier,
        baseStats: AgentPetStats,
        currentStats: AgentPetStats? = nil,
        transferable: Bool = true,
        visual: AgentPetVisualSummary? = nil,
        evolution: AgentPetEvolutionSummary? = nil,
        stageAssets: [AgentPetStageAsset] = []
    ) {
        self.petId = petId
        self.genomeHex = genomeHex
        self.parts = parts
        self.partRarities = partRarities
        self.rarity = rarity
        self.baseStats = baseStats
        self.currentStats = currentStats ?? baseStats
        self.transferable = transferable
        self.visual = visual
        self.evolution = evolution
        self.stageAssets = stageAssets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        petId = try container.decode(String.self, forKey: .petId)
        genomeHex = try container.decode(String.self, forKey: .genomeHex)
        parts = try container.decode(AgentPetParts.self, forKey: .parts)
        partRarities = try container.decode(AgentPetPartRarities.self, forKey: .partRarities)
        rarity = try container.decode(AgentPetRarityTier.self, forKey: .rarity)
        baseStats = try container.decode(AgentPetStats.self, forKey: .baseStats)
        currentStats = try container.decodeIfPresent(AgentPetStats.self, forKey: .currentStats) ?? baseStats
        transferable = try container.decodeIfPresent(Bool.self, forKey: .transferable) ?? true
        visual = try container.decodeIfPresent(AgentPetVisualSummary.self, forKey: .visual)
        evolution = try container.decodeIfPresent(AgentPetEvolutionSummary.self, forKey: .evolution)
        stageAssets = try container.decodeIfPresent([AgentPetStageAsset].self, forKey: .stageAssets) ?? []
    }
}

public enum AgentPetGenerationMode: String, Codable, Sendable, Equatable {
    case wish
    case prompt
}

public struct AgentPetGenerationRequest: Codable, Sendable {
    public var mode: AgentPetGenerationMode
    public var prompt: String?
    public var model: String?

    public init(mode: AgentPetGenerationMode, prompt: String? = nil, model: String? = nil) {
        self.mode = mode
        self.prompt = prompt
        self.model = model
    }
}

public struct AgentPetGenerationResponse: Codable, Sendable, Equatable {
    public var draftId: String
    public var visual: AgentPetVisualSummary
    public var evolution: AgentPetEvolutionSummary
    public var generatedPrompt: String
    public var assetURLs: [String]
    public var stageAssets: [AgentPetStageAsset]
    public var terminalFaceSet: AgentPetTerminalFaceSet

    public init(
        draftId: String,
        visual: AgentPetVisualSummary,
        evolution: AgentPetEvolutionSummary,
        generatedPrompt: String,
        assetURLs: [String],
        stageAssets: [AgentPetStageAsset],
        terminalFaceSet: AgentPetTerminalFaceSet
    ) {
        self.draftId = draftId
        self.visual = visual
        self.evolution = evolution
        self.generatedPrompt = generatedPrompt
        self.assetURLs = assetURLs
        self.stageAssets = stageAssets
        self.terminalFaceSet = terminalFaceSet
    }
}

public struct AgentPetImageGenerationStatusResponse: Codable, Sendable, Equatable {
    public var available: Bool
    public var providers: [String]
    public var message: String

    public init(available: Bool, providers: [String], message: String) {
        self.available = available
        self.providers = providers
        self.message = message
    }
}
