import Foundation
import SloppyClientCore

/// One owned preview per conversation. Commands never drive the Mac's desktop.
@MainActor
final class WorkspaceDeviceToolRuntime {
#if os(macOS)
    let session: WorkspaceDeviceSession
    private let id = UUID().uuidString
    private let present: @MainActor (WorkspaceDeviceSession) throws -> Void
    private struct Target: Equatable {
        let platform: DevicePlatform
        let deviceID: String?
        let androidAddress: String?
    }
    private var requestedTarget: Target?
    private var attachDeadline: ContinuousClock.Instant?

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
            var active: DeviceFrameSource?
            if input.operation == "list" {
                guard let raw = input.platform, let platform = DevicePlatform(rawValue: raw) else {
                    throw LocalDeviceBridge.failure("Choose platform iOS or Android.")
                }
                let devices = try await session.inventory(platform)
                return result(command, binding: binding, platform: platform, state: .stopped, devices: devices)
            }
            switch input.operation {
            case "start":
                guard let raw = input.platform, let platform = DevicePlatform(rawValue: raw),
                      input.androidAddress == nil || (platform == .android && input.deviceId == nil),
                      input.deviceId.map(WorkspaceDeviceSession.validDeviceID) ?? true else {
                    throw LocalDeviceBridge.failure("Choose platform iOS or Android and an optional deviceId, or an Android ADB address.")
                }
                let address = try input.androidAddress.map { try AndroidDeviceEndpoint($0).address }
                let target = Target(platform: platform, deviceID: input.deviceId, androidAddress: address)
                if requestedTarget != target || session.controlError != nil || (!session.isStarting && session.baseURL == nil) {
                    try present(session)
                    session.platform = platform
                    if let address { session.connectAndroid(address) }
                    else if let deviceID = input.deviceId { try session.start(deviceID: deviceID) }
                    else { session.start() }
                    requestedTarget = target
                    attachDeadline = nil
                }
            case "stop": session.stop()
            case "status", "screenshot", "tap", "swipe", "type":
                (active, sources) = try await refreshTarget()
                if input.operation != "status" {
                    guard let active, session.controlError == nil else {
                        throw LocalDeviceBridge.failure(session.controlError ?? "Wait for Devices status to report a ready target.")
                    }
                    if let deviceID = input.deviceId, deviceID != active.id {
                        throw LocalDeviceBridge.failure("Use the active targetId returned by Devices status.")
                    }
                    if input.operation == "screenshot" {
                        image = try await session.capture(active).data.base64EncodedString()
                    } else {
                        guard input.deviceId == active.id else {
                            throw LocalDeviceBridge.failure("Pass the active targetId before sending device input.")
                        }
                        try await session.perform(WorkspaceDeviceInput(input), target: active)
                    }
                }
            default: throw LocalDeviceBridge.failure("Choose a supported Devices operation.")
            }
            let state: WorkspaceDevicePreview.State
            if session.controlError != nil { state = .failed }
            else if active != nil || session.targetID != nil { state = .ready }
            else if session.isStarting || session.baseURL != nil { state = .starting }
            else { state = .stopped }
            return result(command, binding: binding, platform: session.platform, state: state,
                devices: sources.map { .init(id: $0.id, name: $0.name) }, targetID: session.targetID,
                error: session.controlError, image: image)
        } catch {
            return .init(binding: binding, commandId: command.id, error: error.localizedDescription)
        }
#else
        return .init(binding: binding, commandId: command.id, error: "Device previews require the macOS client.")
#endif
    }

#if os(macOS)
    private func refreshTarget() async throws -> (DeviceFrameSource?, [DeviceFrameSource]) {
        guard session.baseURL != nil, session.controlError == nil else { return (nil, []) }
        let deadline = attachDeadline ?? .now + .seconds(30)
        attachDeadline = deadline
        do {
            let sources = try await session.captureSources()
            let target = try await session.resolveTarget(in: sources,
                requestedID: requestedTarget?.androidAddress ?? requestedTarget?.deviceID)
            if target == nil, ContinuousClock.now >= deadline {
                _ = session.failControl("The selected device did not start streaming. Start it again in Devices.")
            }
            return (target, sources)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if session.controlError == nil, session.targetID != nil || ContinuousClock.now >= deadline {
                _ = session.failControl("Could not reach the selected device. Start it again in Devices. \(error.localizedDescription)")
            }
            return (nil, [])
        }
    }

    private func result(_ command: WorkspaceBrowserCommand, binding: WorkspaceBrowserBinding, platform: DevicePlatform,
                        state: WorkspaceDevicePreview.State, devices: [WorkspaceDevicePreview.Device],
                        targetID: String? = nil, error: String? = nil, image: String? = nil) -> WorkspaceBrowserCompletion {
        let running = state == .starting || state == .ready
        var page = WorkspaceBrowserPage(pageId: id, url: running ? session.baseURL?.absoluteString ?? "" : "",
            title: "\(platform.rawValue) Devices", visibleText: running ? session.startupMessage : "", running: running)
        page.devicePreview = .init(state: state, platform: platform.rawValue, devices: devices, error: error, targetId: targetID)
        return .init(binding: binding, commandId: command.id, data: page, imageBase64: image)
    }
#endif
}
