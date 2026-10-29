@_spi(AdaEngine) import AdaEngine
import Observation
import SloppyClientCore
import SloppyClientUI

@Observable @MainActor
final class WorkspaceBrowserModel {
    let runtime = WorkspaceBrowserRuntime()
    var address = ""
    var title = "Browser"
    var error: String?
    var image: Image?
    var revision = 0
    var isRunning = false
    var isLoading = false
    @ObservationIgnored private var frames: Task<Void, Never>?
    private var starting = false
    var executable = ""
    var pageID = UUID().uuidString
    var bridgeStatus = ""
    @ObservationIgnored var bridgeTask: Task<Void, Never>?
    @ObservationIgnored var binding: WorkspaceBrowserBinding?

    isolated deinit { frames?.cancel(); bridgeTask?.cancel(); runtime.stop() }

    func open() async {
        guard !starting else { return }
        starting = true; isLoading = true; error = nil
        defer { starting = false; isLoading = false }
        do {
            try await runtime.start(executable: executable)
            isRunning = true
            try await runtime.navigate(address)
            startFrames()
        } catch { self.error = error.localizedDescription }
    }
    func stop() { frames?.cancel(); frames = nil; runtime.stop(); isRunning = false; image = nil }
    func action(_ method: String, _ params: [String: ConfigJSONValue] = [:]) async {
        do { _ = try await runtime.command(method, params: params); error = nil }
        catch { self.error = error.localizedDescription }
    }
    func history(_ delta: Int) async {
        do {
            let result = try await runtime.command("Page.getNavigationHistory")
            guard case .number(let index) = result["currentIndex"], case .array(let entries) = result["entries"], entries.indices.contains(Int(index) + delta) else { return }
            _ = try await runtime.command("Page.navigateToHistoryEntry", params: ["entryId": entries[Int(index) + delta]["id"]])
        } catch { self.error = error.localizedDescription }
    }
    func startFrames() {
        guard frames == nil else { return }
        frames = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let data = try await runtime.screenshot()
                    guard !Task.isCancelled else { return }
                    image = try Image.decode(from: data); revision += 1
                    failures = 0; error = nil
                    let page = try await runtime.command("Runtime.evaluate", params: ["expression": .string("JSON.stringify({url:location.href,title:document.title})"), "returnByValue": .bool(true)])
                    if let json = page["result"]["value"].string,
                       let info = try? JSONDecoder().decode(ConfigJSONValue.self, from: Data(json.utf8)) {
                        title = info["title"].string ?? "Browser"
                        // Avoid overwriting a URL while the user is editing the address field.
                    }
                    try await Task.sleep(for: .milliseconds(350))
                } catch is CancellationError { return }
                catch {
                    failures += 1
                    if failures >= 10 { self.error = error.localizedDescription; frames = nil; return }
                    do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                }
            }
        }
    }
}

struct WorkspaceBrowserPanel: View {
    let model: WorkspaceBrowserModel
    @Environment(\.theme) private var theme
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    WorkspaceAction(title: "‹") { Task { await model.history(-1) } }.disabled(!model.isRunning)
                    WorkspaceAction(title: "›") { Task { await model.history(1) } }.disabled(!model.isRunning)
                    WorkspaceIconButton(icon: .refresh) { Task { await model.action("Page.reload") } }
                    Spacer()
                    if model.isRunning { WorkspaceAction(title: "Stop") { model.stop() } }
                }
                HStack(spacing: 6) {
                    TextField("Enter a URL", text: Binding(get: { model.address }, set: { model.address = $0 }), onSubmit: { Task { await model.open() } })
                        .font(.system(size: 13)).padding(.horizontal, 8).frame(width: max(100, geometry.size.width - 88), height: 36)
                        .background(theme.colors.surfaceRaised).accessibilityIdentifier("workspace.browser.address")
                    WorkspaceAction(title: model.isLoading ? "…" : "Go", primary: true) { Task { await model.open() } }.disabled(model.isLoading)
                }
                Text(model.title).font(.system(size: 12)).lineLimit(1)
                if !model.bridgeStatus.isEmpty { Text(model.bridgeStatus).font(.system(size: 10)).lineLimit(1).foregroundColor(theme.colors.textMuted) }
                if let error = model.error { Text(error).font(.system(size: 12)).foregroundColor(theme.colors.statusBlocked).lineLimit(3) }
                if model.isRunning {
                    BrowserPageSurface(model: model)
                        .frame(width: max(1, geometry.size.width - 20), height: max(100, geometry.size.height - 145))
                        .accessibilityIdentifier("workspace.browser.page")
                } else {
                    Text("Open a website to browse it here. Click the page to type and scroll.")
                        .font(.system(size: 13)).foregroundColor(theme.colors.textMuted).padding(16)
                }
            }.padding(.horizontal, 10).frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }.sloppyTextInputStyle(theme.colors)
    }
}

