import Foundation

public protocol ComputerControlling: Sendable {
    func click(_ payload: ComputerClickPayload) async throws -> ComputerControlValue
    func typeText(_ payload: ComputerTypeTextPayload) async throws -> ComputerControlValue
    func key(_ payload: ComputerKeyPayload) async throws -> ComputerControlValue
    func screenshot(_ payload: ComputerScreenshotPayload) async throws -> ComputerScreenshotResult
}

public enum ComputerControlError: Error, LocalizedError, Sendable, Equatable {
    case invalidArguments(String)
    case unsupportedPlatform(String)
    case permissionDenied(String)
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArguments(let message),
             .unsupportedPlatform(let message),
             .permissionDenied(let message),
             .operationFailed(let message):
            return message
        }
    }

    public var code: String {
        switch self {
        case .invalidArguments:
            return "invalid_arguments"
        case .unsupportedPlatform:
            return "unsupported_platform"
        case .permissionDenied:
            return "permission_denied"
        case .operationFailed:
            return "operation_failed"
        }
    }
}

public func validateClickPayload(_ payload: ComputerClickPayload) throws {
    guard payload.x.isFinite, payload.y.isFinite, payload.x >= 0, payload.y >= 0 else {
        throw ComputerControlError.invalidArguments("`x` and `y` must be non-negative finite coordinates.")
    }
    if let width = payload.width, (!width.isFinite || width <= 0) {
        throw ComputerControlError.invalidArguments("`width` must be positive when provided.")
    }
    if let height = payload.height, (!height.isFinite || height <= 0) {
        throw ComputerControlError.invalidArguments("`height` must be positive when provided.")
    }
}

public var computerControlPlatformName: String {
    #if os(macOS)
    return "macOS"
    #elseif os(Windows)
    return "Windows"
    #elseif os(Linux)
    return "Linux"
    #else
    return "unknown"
    #endif
}

func defaultScreenshotPath(extension fileExtension: String) -> String {
    let filename = "sloppy-node-screenshot-\(UUID().uuidString).\(fileExtension)"
    return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename).path
}
