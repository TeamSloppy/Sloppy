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
    #expect(!contentScript.contains("${!isFullscreen ? `<button class=\"sloppy-icon-button\" type=\"button\" data-sloppy-sessions"))
    #expect(panelCSS.contains(".sloppy-icon-button.sloppy-sidebar-toggle"))
    #expect(panelCSS.contains("background: transparent;"))
}

@Test("customize button is rendered inside sloppy shell flow")
func customizeButtonLivesInsideShell() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")
    let panelCSSURL = packageRoot.appendingPathComponent("Extension/Resources/panel.css")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)
    let panelCSS = try String(contentsOf: panelCSSURL, encoding: .utf8)

    #expect(contentScript.contains("""
      <div class="sloppy-start-shortcuts" data-sloppy-start-shortcuts></div>
      <button class="sloppy-start-config-button" type="button" data-sloppy-customize>
"""))
    #expect(panelCSS.contains("align-self: center;"))
    #expect(!panelCSS.contains("""
.sloppy-start-config-button {
  position: fixed;
"""))
}

@Test("sidebar switches between artifacts and sessions instead of keeping both expanded")
func sidebarSectionsCollapseEachOther() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)

    #expect(contentScript.contains("""
  frame.querySelector("[data-sloppy-sidebar-artifacts]")?.addEventListener("click", () => {
    const artifactList = frame.querySelector("[data-sloppy-sidebar-artifact-list]");
    const sessionList = frame.querySelector("[data-sloppy-sidebar-session-list]");
"""))
    #expect(contentScript.contains("""
    if (sessionList) {
      sessionList.hidden = true;
    }
"""))
    #expect(contentScript.contains("""
  frame.querySelector("[data-sloppy-sidebar-sessions]")?.addEventListener("click", () => {
    const sessionList = frame.querySelector("[data-sloppy-sidebar-session-list]");
    const artifactList = frame.querySelector("[data-sloppy-sidebar-artifact-list]");
"""))
    #expect(contentScript.contains("""
    if (artifactList) {
      artifactList.hidden = true;
    }
"""))
}
