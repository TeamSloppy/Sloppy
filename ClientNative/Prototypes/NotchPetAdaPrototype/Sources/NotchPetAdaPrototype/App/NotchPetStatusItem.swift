import AppKit

@MainActor
final class NotchPetStatusItem: NSObject {
    static let shared = NotchPetStatusItem()

    private var item: NSStatusItem?

    func install() {
        guard item == nil else { return }
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "sparkles",
            accessibilityDescription: "Ada Notch Pet"
        )
        item.button?.toolTip = "AdaEngine Notch Pet"

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Pet", action: #selector(showPet), keyEquivalent: "")
        menu.addItem(withTitle: "Hide Pet", action: #selector(hidePet), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Ada Notch Pet", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        self.item = item
    }

    @objc private func showPet() {
        petWindow?.orderFrontRegardless()
    }

    @objc private func hidePet() {
        petWindow?.orderOut(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private var petWindow: NSWindow? {
        NSApp.windows.first { $0.title == "Ada Notch Pet" } ?? NSApp.windows.first
    }
}
