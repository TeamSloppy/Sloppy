import AdaEngine
import AppKit

@main
struct NotchPetAdaPrototypeApp: App {
    static let panelSize = Size(width: 348, height: 156)

    var body: some AppScene {
        DefaultAppWindow()
            .addPlugins(NotchPetAdaPlugin())
            .windowMode(.windowed)
            .minimumSize(width: Self.panelSize.width, height: Self.panelSize.height)
            .singleWindow(true)
            .windowTitle("Ada Notch Pet")
            .windowChrome(.borderless)
            .windowTransparentBackground()
            .windowResizable(false)
            .windowShadow(false)
            .transformAppWorlds { worlds in
                let settings = worlds.main.getRefResource(WindowSettings.self)
                settings.wrappedValue.frame = Self.notchFrame()
                settings.wrappedValue.level = .statusBar
                settings.wrappedValue.collectionBehavior = .allSpacesStationary
                settings.wrappedValue.showsImmediately = true
                settings.wrappedValue.makeKey = false
            }
    }

    @MainActor
    private static func notchFrame() -> Rect {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return Rect(origin: .zero, size: panelSize)
        }
        return Rect(
            origin: Point(
                x: Float(screen.frame.midX) - panelSize.width / 2,
                y: Float(screen.frame.maxY) - panelSize.height
            ),
            size: panelSize
        )
    }
}
