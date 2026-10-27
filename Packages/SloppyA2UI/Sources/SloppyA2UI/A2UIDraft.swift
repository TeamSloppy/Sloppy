import Foundation

public struct A2UIDraft: Codable, Sendable, Equatable {
    public var values: [String: A2UIValue]
    public var defaults: [String: A2UIValue]
    public var revision: Int
    public var pending: A2UISubmission?
    public init(surface: A2UISurfaceSnapshot) {
        values = surface.initialValues
        defaults = values
        revision = surface.revision
    }
    public mutating func reconcile(_ surface: A2UISurfaceSnapshot) {
        let next = surface.initialValues
        if surface.submittedActionId != nil {
            values = next
            pending = nil
        } else {
            values = next.mapValues { $0 }.merging(values.filter { next[$0.key] != nil && $0.value != defaults[$0.key] }) { _, edited in
                edited
            }
            if revision != surface.revision { pending = nil }
        }
        defaults = next
        revision = surface.revision
    }
    public mutating func submission(for button: String, surface: A2UISurfaceSnapshot) -> A2UISubmission {
        if let pending { return pending }
        let request = A2UISubmission(
            actionId: UUID().uuidString, revision: revision, componentId: button, values: surface.normalizedValues(values))
        pending = request
        return request
    }
}
