import SwiftUI
import SloppyClientUI

struct MainLoadingView: View {
    var status = "Opening Sloppy…"
    @State private var shimmerPhase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    var body: some View {
#if os(macOS)
        VStack(spacing: 20) {
            Text("sloppy.")
                .font(.system(size: 40, weight: .heavy))
                .tracking(-1.65)
                .foregroundStyle(theme.colors.textPrimary)
            VStack(spacing: 12) {
                if !reduceMotion {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.colors.textMuted)
                }
                Text(status)
                    .font(.callout)
                    .foregroundStyle(theme.colors.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading Sloppy")
        .accessibilityValue(status)
        .accessibilityIdentifier("app.startup-loading")
#else
        mobileLoading
#endif
    }

    private var mobileLoading: some View {
        ZStack {
            projectLogo
                .resizable()
                .aspectRatio(contentMode: .fit)
                .opacity(0.42)

            projectLogo
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.16),
                            .white,
                            .white.opacity(0.16),
                            .clear,
                        ],
                        startPoint: UnitPoint(x: shimmerPhase - 1, y: 0.5),
                        endPoint: UnitPoint(x: shimmerPhase, y: 0.5)
                    )
                )
        }
        .frame(width: 88, height: 88)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading Sloppy")
        .onAppear {
            guard !reduceMotion else {
                shimmerPhase = 0.5
                return
            }
            withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                shimmerPhase = 2
            }
        }
    }

    private var projectLogo: Image {
        #if SWIFT_PACKAGE
        Image("SloppyProjectLogo", bundle: .module)
        #else
        Image("SloppyProjectLogo")
        #endif
    }
}

#Preview {
    MainLoadingView()
        .frame(width: 640, height: 420)
        .background(Color.black)
}