private struct BrowserPageSurface: UIViewRepresentable {
    let model: WorkspaceBrowserModel
    func makeUIView(in context: Context) -> BrowserPageView { BrowserPageView(frame: .zero) }
    func sizeThatFits(_ proposal: ProposedViewSize, view: BrowserPageView, context: Context) -> Size { proposal.replacingUnspecifiedDimensions() }
    func updateUIView(_ view: BrowserPageView, in context: Context) {
        view.model = model
        if view.revision != model.revision { view.image = model.image; view.revision = model.revision }
    }
}

private final class BrowserPageView: UIView {
    var model: WorkspaceBrowserModel?
    var image: Image? { didSet { texture = image.map { Texture2D(image: $0) }; setNeedsDisplay() } }
    private var texture: Texture2D?
    var revision = -1
    override var acceptsKeyboardFocus: Bool { true }
    override func draw(in rect: Rect, with context: UIGraphicsContext) { context.drawRect(bounds, texture: texture, color: .white) }
    override func onMouseEvent(_ event: MouseEvent) {
        guard let model else { return }
        let x = Double(event.mousePosition.x / max(1, bounds.width)) * 800
        let y = Double(event.mousePosition.y / max(1, bounds.height)) * 900
        if event.button == .scrollWheel {
            Task { await model.action("Input.dispatchMouseEvent", ["type": .string("mouseWheel"), "x": .number(x), "y": .number(y), "deltaX": .number(Double(event.scrollDelta.x) * -80), "deltaY": .number(Double(event.scrollDelta.y) * -80)]) }
        } else if event.button == .left && (event.phase == .began || event.phase == .ended) {
            let type = event.phase == .began ? "mousePressed" : "mouseReleased"
            Task { await model.action("Input.dispatchMouseEvent", ["type": .string(type), "x": .number(x), "y": .number(y), "button": .string("left"), "clickCount": .number(1)]) }
        }
    }
    override func onTextInputEvent(_ event: TextInputEvent) {
        guard event.action == .insert || event.action == .commitText, let model, !event.text.isEmpty else { return }
        Task { await model.action("Input.insertText", ["text": .string(event.text)]) }
    }
    override func onKeyEvent(_ event: KeyEvent) {
        guard let model else { return }
        if event.status == .down, event.keyCode == .v, event.modifiers.contains(.main), let text = UIClipboard.getString() {
            Task { await model.action("Input.insertText", ["text": .string(text)]) }; return
        }
        let key: (String, Int)? = switch event.keyCode {
        case .enter: ("Enter", 13); case .backspace: ("Backspace", 8); case .tab: ("Tab", 9)
        case .escape: ("Escape", 27); case .arrowUp: ("ArrowUp", 38); case .arrowDown: ("ArrowDown", 40)
        case .arrowLeft: ("ArrowLeft", 37); case .arrowRight: ("ArrowRight", 39); case .delete: ("Delete", 46)
        default: nil
        }
        var modifiers = 0
        if event.modifiers.contains(.alt) { modifiers |= 1 }
        if event.modifiers.contains(.control) { modifiers |= 2 }
        if event.modifiers.contains(.main) && !event.modifiers.contains(.control) { modifiers |= 4 }
        if event.modifiers.contains(.shift) { modifiers |= 8 }
        let resolved = key ?? (modifiers & 6 != 0 && event.keyCode.rawValue.count == 1
            ? (event.keyCode.rawValue, Int(event.keyCode.rawValue.uppercased().utf8.first ?? 0)) : nil)
        guard let resolved else { return }
        Task { await model.action("Input.dispatchKeyEvent", ["type": .string(event.status == .down ? "keyDown" : "keyUp"), "key": .string(resolved.0), "windowsVirtualKeyCode": .number(Double(resolved.1)), "modifiers": .number(Double(modifiers))]) }
    }
}
