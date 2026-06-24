import Foundation
import Testing

@Test("start page renders restore button and collapsed state exposes it")
func startPageCollapsedSidebarHasRestoreButton() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")
    let panelCSSURL = packageRoot.appendingPathComponent("Extension/Resources/panel.css")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)
    let panelCSS = try String(contentsOf: panelCSSURL, encoding: .utf8)

    #expect(contentScript.contains("isFullscreen || isMobile || isStartPageMode()"))
    #expect(panelCSS.contains(".sloppy-start-page #sloppy-safari-extension-panel .is-sidebar-collapsed [data-sloppy-sidebar-restore]"))
}

@Test("fullscreen mobile collapsed sidebar keeps content column visible")
func fullscreenCollapsedSidebarKeepsSingleColumnLayout() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let panelCSSURL = packageRoot.appendingPathComponent("Extension/Resources/panel.css")

    let panelCSS = try String(contentsOf: panelCSSURL, encoding: .utf8)

    #expect(panelCSS.contains("""
  .sloppy-fullscreen-chat-page #sloppy-safari-extension-panel .sloppy-app-layout.is-sidebar-collapsed,
  .sloppy-start-page #sloppy-safari-extension-panel .sloppy-app-layout.is-sidebar-collapsed {
    grid-template-columns: minmax(0, 1fr);
  }
"""))
}

@Test("sidebar restore button lives in the leading row with transparent styling")
func sidebarRestoreButtonUsesLeadingTransparentStyle() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")
    let panelCSSURL = packageRoot.appendingPathComponent("Extension/Resources/panel.css")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)
    let panelCSS = try String(contentsOf: panelCSSURL, encoding: .utf8)

    #expect(contentScript.contains("sloppy-topbar-leading"))
    #expect(contentScript.contains("sloppy-sidebar-toggle"))
    #expect(panelCSS.contains(".sloppy-sidebar-toggle"))
}
