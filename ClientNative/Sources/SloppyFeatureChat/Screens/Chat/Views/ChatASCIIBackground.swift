#if os(macOS)
import SwiftUI
import SloppyClientUI

/// A quiet, bounded character field behind the empty desktop conversation.
struct ChatASCIIBackground: View {
    let protectedWidth: CGFloat

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    var body: some View {
        Group {
            if !reduceMotion, scenePhase == .active {
                TimelineView(.animation(minimumInterval: 1.0 / 12)) { timeline in
                    artwork(time: timeline.date.timeIntervalSince(startedAt))
                }
            } else {
                artwork(time: 0)
            }
        }
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .white, location: 0.12),
                .init(color: .white, location: 0.88),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        }
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .white, location: 0.1),
                .init(color: .white, location: 0.85),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func artwork(time: TimeInterval) -> some View {
        let ink = theme.colors.textMuted.opacity(colorScheme == .dark ? 0.42 : 0.24)
        return Canvas(rendersAsynchronously: true) { context, size in
            guard size.width > 0, size.height > 0 else { return }
            let columns = min(320, max(1, Int(ceil(size.width / 10))))
            let rows = min(90, max(1, Int(size.height / 15)))
            let characters: [Character] = [" ", ".", ":", "-", "=", "+", "*"]
            let width = Double(size.width)
            let height = Double(size.height)
            let cellWidth = width / Double(columns)
            let quietWidth = Double(min(protectedWidth, size.width) * 0.65 + 60)
            let quietHeight = min(230.0, height * 0.34)

            for row in 0..<rows {
                let y = (Double(row) + 0.5) * height / Double(rows)
                var line = String()
                line.reserveCapacity(columns)
                for column in 0..<columns {
                    let x = (Double(column) + 0.5) * cellWidth
                    let u = x / 100
                    let v = y / 100
                    let wave = sin(u * 0.62 + sin(v * 0.48 + time * 0.16) * 1.6 - time * 0.2)
                        + cos(v * 0.58 - u * 0.25 + time * 0.12) * 0.7
                    let contour = pow(0.5 + 0.5 * cos(wave * 4.2), 2)
                    let distance = hypot((x - width / 2) / quietWidth, (y - height * 0.43) / quietHeight)
                    let quiet = min(1, max(0, (distance - 0.65) / 0.8))
                    let density = contour * quiet * quiet
                    let index = min(characters.count - 1, Int(density * Double(characters.count)))
                    line.append(characters[index])
                }
                let text = Text(line)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(cellWidth - 6.6)
                    .foregroundStyle(ink)
                context.draw(text, at: CGPoint(x: size.width / 2, y: y))
            }
        }
    }
}
#endif
