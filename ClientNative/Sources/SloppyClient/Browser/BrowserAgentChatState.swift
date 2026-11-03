import Foundation
import Observation
import SloppyClientCore
import SloppyFeatureChat

/// A conversation belongs to the browsing workspace, independently of Work tabs.
@Observable
@MainActor
final class BrowserAgentChatState {
    let chat: ChatScreenViewModel
    let panel = WorkspaceDockState()
    private(set) var contextError: String?
    private(set) var isAddingPage = false
    private(set) var isSummarizingPage = false
#if os(macOS)
    @ObservationIgnored private weak var annotationPage: WorkspaceWebViewModel?
#endif
    private var presentationID = UUID()
    @ObservationIgnored private(set) var browserConnection: WorkspaceBrowserSession?
    @ObservationIgnored private var connectionRevision = UUID()
    @ObservationIgnored private var connectionStopTask: Task<Void, Never>?
    @ObservationIgnored private let apiClient: SloppyAPIClient

    init(chat: ChatScreenViewModel, apiClient: SloppyAPIClient? = nil) {
        self.chat = chat
        self.apiClient = apiClient ?? SloppyAPIClient(endpoint: chat.sessionEndpoint)
        panel.preferredWidth = 420
    }

    func show(prompt: String? = nil) {
        panel.isPresented = true
        chat.loadInitialData()
        if let prompt { chat.addTextSelectionToComposer(prompt) }
        chat.requestComposerFocus()
    }

    func hide() {
#if os(macOS)
        cancelElementAnnotation()
#endif
        presentationID = UUID()
        panel.hide()
    }

    func toggle() {
        if panel.isPresented { hide() } else { show() }
    }

    func canSummarizePage(from browser: BrowserWorkspaceState) -> Bool {
        browser.isBrowsing && !isSummarizingPage && !chat.isSending && !chat.isAwaitingAgentResponse
            && chat.activeInputRequest == nil && browser.selectedPage?.isLoading == false
            && BrowserSearchEngine.websiteURL(browser.selectedPage?.currentURL) != nil
    }

    func summarizeCurrentPage(from browser: BrowserWorkspaceState) async {
        guard canSummarizePage(from: browser), let page = browser.selectedPage,
              let url = BrowserSearchEngine.websiteURL(page.currentURL) else { return }
        let tabID = browser.selectedID
        let title = page.pageTitle ?? browser.selectedTab?.title ?? url.host ?? "Page"
        contextError = nil
        isSummarizingPage = true
        defer { isSummarizingPage = false }
        show()
        let id = presentationID
        let initialAgentID = chat.selectedAgent?.id
        let initialSessionID = chat.selectedSessionId
        await chat.waitForInitialData()
        guard initialSessionID == chat.selectedSessionId,
              initialAgentID == nil || initialAgentID == chat.selectedAgent?.id else {
            contextError = "The conversation changed. Summarize the page again."
            return
        }
        let agentID = chat.selectedAgent?.id
        let sessionID = chat.selectedSessionId
        do {
#if os(macOS) || os(iOS)
            let snapshot = try await page.ensureBrowserRuntime().read()
            let text = snapshot.visibleText.trimmingCharacters(in: .whitespacesAndNewlines)
#else
            let text = title
#endif
            guard !Task.isCancelled, browser.isBrowsing, panel.isPresented, presentationID == id else { return }
            guard browser.selectedID == tabID, browser.selectedPage === page, page.currentURL == url else {
                contextError = "The page changed. Summarize the current page again."
                return
            }
            guard chat.selectedAgent?.id == agentID, chat.selectedSessionId == sessionID else {
                contextError = "The conversation changed. Summarize the page again."
                return
            }
            guard !text.isEmpty else {
                contextError = "This page has no readable text to summarize."
                return
            }
            let quote = ChatComposerQuote(text: String(decoding: text.utf16.prefix(12000), as: UTF16.self),
                browserSource: .init(url: url, title: title))
            if !chat.summarizeBrowserPage(quote) {
                contextError = "Choose an available assistant to summarize this page."
            }
        } catch {
            contextError = "Could not read this page: \(error.localizedDescription)"
        }
    }

    func finishHomeComposerHandoff() {
        guard panel.isPresented else { return }
        // Removing the focused Home editor can reset the window's first responder.
        chat.dismissComposerFocus()
        chat.requestComposerFocus()
    }

