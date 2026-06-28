import Foundation
import Testing

@Test("customize flow renders navigation shell with general and widgets sections")
func customizeFlowRendersNavigationShell() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")
    let panelCSSURL = packageRoot.appendingPathComponent("Extension/Resources/panel.css")
    let i18nURL = packageRoot.appendingPathComponent("Extension/Resources/i18n.js")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)
    let panelCSS = try String(contentsOf: panelCSSURL, encoding: .utf8)
    let i18n = try String(contentsOf: i18nURL, encoding: .utf8)

    #expect(contentScript.contains("customizeNavigation"))
    #expect(contentScript.contains("renderCustomizeDialog(frame)"))
    #expect(contentScript.contains("data-sloppy-customize-screen"))
    #expect(panelCSS.contains(".sloppy-customize-nav"))
    #expect(i18n.contains("widgetsSection"))
    #expect(i18n.contains("generalSection"))
}

@Test("start page items migrate to span-based layout metadata")
func startPageItemsMigrateToSpanGridMetadata() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")
    let panelCSSURL = packageRoot.appendingPathComponent("Extension/Resources/panel.css")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)
    let panelCSS = try String(contentsOf: panelCSSURL, encoding: .utf8)

    #expect(contentScript.contains("normalizeStartPageItem(record, fallbackOrder)"))
    #expect(contentScript.contains("applyLegacyWidgetSize(size)"))
    #expect(contentScript.contains("colSpan"))
    #expect(contentScript.contains("rowSpan"))
    #expect(contentScript.contains("renderWidgetsGrid(frame, items)"))
    #expect(panelCSS.contains(".sloppy-widgets-grid"))
}

@Test("widgets screen exposes edit mode with reorder resize and delete controls")
func widgetsScreenExposesEditControls() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")
    let i18nURL = packageRoot.appendingPathComponent("Extension/Resources/i18n.js")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)
    let i18n = try String(contentsOf: i18nURL, encoding: .utf8)

    #expect(contentScript.contains("data-sloppy-toggle-edit"))
    #expect(contentScript.contains("data-sloppy-resize-item"))
    #expect(contentScript.contains("data-sloppy-delete-item"))
    #expect(contentScript.contains("data-sloppy-move-item"))
    #expect(i18n.contains("editWidgets"))
}

@Test("widget editor uses a draft preview with done and cancel actions")
func widgetEditorUsesDraftPreviewFlow() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")
    let i18nURL = packageRoot.appendingPathComponent("Extension/Resources/i18n.js")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)
    let i18n = try String(contentsOf: i18nURL, encoding: .utf8)

    #expect(contentScript.contains("openWidgetEditor(frame, sourceItemId = null)"))
    #expect(contentScript.contains("commitWidgetDraft(frame)"))
    #expect(contentScript.contains("data-sloppy-widget-preview"))
    #expect(contentScript.contains("data-sloppy-widget-editor-prompt"))
    #expect(i18n.contains("widgetEditorDone"))
    #expect(i18n.contains("widgetEditorCancel"))
}

@Test("widgets screen renders a bottom-sheet picker with ready widgets and create placeholder")
func widgetsScreenRendersBottomSheetPicker() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")
    let panelCSSURL = packageRoot.appendingPathComponent("Extension/Resources/panel.css")
    let i18nURL = packageRoot.appendingPathComponent("Extension/Resources/i18n.js")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)
    let panelCSS = try String(contentsOf: panelCSSURL, encoding: .utf8)
    let i18n = try String(contentsOf: i18nURL, encoding: .utf8)

    #expect(contentScript.contains("renderWidgetPickerSheet(frame)"))
    #expect(contentScript.contains("data-sloppy-widget-picker-sheet"))
    #expect(contentScript.contains("data-sloppy-create-widget-card"))
    #expect(panelCSS.contains(".sloppy-widget-picker-sheet"))
    #expect(panelCSS.contains(".sloppy-widget-create-card"))
    #expect(i18n.contains("createWidgetCard"))
}

@Test("shortcut is treated as a widget card and old shortcut form list is removed")
func shortcutIsTreatedAsWidgetCard() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")
    let i18nURL = packageRoot.appendingPathComponent("Extension/Resources/i18n.js")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)
    let i18n = try String(contentsOf: i18nURL, encoding: .utf8)

    #expect(contentScript.contains("openShortcutEditor(frame, sourceItemId = null, seed = null)"))
    #expect(contentScript.contains("data-sloppy-pick-shortcut-widget"))
    #expect(!contentScript.contains("data-sloppy-start-page-add-shortcut"))
    #expect(i18n.contains("shortcutWidget"))
}

@Test("widgets edit mode exposes drag affordances and contextual menus")
func widgetsEditModeExposesDragAffordances() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")
    let panelCSSURL = packageRoot.appendingPathComponent("Extension/Resources/panel.css")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)
    let panelCSS = try String(contentsOf: panelCSSURL, encoding: .utf8)

    #expect(contentScript.contains("state.gridDrag"))
    #expect(contentScript.contains("data-sloppy-grid-draggable"))
    #expect(contentScript.contains("data-sloppy-grid-drop-target"))
    #expect(contentScript.contains("data-sloppy-grid-menu"))
    #expect(panelCSS.contains(".sloppy-grid-drop-preview"))
}

@Test("dragging a valid URL to the grid opens shortcut widget creation")
func draggingValidURLOpensShortcutCreation() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)

    #expect(contentScript.contains("readDroppedURL(event)"))
    #expect(contentScript.contains("isSupportedShortcutURL(value)"))
    #expect(contentScript.contains("openShortcutEditor(frame, null,"))
}

@Test("shortcut editor includes bookmark selection only when bookmark access is available")
func shortcutEditorSupportsBookmarksWhenAvailable() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")
    let backgroundURL = packageRoot.appendingPathComponent("Extension/Resources/background.js")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)
    let background = try String(contentsOf: backgroundURL, encoding: .utf8)

    #expect(contentScript.contains("loadBookmarksIfAvailable(frame)"))
    #expect(contentScript.contains("availableBookmarks"))
    #expect(contentScript.contains("data-sloppy-shortcut-bookmarks"))
    #expect(contentScript.contains("data-sloppy-pick-bookmark"))
    #expect(background.contains("sloppy.bookmarks.list"))
}

@Test("customize commits keep the visible start page preview in sync")
func customizeCommitsSyncVisibleStartPagePreview() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let customizeURL = packageRoot.appendingPathComponent("Extension/Resources/startPageCustomize.js")

    let customize = try String(contentsOf: customizeURL, encoding: .utf8)

    #expect(customize.contains("function syncStartPagePreview(frame, options = {})"))
    #expect(customize.contains("syncStartPagePreview(frame);"))
    #expect(customize.contains("syncStartPagePreview(frame, { animate: false });"))
}

@Test("widget picker delete action uses the standard trash symbol mapping")
func widgetPickerDeleteActionUsesStandardTrashSymbol() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentScriptURL = packageRoot.appendingPathComponent("Extension/Resources/contentScript.js")

    let contentScript = try String(contentsOf: contentScriptURL, encoding: .utf8)

    #expect(contentScript.contains("trash: \"trash\""))
    #expect(!contentScript.contains("trash: \"icons/trash\""))
}
