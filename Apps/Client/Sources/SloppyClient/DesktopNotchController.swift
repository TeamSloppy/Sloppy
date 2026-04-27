@_spi(Internal) import AdaEngine
import SloppyClientCore
import SloppyClientUI

#if os(macOS)
import AppKit

@MainActor
final class DesktopNotchController {
    private enum Metrics {
        static let windowSize = Size(width: 640, height: 124)
    }

    private var primaryWindow: UIWindow?
    private var notchWindow: UIWindow?
    private var miniaturizeTask: Task<Void, Never>?
    private var deminiaturizeTask: Task<Void, Never>?

    func start(settings: ClientSettings) {
        applyCloseBehavior(settings.windowCloseBehavior)
        guard miniaturizeTask == nil, deminiaturizeTask == nil else {
            return
        }

        miniaturizeTask = Task { @MainActor in
            let notifications = NotificationCenter.default.notifications(named: .adaEngineWindowDidMiniaturize)
            for await notification in notifications {
                guard let window = notification.object as? UIWindow else { continue }
                showNotch(for: window)
            }
        }

        deminiaturizeTask = Task { @MainActor in
            let notifications = NotificationCenter.default.notifications(named: .adaEngineWindowDidDeminiaturize)
            for await notification in notifications {
                guard let window = notification.object as? UIWindow else { continue }
                if window === primaryWindow {
                    hideNotch()
                }
            }
        }
    }

    func applyCloseBehavior(_ behavior: ClientWindowCloseBehavior) {
        let engineBehavior: Application.LastWindowCloseBehavior = switch behavior {
        case .keepProcess:
            .keepApplicationRunning
        case .quitOnLastWindow:
            .terminateApplication
        }
        Application.shared?.setLastWindowCloseBehavior(engineBehavior)
    }

    private func showNotch(for window: UIWindow) {
        guard window !== notchWindow else {
            return
        }
        primaryWindow = window
        if let notchWindow {
            notchWindow.canDraw = true
            if let nsWindow = notchWindow.systemWindow as? NSWindow {
                nsWindow.setFrame(makeNotchFrame().toNSRect, display: true)
                nsWindow.orderFrontRegardless()
            } else {
                notchWindow.showWindow(makeFocused: false)
            }
            return
        }

        guard notchWindow == nil else {
            return
        }

        let frame = makeNotchFrame()
        notchWindow = Application.shared.windowManager.spawnWindow(
            configuration: UIWindow.Configuration(
                title: "Sloppy Notch",
                frame: frame,
                minimumSize: frame.size,
                chrome: .borderless,
                background: .transparent,
                level: .statusBar,
                collectionBehavior: .allSpacesStationary,
                showsImmediately: true,
                makeKey: false
            )
        ) { [weak self] in
            DesktopNotchView(windowSize: Metrics.windowSize) {
                self?.restorePrimaryWindow()
            }
            .theme(.sloppyDark)
        }
    }

    private func restorePrimaryWindow() {
        primaryWindow?.showWindow(makeFocused: true)
        hideNotch()
    }

    private func hideNotch() {
        notchWindow?.canDraw = false
        (notchWindow?.systemWindow as? NSWindow)?.orderOut(nil)
    }

    private func makeNotchFrame() -> Rect {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return Rect(
            x: Float(screenFrame.midX) - Metrics.windowSize.width / 2,
            y: Float(screenFrame.maxY) - Metrics.windowSize.height,
            width: Metrics.windowSize.width,
            height: Metrics.windowSize.height
        )
    }
}

private extension Rect {
    var toNSRect: NSRect {
        NSRect(
            x: CGFloat(origin.x),
            y: CGFloat(origin.y),
            width: CGFloat(size.width),
            height: CGFloat(size.height)
        )
    }
}

private struct DesktopNotchView: View {
    let windowSize: Size
    let onActivate: @MainActor () -> Void

    @Environment(\.theme) private var theme
    @State private var expansion: Float = 0
    @State private var expansionTask: Task<Void, Never>?

    private enum Metrics {
        static let collapsedWidth: Float = 196
        static let expandedWidth: Float = 440
        static let collapsedHeight: Float = 36
        static let expandedHeight: Float = 104
        static let collapsedRadius: Float = 18
        static let expandedRadius: Float = 34
        static let duration = 0.16
    }

