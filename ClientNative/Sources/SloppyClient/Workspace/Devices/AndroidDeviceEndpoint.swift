#if os(macOS)
import Foundation

/// An ADB device endpoint, distinct from the HTTP URL of a preview bridge.
struct AndroidDeviceEndpoint: Equatable {
    let address: String

    init(_ text: String) throws {
        let address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty,
              address.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !address.contains(where: { "/\\?#@%".contains($0) }),
              let components = URLComponents(string: "adb://" + address),
              let host = components.host, !host.isEmpty, !host.hasPrefix("-"),
              host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-:[]".contains($0)) }),
              components.user == nil, components.password == nil,
              let port = components.port, (1...65535).contains(port),
              let portText = address.split(separator: ":").last,
              !portText.isEmpty, portText.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw LocalDeviceBridge.failure("Enter the Android device's ADB address as host:port, such as 192.168.3.172:55555. A bridge URL goes in Existing local bridge.")
        }
        self.address = address
    }
}
#endif
