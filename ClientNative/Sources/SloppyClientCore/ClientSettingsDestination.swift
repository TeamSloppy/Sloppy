public enum ClientSettingsDestination: String, Sendable, Equatable, Identifiable {
    case account
    case general
    case providers

    public var id: String { rawValue }
}
