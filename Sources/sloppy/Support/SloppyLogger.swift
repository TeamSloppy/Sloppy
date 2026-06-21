import Foundation
import Logging

extension Logger {
    public static func sloppy(label: String) -> Logger {
        var logger = Logger(label: label)
        if ProcessInfo.processInfo.environment["SLOPPY_QUIET_LOGS"] == "1" {
            logger.logLevel = .critical
        }
        return logger
    }
}
