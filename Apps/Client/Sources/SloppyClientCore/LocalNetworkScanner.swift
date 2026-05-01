import Foundation

/// Discovers Sloppy servers on the LAN. On Apple platforms this scans the local /24 subnet;
/// on other hosts (e.g. Windows/Linux IDEs) scanning is a no-op.
public actor LocalNetworkScanner {
    public static let sloppyPort: UInt16 = 25101

    public init() {}

    public func scan() -> AsyncStream<SavedServer> {
        #if os(macOS) || os(iOS) || os(visionOS)
        LocalNetworkScannerApple.makeScanStream(port: Self.sloppyPort)
        #else
        AsyncStream { continuation in
            continuation.finish()
        }
        #endif
    }
}