    private var islandWidth: Float {
        lerp(Metrics.collapsedWidth, Metrics.expandedWidth, expansion)
    }

    private var islandHeight: Float {
        lerp(Metrics.collapsedHeight, Metrics.expandedHeight, expansion)
    }

    private var bottomRadius: Float {
        lerp(Metrics.collapsedRadius, Metrics.expandedRadius, expansion)
    }

    private var glyphSize: Float {
        lerp(18, 28, expansion)
    }

    var body: some View {
        return ZStack(anchor: .topLeading) {
            Color.clear.ignoresSafeArea()
            HStack(spacing: 0) {
                Spacer()
                island
                    .frame(width: islandWidth, height: islandHeight)
                    .onHover { isHovered in
                        animateExpansion(to: isHovered ? 1 : 0)
                    }
                Spacer()
            }
            .frame(width: windowSize.width, height: windowSize.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var island: some View {
        let c = theme.colors
        let ty = theme.typography

        return Button(action: onActivate) {
            ZStack {
                NotchIslandShape(radius: bottomRadius)
                    .fill(Color.black.opacity(0.97 as Float))
                    .frame(width: islandWidth, height: islandHeight)

                VStack(spacing: 12) {
                    Text("Sloppy minimized")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textMuted)
                    HStack(spacing: 14) {
                        ActivityGlyph()
                            .frame(width: glyphSize, height: glyphSize)
//                        Text("Restore Sloppy")
//                            .font(.system(size: 15))
//                            .foregroundColor(c.textPrimary)
                    }
                }
                .opacity(expansion)

                HStack(spacing: 10) {
                    ActivityGlyph()
                        .frame(width: 18, height: 18)
                    Text("Sloppy")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textSecondary)
                }
                .padding(.top, 8)
                .opacity(1 - expansion)
            }
        }
    }

    private func animateExpansion(to target: Float) {
        expansionTask?.cancel()

        let start = expansion
        guard start != target else {
            return
        }

        expansionTask = Task { @MainActor in
            let frameDuration: UInt64 = 16_000_000
            let frameSeconds = 0.016
            var elapsed = 0.0

            while elapsed < Metrics.duration && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: frameDuration)
                elapsed += frameSeconds

                let t = min(Float(elapsed / Metrics.duration), 1)
                expansion = lerp(start, target, easeOutCubic(t))
            }

            if !Task.isCancelled {
                expansion = target
                expansionTask = nil
            }
        }
    }

    private func lerp(_ start: Float, _ end: Float, _ progress: Float) -> Float {
        start + (end - start) * progress
    }

    private func easeOutCubic(_ value: Float) -> Float {
        let inverse = 1 - value
        return 1 - inverse * inverse * inverse
    }
}

private struct NotchIslandShape: Shape {
    let radius: Float

    func path(in rect: Rect) -> Path {
        let r = min(radius, min(rect.width, rect.height) * 0.5)
        let k: Float = r * 0.5522847498
        return Path { path in
            path.move(to: Vector2(rect.minX, rect.minY))
            path.addLine(to: Vector2(rect.maxX, rect.minY))
            path.addLine(to: Vector2(rect.maxX, rect.maxY - r))
            path.addCurve(
                to: Point(rect.maxX - r, rect.maxY),
                control1: Point(rect.maxX, rect.maxY - r + k),
                control2: Point(rect.maxX - r + k, rect.maxY)
            )
            path.addLine(to: Vector2(rect.minX + r, rect.maxY))
            path.addCurve(
                to: Point(rect.minX, rect.maxY - r),
                control1: Point(rect.minX + r - k, rect.maxY),
                control2: Point(rect.minX, rect.maxY - r + k)
            )
            path.addLine(to: Vector2(rect.minX, rect.minY))
            path.closeSubpath()
        }
    }
}

private struct ActivityGlyph: View {
    var body: some View {
        ZStack {
            CircleShape()
                .fill(Color.fromHex(0xFF4D6D).opacity(0.18 as Float))
            RectangleShape()
                .fill(Color.fromHex(0xFF6B7F))
                .frame(width: 14, height: 14)
            RectangleShape()
                .fill(Color.fromHex(0xFFA1AA).opacity(0.75 as Float))
                .frame(width: 7, height: 7)
                .offset(x: -4, y: -4)
        }
    }
}
#endif