    func synchronizeBrowser(_ browser: BrowserWorkspaceState) async {
#if os(macOS) || os(iOS)
        let revision = UUID()
        connectionRevision = revision
        await connectionStopTask?.value
        guard connectionRevision == revision, !Task.isCancelled else { return }
        connectionStopTask = nil
        let page = browser.isBrowsing ? browser.selectedPage : nil
        let agentID = chat.selectedAgent?.id
        let sessionID = chat.selectedSessionId
        if let connection = browserConnection,
           connection.binding.agentId == agentID, connection.binding.sessionId == sessionID, browser.isBrowsing {
            if let page { connection.viewModel = page }
            connection.agentPaletteID = chat.selectedAgent?.pet?.visual?.paletteId
            return
        }
        let previous = browserConnection
        browserConnection = nil
        if let previous {
            let stop = Task { await previous.stopAndWait() }
            connectionStopTask = stop
            await stop.value
        }
        guard connectionRevision == revision, !Task.isCancelled, browser.isBrowsing,
              browser.selectedPage === page,
              let agentID, chat.selectedAgent?.id == agentID,
              let sessionID, chat.selectedSessionId == sessionID else { return }
        connectionStopTask = nil
        let connection = WorkspaceBrowserSession(apiClient: apiClient, agentID: agentID, sessionID: sessionID,
            viewModel: page, workspace: browser, agentPaletteID: chat.selectedAgent?.pet?.visual?.paletteId) { [weak self, weak browser] in
                guard let browser, browser.isBrowsing,
                      let page = self?.browserConnection?.viewModel,
                      let tab = browser.tabs.first(where: { browser.pages[$0.id] === page }) else { return }
                if browser.selectedID != tab.id { browser.select(tab.id) }
            }
        browserConnection = connection
        connection.start()
#endif
    }

    func stopBrowserConnection() {
        connectionRevision = UUID()
        let previous = browserConnection
        let pending = connectionStopTask
        previous?.stop()
        browserConnection = nil
        connectionStopTask = Task {
            await pending?.value
            await previous?.stopAndWait()
        }
    }

    func makeAnnotationReceiver() -> BrowserTextAnnotationReceiver? {
        guard panel.isPresented else { return nil }
        let id = presentationID
        let receive = chat.makeBrowserTextAnnotationReceiver()
        return { [weak self] quote in
            guard let self, panel.isPresented, presentationID == id else { return false }
            return receive(quote)
        }
    }

#if os(macOS)
    func cancelElementAnnotation() {
        annotationPage?.annotations.cancel()
        annotationPage = nil
    }

    func toggleElementAnnotation(in browser: BrowserWorkspaceState) async {
        guard panel.isPresented, browser.isBrowsing, let page = browser.selectedPage,
              !page.isLoading, BrowserSearchEngine.websiteURL(page.currentURL) != nil else { return }
        let wasActive = page.annotations.isSelecting || page.annotations.isCapturing || page.annotations.draft != nil
        cancelElementAnnotation()
        guard !wasActive else { return }
        let id = presentationID
        let tabID = browser.selectedID
        let receive = chat.makeBrowserAnnotationReceiver()
        annotationPage = page
        page.textSelection.dismiss()
        await page.annotations.begin(in: page.ensureBrowserRuntime().webView) { [weak self, weak browser, weak page] attachment in
            guard let self, let browser, let page, panel.isPresented, presentationID == id,
                  browser.isBrowsing, browser.selectedID == tabID, browser.selectedPage === page else { return false }
            return receive(attachment)
        }
    }
#endif

    func addCurrentPage(from browser: BrowserWorkspaceState) async {
        guard !isAddingPage, let page = browser.selectedPage,
              let url = BrowserSearchEngine.websiteURL(page.currentURL ?? browser.selectedTab?.url),
              let receive = makeAnnotationReceiver() else { return }
        let tabID = browser.selectedID
        let title = page.pageTitle ?? browser.selectedTab?.title ?? url.host ?? "Page"
        contextError = nil
        isAddingPage = true
        defer { isAddingPage = false }
        do {
#if os(macOS) || os(iOS)
            let snapshot = try await page.ensureBrowserRuntime().read()
            let text = snapshot.visibleText.trimmingCharacters(in: .whitespacesAndNewlines)
#else
            let text = title
#endif
            guard browser.selectedID == tabID, page.currentURL == url else {
                contextError = "The page changed. Add the current page again."
                return
            }
            let boundedText = String(decoding: (text.isEmpty ? title : text).utf16.prefix(12000), as: UTF16.self)
            let quote = ChatComposerQuote(text: boundedText,
                browserSource: .init(url: url, title: title))
            if !receive(quote) { contextError = "The conversation changed. Add the page again." }
        } catch {
            contextError = "Could not read this page: \(error.localizedDescription)"
        }
    }
}
