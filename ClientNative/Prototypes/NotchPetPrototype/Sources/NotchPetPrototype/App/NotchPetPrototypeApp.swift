import AppKit

@main
@MainActor
enum NotchPetPrototypeApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = NotchPetAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
private final class NotchPetAppDelegate: NSObject, NSApplicationDelegate {
    private let notchController = NotchPanelController()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        notchController.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        notchController.stop()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "face.smiling.inverse",
            accessibilityDescription: "Notch Pet"
        )
        item.button?.toolTip = "Notch Pet Prototype"

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Pet", action: #selector(showPet), keyEquivalent: "")
        menu.addItem(withTitle: "Hide Pet", action: #selector(hidePet), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Think", action: #selector(think), keyEquivalent: "t")
        menu.addItem(withTitle: "React", action: #selector(react), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Notch Pet", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func showPet() {
        notchController.show()
    }

    @objc private func hidePet() {
        notchController.hide()
    }

    @objc private func think() {
        notchController.triggerThinking()
    }

    @objc private func react() {
        notchController.triggerReaction()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
