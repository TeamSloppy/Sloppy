import Foundation
import Logging
import Protocols

@main
enum AppMain {
    static func main() {
        LoggingSystem.bootstrap(ColoredLogHandler.standardError)
        let logger = Logger(label: "sloppy.app.main")
        logger.info("App target placeholder. AdaUI client will mirror Dashboard capabilities.")
    }
}
