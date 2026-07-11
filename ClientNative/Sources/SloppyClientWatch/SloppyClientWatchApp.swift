import SwiftUI

@main
struct SloppyClientWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchHomeView()
        }
    }
}

private struct WatchHomeView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.tint)

            Text("Sloppy")
                .font(.headline)

            Text("Connect Sloppy on your iPhone to view your workspace here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
