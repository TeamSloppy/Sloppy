import Logging

enum ClientLogging {
    private static let bootstrapOnce: Void = {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            #if DEBUG
            handler.logLevel = .debug
            #else
            handler.logLevel = .info
            #endif
            return handler
        }
    }()

    static func bootstrap() {
        _ = bootstrapOnce
    }
}
