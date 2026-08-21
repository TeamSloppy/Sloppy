import Foundation
import Observation
import SloppyClientCore
import SwiftUI

enum ChatComputerUseSource: String, Sendable, Equatable {
    case computer
    case browser

    var title: String {
        switch self {
        case .computer: "Mac"
        case .browser: "Browser"
        }
    }

    var symbol: String {
        switch self {
        case .computer: "macbook"
        case .browser: "globe"
        }
    }
}

enum ChatComputerUsePhase: Sendable, Equatable {
    case active
    case completed
    case failed
}

struct ChatComputerUseActivity: Identifiable, Sendable, Equatable {
    var id: String
    var source: ChatComputerUseSource
    var tool: String
    var title: String
    var phase: ChatComputerUsePhase
    var updatedAt: Date

    func finishing(failed: Bool) -> Self {
        var copy = self
        copy.phase = failed ? .failed : .completed
        copy.updatedAt = Date()
        return copy
    }
}

enum ChatComputerUseEventReducer {
    static func reduce(
        current: ChatComputerUseActivity?,
        message: ChatMessage
    ) -> ChatComputerUseActivity? {
        guard let segment = message.segments.last(where: {
            $0.kind == .toolCall || $0.kind == .toolResult
        }),
        let tool = segment.title,
        let source = source(for: tool) else {
            return current
        }

        let phase: ChatComputerUsePhase
        switch segment.kind {
        case .toolCall:
            phase = .active
        case .toolResult:
            phase = segment.status == "failed" ? .failed : .completed
        default:
            return current
        }

        return ChatComputerUseActivity(
            id: message.id,
            source: source,
            tool: tool,
            title: title(for: tool, source: source),
            phase: phase,
            updatedAt: message.createdAt
        )
    }

    private static func source(for tool: String) -> ChatComputerUseSource? {
        if tool.hasPrefix("computer.") {
            return .computer
        }
        if tool.hasPrefix("browser.") {
            return .browser
        }
        return nil
    }

    private static func title(for tool: String, source: ChatComputerUseSource) -> String {
        switch tool {
        case "computer.click": "Clicking"
        case "computer.type": "Typing"
        case "computer.key": "Pressing a key"
        case "computer.screenshot": "Inspecting the screen"
        case "browser.open": "Opening the browser"
        case "browser.navigate": "Navigating"
        case "browser.click": "Clicking a page"
        case "browser.type": "Typing in a page"
        case "browser.screenshot": "Inspecting the page"
        case "browser.status": "Checking the browser"
        case "browser.close": "Closing the browser"
        default: "Using \(source.title)"
        }
    }
}

#if os(macOS)
import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

@MainActor
@Observable
private final class ChatComputerUseCaptureModel {
    private(set) var image: NSImage?
    private(set) var errorMessage: String?
    private(set) var needsPermission = !CGPreflightScreenCaptureAccess()

    private var captureTask: Task<Void, Never>?

    func start() {
        guard captureTask == nil else { return }
        captureTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.captureFrame()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stop() {
        captureTask?.cancel()
        captureTask = nil
    }

    func requestPermission() {
        needsPermission = !CGRequestScreenCaptureAccess()
        if !needsPermission {
            errorMessage = nil
        }
    }

    private func captureFrame() async {
        guard CGPreflightScreenCaptureAccess() else {
            needsPermission = true
            return
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: {
                $0.displayID == CGMainDisplayID()
            }) ?? content.displays.first else {
                errorMessage = "No display is available."
                return
            }

            let currentProcessID = ProcessInfo.processInfo.processIdentifier
            let excludedApplications = content.applications.filter {
                $0.processID == currentProcessID
            }
            let filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )
            let configuration = SCStreamConfiguration()
            configuration.width = 960
            configuration.height = max(
                1,
                Int((Double(display.height) / Double(display.width)) * 960)
            )
            configuration.showsCursor = true

            let frame = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            image = NSImage(cgImage: frame, size: .zero)
            errorMessage = nil
            needsPermission = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
struct ChatComputerUsePictureInPictureView: View {
    let activity: ChatComputerUseActivity
    let onHide: () -> Void

    @State private var capture = ChatComputerUseCaptureModel()
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                Color.black

                if let image = capture.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else if capture.needsPermission {
                    permissionPrompt
                } else if let errorMessage = capture.errorMessage {
                    captureError(errorMessage)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }
            .frame(height: isExpanded ? 280 : 168)
            .clipped()
        }
        .frame(width: isExpanded ? 500 : 300)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .task { capture.start() }
        .onDisappear { capture.stop() }
        .accessibilityIdentifier("chat.computer-use.picture-in-picture")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: activity.source.symbol)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(activity.source.title)
                    .font(.caption.weight(.semibold))
                Text(activity.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            phaseIndicator

            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Make smaller" : "Make larger")

            Button(action: onHide) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Hide Computer Use")
        }
        .font(.caption)
        .padding(.horizontal, 11)
        .frame(height: 42)
    }

    @ViewBuilder
    private var phaseIndicator: some View {
        switch activity.phase {
        case .active:
            ProgressView()
                .controlSize(.mini)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var permissionPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.title2)
            Text("Screen Recording access is required")
                .font(.caption)
            Button("Allow") {
                capture.requestPermission()
            }
            .controlSize(.small)
        }
        .foregroundStyle(.white)
        .padding()
    }

    private func captureError(_ message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding()
    }
}
#endif
