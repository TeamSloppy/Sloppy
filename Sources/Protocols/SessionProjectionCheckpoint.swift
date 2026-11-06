import Foundation

/// References canonical journal entries; outputs and images are not duplicated into the checkpoint.
public struct SessionProjectionCheckpoint: Codable, Sendable, Equatable {
    public var projectionVersion: Int
    public var coveredCursor: UInt64
    public var coveredThroughEventId: String
    public var summary: String
    public var retainedEventIds: [String]
    public var artifactRefs: [String]

    public init(projectionVersion: Int = 1, coveredCursor: UInt64, coveredThroughEventId: String,
                summary: String, retainedEventIds: [String], artifactRefs: [String] = []) {
        self.projectionVersion = projectionVersion
        self.coveredCursor = coveredCursor
        self.coveredThroughEventId = coveredThroughEventId
        self.summary = summary
        self.retainedEventIds = retainedEventIds
        self.artifactRefs = artifactRefs
    }
}
