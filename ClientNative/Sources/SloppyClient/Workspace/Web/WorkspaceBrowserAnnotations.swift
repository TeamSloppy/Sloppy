#if os(macOS)
import AppKit
import Observation
import SloppyFeatureChat
import WebKit

struct WorkspaceBrowserElementSelection: Decodable {
    let nonce: String
    let pageURL: String
    let title: String
    let selector: String
    let tag: String
    let elementID: String
    let classNames: [String]
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var elementLabel: String {
        tag + (elementID.isEmpty ? "" : "#" + elementID) + classNames.map { "." + $0 }.joined()
    }

    var region: ChatImageRegion { .init(x: x, y: y, width: width, height: height) }

    static func decode(_ body: Any, url: URL?, nonce: String) throws -> Self {
        guard JSONSerialization.isValidJSONObject(body) else { throw AnnotationError.invalidSelection }
        let selection = try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: body))
        guard selection.nonce == nonce, selection.pageURL == url?.absoluteString,
              ["http", "https"].contains(url?.scheme?.lowercased() ?? ""), url?.host != nil,
              !selection.selector.isEmpty, selection.selector.count <= 1024,
              !selection.tag.isEmpty, selection.tag.count <= 64,
              selection.elementID.count <= 1024, selection.classNames.count <= 64,
              selection.classNames.allSatisfy({ !$0.isEmpty && $0.count <= 128 }),
              [selection.x, selection.y, selection.width, selection.height].allSatisfy(\.isFinite),
              selection.x >= 0, selection.y >= 0, selection.width > 0, selection.height > 0,
              selection.x + selection.width <= 1.000001, selection.y + selection.height <= 1.000001 else {
            throw AnnotationError.invalidSelection
        }
        return selection
    }
}

private enum AnnotationError: LocalizedError {
    case invalidSelection, snapshotFailed
    var errorDescription: String? {
        switch self {
        case .invalidSelection: "The selected element is no longer available. Select it again."
        case .snapshotFailed: "Could not capture the selected page."
        }
    }
}

@Observable
@MainActor
final class WorkspaceBrowserAnnotations {
    struct Draft: Identifiable {
        let id = UUID()
        let element: WorkspaceBrowserElementSelection
        let image: NSImage
        let data: Data
        var comment = ""
    }

    private(set) var isSelecting = false
    private(set) var isCapturing = false
    var draft: Draft?
    var errorMessage: String?
    private var nonce = UUID().uuidString
    private weak var webView: WKWebView?
    private var receive: (@MainActor (ChatComposerAttachment) -> Bool)?
    static let world = WKContentWorld.world(name: "SloppyBrowserAnnotations")
    private(set) var hovered: WorkspaceBrowserElementSelection?
    private var hoverTask: Task<Void, Never>?

    func begin(in webView: WKWebView, receive: @escaping @MainActor (ChatComposerAttachment) -> Bool) async {
        cancel()
        self.webView = webView
        self.receive = receive
        isSelecting = true
    }

    func cancel() {
        nonce = UUID().uuidString
        hoverTask?.cancel()
        hovered = nil
        isSelecting = false
        isCapturing = false
        draft = nil
        errorMessage = nil
        receive = nil
    }

    func stopPicking() {
        if draft == nil { cancel() }
    }

    func hover(at point: CGPoint?) {
        hoverTask?.cancel()
        guard let point, isSelecting else { hovered = nil; return }
        let token = nonce
        hoverTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(30))
                guard let self else { return }
                let element = try await inspect(at: point, nonce: token)
                guard nonce == token, !Task.isCancelled else { return }
                hovered = element
            } catch { }
        }
    }

    func pick(at point: CGPoint) {
        guard isSelecting, let webView else { return }
        let token = nonce
        hoverTask?.cancel()
        hovered = nil
        isSelecting = false
        isCapturing = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let element = try await inspect(at: point, nonce: token)
                guard nonce == token else { return }
                let image = try await webView.takeSnapshot(configuration: nil)
                guard nonce == token else { return }
                guard webView.url?.absoluteString == element.pageURL else { throw AnnotationError.invalidSelection }
                guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                      let data = bitmap.representation(using: .png, properties: [:]) else { throw AnnotationError.snapshotFailed }
                draft = Draft(element: element, image: image, data: data)
                isCapturing = false
            } catch {
                guard nonce == token else { return }
                cancel()
                errorMessage = error.localizedDescription
            }
        }
    }

    private func inspect(at point: CGPoint, nonce: String) async throws -> WorkspaceBrowserElementSelection {
        guard let webView else { throw AnnotationError.invalidSelection }
        let body = try await webView.callAsyncJavaScript(Self.inspectorScript,
            arguments: ["nonce": nonce, "x": point.x, "y": point.y], in: nil, contentWorld: Self.world)
        guard let body else { throw AnnotationError.invalidSelection }
        return try WorkspaceBrowserElementSelection.decode(body, url: webView.url, nonce: nonce)
    }

    func save() {
        guard let draft else { return }
        let comment = draft.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !comment.isEmpty else { cancel(); return }
        guard var components = URLComponents(string: draft.element.pageURL) else { return }
        components.user = nil
        components.password = nil
        guard let url = components.url else { return }
        let source = ChatImageAnnotation.BrowserSource(url: url, title: String(draft.element.title.prefix(200)),
                                                      selector: draft.element.selector, tag: draft.element.tag,
                                                      elementID: draft.element.elementID, classNames: draft.element.classNames)
        let attachment = ChatComposerAttachment(name: "Browser annotation.png", mimeType: "image/png", data: draft.data,
            annotations: [.init(region: draft.element.region, comment: comment, browserSource: source)])
        guard receive?(attachment) == true else {
            errorMessage = "The destination chat changed or cannot accept another attachment."
            return
        }
        cancel()
    }

}
#endif
