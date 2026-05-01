import Foundation
import Logging

public struct ColoredLogHandler: LogHandler, @unchecked Sendable {
    private static let isColorEnabled: Bool = {
        if let term = ProcessInfo.processInfo.environment["TERM"], !term.isEmpty, term != "dumb" {
            return true
        }
        return ProcessInfo.processInfo.environment["COLORTERM"] != nil
            || ProcessInfo.processInfo.environment["FORCE_COLOR"] != nil
    }()

    private let label: String
    public var logLevel: Logger.Level = .info
    public var metadata: Logger.Metadata = [:]

    public init(label: String) {
        self.label = label
    }

    public static func standardError(label: String) -> ColoredLogHandler {
        ColoredLogHandler(label: label)
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(event: LogEvent) {
        let ts = Self.timestampFormatter.string(from: Date())
        let levelTag = Self.tag(for: event.level)
        let metaString = formatMetadata(event.metadata)

        let output: String
        if Self.isColorEnabled {
            let (color, reset) = Self.ansiCodes(for: event.level)
            output = "\(Self.dim)\(ts)\(Self.resetAll) \(color)\(levelTag)\(reset) [\(label)] \(event.message)\(metaString)\n"
        } else {
            output = "\(ts) \(levelTag) [\(label)] \(event.message)\(metaString)\n"
        }

        FileHandle.standardError.write(Data(output.utf8))
    }

    private func formatMetadata(_ callMetadata: Logger.Metadata?) -> String {
        var merged = metadata
        if let callMetadata {
            for (key, value) in callMetadata {
                merged[key] = value
            }
        }
        guard !merged.isEmpty else { return "" }
        let pairs = merged
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        return " {\(pairs)}"
    }

    private static let dim = "\u{1B}[2m"
    private static let resetAll = "\u{1B}[0m"

    private static func ansiCodes(for level: Logger.Level) -> (color: String, reset: String) {
        let code: String
        switch level {
        case .trace:    code = "\u{1B}[37m"
        case .debug:    code = "\u{1B}[36m"
        case .info:     code = "\u{1B}[32m"
        case .notice:   code = "\u{1B}[34m"
        case .warning:  code = "\u{1B}[33m"
        case .error:    code = "\u{1B}[31m"
        case .critical: code = "\u{1B}[1;31m"
        }
        return (code, resetAll)
    }

    private static func tag(for level: Logger.Level) -> String {
        switch level {
        case .trace:    return "TRACE"
        case .debug:    return "DEBUG"
        case .info:     return "INFO "
        case .notice:   return "NOTE "
        case .warning:  return "WARN "
        case .error:    return "ERROR"
        case .critical: return "CRIT "
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
