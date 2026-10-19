public enum ClientSettingsDestination: String, Sendable, Equatable, Identifiable {
    case account
    case general
    case providers
    case migrations
    case usage

    public var id: String { rawValue }
}
