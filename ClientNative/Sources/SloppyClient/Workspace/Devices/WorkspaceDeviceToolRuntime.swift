import Foundation
import SloppyClientCore

/// One owned preview per conversation. Commands never drive the Mac's desktop.
@MainActor
final class WorkspaceDeviceToolRuntime {
#if os(macOS)
    let session: WorkspaceDeviceSession
    private let id = UUID().uuidString
    private let present: @MainActor (WorkspaceDeviceSession) throws -> Void
    private var requestedTarget: [String?]?

    init(session: WorkspaceDeviceSession? = nil, present: @escaping @MainActor (WorkspaceDeviceSession) throws -> Void) {
        self.session = session ?? WorkspaceDeviceSession()
        self.present = present
    }
#endif

    func stop() {
#if os(macOS)
        session.stop()
#endif
    }

    func execute(_ command: WorkspaceBrowserCommand, binding: WorkspaceBrowserBinding) async -> WorkspaceBrowserCompletion {
#if os(macOS)
        do {
            let input = command.input
            var image: String?
            var sources: [DeviceFrameSource] = []
            switch input.operation {
            case "start":
                guard let raw = input.platform, let platform = DevicePlatform(rawValue: raw),
                      input.androidAddress == nil || (platform == .android && input.deviceId == nil),
                      input.deviceId.map(WorkspaceDeviceSession.validDeviceID) ?? true else {
                    throw LocalDeviceBridge.failure("Choose platform iOS or Android and an optional deviceId, or an Android ADB address.")
                }
                if let address = input.androidAddress { _ = try AndroidDeviceEndpoint(address) }
                try present(session)
                let target = [raw, input.deviceId, input.androidAddress]
                if requestedTarget != target || (!session.isStarting && session.baseURL == nil) {
                    session.platform = platform
                    if let address = input.androidAddress { session.connectAndroid(address) }
                    else if let deviceID = input.deviceId { try session.start(deviceID: deviceID) }
                    else { session.start() }
                    requestedTarget = target
                }
            case "status": break
            case "screenshot":
                sources = try await session.captureSources()
                let source = input.deviceId.flatMap { id in sources.first { $0.id == id } }
                    ?? (input.deviceId == nil && sources.count == 1 ? sources.first : nil)
                guard let source else { throw LocalDeviceBridge.failure("Use a deviceId returned by status to select a streaming device.") }
                image = try await session.capture(source).data.base64EncodedString()
            case "stop": session.stop()
            default: throw LocalDeviceBridge.failure("Use start, status, screenshot or stop.")
            }
            if sources.isEmpty, session.isLoaded { sources = try await session.captureSources() }
            let state: WorkspaceDevicePreview.State = session.isLoaded ? .ready : session.isStarting ? .starting
                : session.errorMessage != nil ? .failed : session.baseURL != nil ? .starting : .stopped
            var page = WorkspaceBrowserPage(pageId: id, url: session.baseURL?.absoluteString ?? "",
                title: "\(session.platform.rawValue) Devices", visibleText: session.startupMessage,
                running: state == .starting || state == .ready)
            page.devicePreview = WorkspaceDevicePreview(state: state, platform: session.platform.rawValue,
                devices: sources.map { .init(id: $0.id, name: $0.name) }, error: session.errorMessage)
            return .init(binding: binding, commandId: command.id, data: page, imageBase64: image)
        } catch {
            return .init(binding: binding, commandId: command.id, error: error.localizedDescription)
        }
#else
        return .init(binding: binding, commandId: command.id, error: "Device previews require the macOS client.")
#endif
    }
}
