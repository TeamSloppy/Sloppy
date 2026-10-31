#if DEBUG && os(iOS)
import SwiftUI
import SloppyClientUI

/// Exercises the production mobile browser without a Core connection or personal history.
@MainActor
struct BrowserMobileFixture: View {
    @State private var state: BrowserWorkspaceState
    @State private var runtimeResult: String?

    init() {
        let defaults = UserDefaults(suiteName: "team.sloppy.browser.mobile-qa") ?? .standard
        if ProcessInfo.processInfo.arguments.contains("--browser-fixture-reset") {
            defaults.removePersistentDomain(forName: "team.sloppy.browser.mobile-qa")
        }
        _state = State(initialValue: BrowserWorkspaceState(defaults: defaults,
            history: WorkspaceBrowserHistory(defaults: defaults)))
    }

    var body: some View {
        BrowserWorkspaceView(state: state, onAskAgent: { state.searchText = $0 }, onCollect: { _ in })
            .theme(isLight ? .sloppyLight : .sloppyDark)
            .modifier(MobileBrowserChromeSchemeModifier(fallback: isLight ? .light : .dark))
            .overlay(alignment: .top) {
                if let runtimeResult {
                    Text(runtimeResult).font(.caption).padding(12).background(.bar)
                        .accessibilityIdentifier("browser-runtime-result")
                }
            }
            .task {
                let prefix = "--browser-fixture-url="
                if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
                   let url = URL(string: String(argument.dropFirst(prefix.count))) {
                    state.open(url, inNewTab: true)
                    if ProcessInfo.processInfo.arguments.contains("--browser-fixture-runtime-check") {
                        await checkRuntime()
                    }
                }
            }
    }

    private var isLight: Bool { ProcessInfo.processInfo.arguments.contains("--browser-fixture-light") }

    private func checkRuntime() async {
        do {
            guard let page = state.selectedPage else { throw ProbeError.failed("Missing page") }
            let runtime = page.ensureBrowserRuntime()
            let deadline = ContinuousClock.now + .seconds(5)
            while runtime.webView.window == nil {
                guard ContinuousClock.now < deadline else { throw ProbeError.failed("Page not attached") }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard let url = state.selectedTab?.url else { throw ProbeError.failed("Missing fixture URL") }
            let first = try await runtime.open(url: url.absoluteString)
            guard first.title == "Browser First Page", first.elements.contains(where: { $0.selector == "#draft" }) else {
                throw ProbeError.failed("Read did not return the local page")
            }
            _ = try await runtime.type(selector: "#draft", text: "Runtime draft\nwith quotes: \"ok\"")
            let value = try await runtime.webView.evaluateJavaScript("document.querySelector('#draft').value") as? String
            guard value?.contains("Runtime draft") == true else { throw ProbeError.failed("Input was not retained") }
            _ = try await runtime.click(selector: "a[href='second.html']")
            guard try await runtime.read().title == "Browser Second Page" else { throw ProbeError.failed("Click did not navigate") }
            _ = try await runtime.scroll(x: 0, y: 100)
            let image = try await runtime.screenshot().imageData
            guard image.starts(with: [137, 80, 78, 71]) else { throw ProbeError.failed("Snapshot was not PNG") }
            runtimeResult = "Browser tools passed"
        } catch {
            runtimeResult = "Browser tools failed: \(error.localizedDescription)"
        }
    }

    private enum ProbeError: LocalizedError {
        case failed(String)
        var errorDescription: String? { if case .failed(let message) = self { message } else { nil } }
    }


}
/// Tests the production mobile shell while its connection transitions from pending to login.
@MainActor
struct BrowserOfflineRootFixture: View {
    @State private var root: RootShellViewModel
    @State private var launch: MobileBrowserLaunchState

    init() {
        let defaults = UserDefaults(suiteName: "team.sloppy.browser.offline-qa") ?? .standard
        if ProcessInfo.processInfo.arguments.contains("--browser-fixture-reset") {
            defaults.removePersistentDomain(forName: "team.sloppy.browser.offline-qa")
        }
        let root = RootShellViewModel()
        root.appState = .pairing(URL(string: "http://127.0.0.1:18875")!)
        _root = State(initialValue: root)
        _launch = State(initialValue: MobileBrowserLaunchState(browser: BrowserWorkspaceState(defaults: defaults,
            history: WorkspaceBrowserHistory(defaults: defaults))))
    }

    var body: some View {
        MobileRootShellView(root: root, safeAreaInsets: .init(), launch: launch,
            endpointOverride: .direct(baseURL: URL(string: "http://127.0.0.1:18875")!)) {
            VStack {
                ContentUnavailableView("Sign in to Work", systemImage: "server.rack",
                    description: Text("The server requires a connection. Browsing is available."))
                Button("Simulate unavailable workspace") {
                    root.appState = .chat(URL(string: "http://127.0.0.1:18875")!)
                }
                .padding()
            }
        }
        .theme(.sloppyDark)
        .modifier(MobileBrowserChromeSchemeModifier(fallback: .dark))
        .task {
            let prefix = "--browser-fixture-url="
            if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
               let url = URL(string: String(argument.dropFirst(prefix.count))) {
                launch.browser.open(url, inNewTab: true)
            }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            root.appState = .authentication(URL(string: "http://127.0.0.1:18875")!,
                .init(mode: "login_password", bootstrapRequired: false), nil)
        }
    }
}
#endif
