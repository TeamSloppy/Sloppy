import Foundation

/// The temporary directory is an implicitly allowed tool root (`defaultTemporaryToolRoots`), so a
/// directory that must be rejected as "outside every allowed root" cannot live there.
/// The user's home directory is outside all implicit roots on every supported platform.
func outsideImplicitRootsURL(_ name: String = "sloppy-outside") -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".\(name)-\(UUID().uuidString)", isDirectory: true)
}
