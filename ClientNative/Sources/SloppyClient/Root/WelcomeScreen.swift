import SwiftUI
import SloppyClientCore
#if os(iOS)
import UIKit
#endif

/// A short, interruptible greeting; the choices remain available during the animation.
struct WelcomeScreen: View {
    let onChoose: (ClientLaunchMode) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var logoSize = 76.0
    @State private var revealed = false
    @State private var settled = false

    private let paper = Color(red: 245 / 255, green: 242 / 255, blue: 233 / 255)
    private let forest = Color(red: 32 / 255, green: 38 / 255, blue: 30 / 255)
    private let mint = Color(red: 200 / 255, green: 226 / 255, blue: 174 / 255)

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 32)
                    wordmark
                        .padding(.bottom, 36)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Hello, welcome in.")
                            .font(.largeTitle.weight(.semibold))
                            .tracking(-1)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("A place to explore the web.\nA little help when you need it.")
                            .font(.title3)
                            .foregroundStyle(paper.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(revealed ? Double(1) : Double(0))
                    .offset(y: revealed || reduceMotion ? 0 : 14)

                    Spacer(minLength: 48)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Make yourself at home")
                            .font(.headline)
                            .padding(.bottom, 18)
                        choice("Connect to Sloppy", subtitle: "Bring your agents and workspace along.",
                               icon: "point.3.connected.trianglepath.dotted", mode: .instance)
                        Rectangle().fill(paper.opacity(0.2)).frame(height: 1)
                        choice("Use as a browser", subtitle: "Start exploring. Connect an instance later.",
                               icon: "globe", mode: .browser)
                    }
                    .opacity(settled ? Double(1) : Double(0.45))
                    .padding(.bottom, 32)
                }
                .frame(maxWidth: 540, minHeight: max(0, geometry.size.height - 64), alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(paper)
        .background(forest.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("welcome-screen")
        .task { await greet() }
    }

    private var wordmark: some View {
        Text("\(Text("sloppy").foregroundColor(paper))\(Text(".").foregroundColor(mint))")
            .font(SwiftUI.Font.system(size: min(logoSize, 112), weight: .heavy))
            .tracking(-min(logoSize, 112) * 1.2 / 29)
            .minimumScaleFactor(0.65)
            .lineLimit(1)
            .scaleEffect(revealed || reduceMotion ? 1 : 0.9, anchor: .leading)
            .opacity(revealed ? Double(1) : Double(0))
            .accessibilityLabel("Sloppy")
    }

    private func choice(_ title: String, subtitle: String, icon: String, mode: ClientLaunchMode) -> some View {
        Button {
            selectionHaptic()
            onChoose(mode)
        } label: {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: icon).font(.title2).frame(width: 30).foregroundStyle(mint)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundStyle(paper.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").foregroundStyle(mint)
            }
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("welcome-\(mode.rawValue)")
    }

    @MainActor
    private func greet() async {
        guard !revealed else { return }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.9, bounce: 0.12)) { revealed = true }
        do { try await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 450)) } catch { return }
        guard !Task.isCancelled else { return }
        selectionHaptic()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { settled = true }
    }

    @MainActor
    private func selectionHaptic() {
#if os(iOS)
        guard !reduceMotion else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
#endif
    }
}
