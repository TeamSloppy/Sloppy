import Foundation
@testable import sloppy

extension CoreConfig {
    static var test: CoreConfig {
        var config = CoreConfig.default
        let id = UUID().uuidString
        config.workspace = .init(
            name: "workspace-test-\(id)",
            basePath: FileManager.default.temporaryDirectory.path
        )
        config.sqlitePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("core-test-\(id).sqlite")
            .path
        return config
    }
}
