import SwiftUI

struct MainLoadingView: View {
    @State private var shimmerPhase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
