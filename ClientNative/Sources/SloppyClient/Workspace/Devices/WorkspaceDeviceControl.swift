#if os(macOS)
import Foundation
import SloppyClientCore

@MainActor
enum WorkspaceDeviceInventory {
    typealias Device = WorkspaceDevicePreview.Device

    static func list(_ platform: DevicePlatform, adbExecutable: URL?) async throws -> [Device] {
        let command = LocalDeviceBridge()
        defer { command.stop() }
        switch platform {
        case .iOS:
            struct SimulatorList: Decodable {
                struct Simulator: Decodable {
                    let udid: String
                    let name: String
                    let isAvailable: Bool
                }
                let devices: [String: [Simulator]]
            }
            let output = try await command.run(URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["simctl", "list", "devices", "available", "-j"], timeout: .seconds(8))
            let list = try JSONDecoder().decode(SimulatorList.self, from: Data(output.utf8))
            return list.devices.sorted { $0.key < $1.key }.flatMap { runtime, devices in
                let parts = runtime.components(separatedBy: ".").last?.split(separator: "-") ?? []
                let version = parts.first.map { "\($0) \(parts.dropFirst().joined(separator: "."))" } ?? runtime
                return devices.filter(\.isAvailable).map { Device(id: $0.udid, name: "\($0.name) (\(version))") }
            }
        case .android:
            let adb = try adbExecutable ?? LocalDeviceBridge.adbExecutable()
            let output = try await command.run(adb, arguments: ["devices", "-l"], timeout: .seconds(8))
            let connected: [Device] = output.split(whereSeparator: \.isNewline).compactMap { line in
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count >= 2, fields[1] == "device" else { return nil }
                let serial = String(fields[0])
                let model = fields.dropFirst(2).first { $0.hasPrefix("model:") }?.dropFirst("model:".count)
                return .init(id: serial, name: model.map { $0.replacingOccurrences(of: "_", with: " ") } ?? serial)
            }
            guard let emulator = LocalDeviceBridge.androidEmulatorExecutable() else { return connected }
            let avds = try await command.run(emulator, arguments: ["-list-avds"], timeout: .seconds(8))
            // A running AVD may be listed by name as well as by serial. Use the AVD name
            // in the connected label when known and omit that duplicate from configured targets.
            var runningAVDs: Set<String> = []
            var devices = connected
            let lookupDeadline = ContinuousClock.now + .seconds(3)
            for index in devices.indices where devices[index].id.hasPrefix("emulator-") {
                let remaining = ContinuousClock.now.duration(to: lookupDeadline)
                guard remaining > .zero else { break }
                if let name = try await avdName(serial: devices[index].id, adb: adb, timeout: min(remaining, .seconds(1))) {
                    devices[index].name = name
                    runningAVDs.insert(name.lowercased())
                }
            }
            devices += avds.split(whereSeparator: \.isNewline).compactMap { line in
                let name = String(line).trimmingCharacters(in: .whitespaces)
                guard WorkspaceDeviceSession.validDeviceID(name), !name.hasPrefix("INFO"),
                      !runningAVDs.contains(name.lowercased()), !connected.contains(where: { $0.id == name }) else { return nil }
                return .init(id: name, name: name)
            }
            return devices
        }
    }

    static func avdName(serial: String, adb: URL, timeout: Duration = .seconds(3)) async throws -> String? {
        guard serial.hasPrefix("emulator-"), WorkspaceDeviceSession.validDeviceID(serial) else { return nil }
        let command = LocalDeviceBridge()
        defer { command.stop() }
        do {
            let output = try await command.run(adb, arguments: ["-s", serial, "emu", "avd", "name"], timeout: timeout)
            let lines = output.split(whereSeparator: \.isNewline)
            guard lines.count == 2, lines[1] == "OK" else { return nil }
            return String(lines[0])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }
}

enum WorkspaceDeviceInput: Sendable {
    struct Point: Sendable {
        let x: Double
        let y: Double

        init(_ x: Double?, _ y: Double?) throws {
            guard let x, let y, (0...1).contains(x), (0...1).contains(y) else {
                throw LocalDeviceBridge.failure("Use normalized device coordinates between 0 and 1.")
            }
            self.x = x
            self.y = y
        }
    }

    case tap(Point)
    case swipe(Point, Point, Int)
    case text(String)

    init(_ input: WorkspaceBrowserCommand.Input) throws {
        switch input.operation {
        case "tap":
            self = .tap(try Point(input.x, input.y))
        case "swipe":
            let duration = input.durationMs ?? 300
            guard (50...3000).contains(duration) else {
                throw LocalDeviceBridge.failure("Swipe duration must be between 50 and 3000 milliseconds.")
            }
            self = .swipe(try Point(input.x, input.y), try Point(input.endX, input.endY), duration)
        case "type":
            guard let text = input.text, (1...512).contains(text.utf8.count),
                  text.utf8.allSatisfy({ (32...126).contains($0) || $0 == 9 || $0 == 10 }) else {
                throw LocalDeviceBridge.failure("Use 1–512 ASCII characters for device keyboard input.")
            }
            self = .text(text)
        default:
            throw LocalDeviceBridge.failure("Unknown device input.")
        }
    }

    func sendToAndroid(at url: URL) async throws {
        struct Response: Decodable { let ok: Bool; let message: String? }
        let body: [String: Any] = switch self {
        case .tap(let point):
            ["action": "tap", "x": point.x, "y": point.y]
        case .swipe(let start, let end, let duration):
            ["action": "swipe", "x1": start.x, "y1": start.y, "x2": end.x, "y2": end.y, "durationMs": duration]
        case .text(let text):
            ["action": "text", "text": text]
        }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request, delegate: DeviceBridgeNoRedirect())
        let result = try? JSONDecoder().decode(Response.self, from: data)
        guard (response as? HTTPURLResponse)?.statusCode == 200, result?.ok == true else {
            throw LocalDeviceBridge.failure(result?.message ?? "The Android bridge could not deliver the input.")
        }
    }

    func sendIOSGesture(to url: URL) async throws {
        let client = URLSession(configuration: .ephemeral, delegate: DeviceBridgeNoRedirect(), delegateQueue: nil)
        let socket = client.webSocketTask(with: URLRequest(url: url, timeoutInterval: 8))
        socket.resume()
        defer { client.invalidateAndCancel() }
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    switch self {
                    case .tap(let point):
                        try await Self.touch("begin", x: point.x, y: point.y, socket: socket)
                        try await Task.sleep(for: .milliseconds(40))
                        try await Self.touch("end", x: point.x, y: point.y, socket: socket)
                    case .swipe(let start, let end, let duration):
                        let steps = max(2, duration / 16)
                        try await Self.touch("begin", x: start.x, y: start.y, socket: socket)
                        for step in 1...steps {
                            try await Task.sleep(for: .milliseconds(duration / steps))
                            let progress = Double(step) / Double(steps)
                            try await Self.touch(step == steps ? "end" : "move",
                                x: start.x + (end.x - start.x) * progress,
                                y: start.y + (end.y - start.y) * progress, socket: socket)
                        }
                    case .text:
                        throw LocalDeviceBridge.failure("Use the simulator keyboard for text input.")
                    }
                    // Like the bridge CLI, give the final touch frame time to flush before closing.
                    try await Task.sleep(for: .milliseconds(50))
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(10))
                    socket.cancel(with: .goingAway, reason: nil)
                    throw LocalDeviceBridge.failure("The simulator input bridge did not respond in time.")
                }
                defer { group.cancelAll() }
                try await group.next()
            }
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
        }
    }

    private static func touch(_ type: String, x: Double, y: Double, socket: URLSessionWebSocketTask) async throws {
        let event = try JSONSerialization.data(withJSONObject: ["type": type, "x": x, "y": y])
        try await socket.send(.data(Data([3]) + event))
    }
}

final class DeviceBridgeNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}
#endif
