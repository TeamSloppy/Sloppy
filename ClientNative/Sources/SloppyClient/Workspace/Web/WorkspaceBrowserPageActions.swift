#if os(macOS)
import Foundation
import AppKit
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import WebKit

@MainActor
final class WorkspaceBrowserPageActions: NSObject {
    private weak var webView: WKWebView?
    private var auxiliaryWindows: [UUID: BrowserPageWindowController] = [:]

    init(webView: WKWebView) { self.webView = webView }

    @objc func goBack(_ sender: Any?) { webView?.goBack() }
    @objc func goForward(_ sender: Any?) { webView?.goForward() }
    @objc func reloadPage(_ sender: Any?) { webView?.reload() }

    @objc func savePage(_ sender: Any?) {
        guard let webView, let window = webView.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.webArchive]
        panel.nameFieldStringValue = (webView.title ?? "Page").replacingOccurrences(of: "/", with: "-") + ".webarchive"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url, let self else { return }
            Task { @MainActor in
                let accessed = destination.startAccessingSecurityScopedResource()
                defer { if accessed { destination.stopAccessingSecurityScopedResource() } }
                do { try await self.archiveData().write(to: destination, options: .atomic) }
                catch { self.presentError("Couldn’t save this page", error: error) }
            }
        }
    }

    func archiveData() async throws -> Data {
        guard let webView else { throw WorkspaceBrowserRuntimeError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            webView.createWebArchiveData { continuation.resume(with: $0) }
        }
    }

    @objc func printPage(_ sender: Any?) {
        guard let webView, let window = webView.window else { return }
        let operation = webView.printOperation(with: .shared)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    @objc func showPageSource(_ sender: Any?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let source = try await self.pageSource()
                let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
                scroll.hasVerticalScroller = true
                let text = NSTextView(frame: scroll.bounds)
                text.isEditable = false
                text.isSelectable = true
                text.isRichText = false
                text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                text.textContainerInset = NSSize(width: 16, height: 16)
                text.autoresizingMask = [.width]
                text.isVerticallyResizable = true
                text.string = source
                scroll.documentView = text
                self.showWindow(content: scroll, title: "Page Source — " + (self.webView?.url?.host ?? "Page"),
                                subtitle: "Current page HTML (DOM)", size: scroll.frame.size)
            } catch { self.presentError("Couldn’t read page source", error: error) }
        }
    }

    func pageSource() async throws -> String {
        guard let webView,
              let source = try await webView.evaluateJavaScript("new XMLSerializer().serializeToString(document)") as? String else {
            throw WorkspaceBrowserRuntimeError.unavailable
        }
        return source
    }

    @objc func showQRCode(_ sender: Any?) {
        guard let url = BrowserSearchEngine.websiteURL(webView?.url), let image = Self.qrImage(for: url) else { return }
        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleNone
        imageView.allowsCutCopyPaste = true
        let paper = NSView()
        paper.wantsLayer = true
        paper.layer?.backgroundColor = NSColor.white.cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        paper.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: paper.leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: paper.trailingAnchor, constant: -16),
            imageView.topAnchor.constraint(equalTo: paper.topAnchor, constant: 16),
            imageView.bottomAnchor.constraint(equalTo: paper.bottomAnchor, constant: -16),
            imageView.widthAnchor.constraint(equalToConstant: image.size.width),
            imageView.heightAnchor.constraint(equalToConstant: image.size.height),
        ])
        let label = NSTextField(labelWithString: url.absoluteString)
        label.isSelectable = true
        label.lineBreakMode = .byTruncatingMiddle
        let stack = NSStackView(views: [paper, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        let size = NSSize(width: image.size.width + 72, height: image.size.height + 112)
        showWindow(content: stack, title: "QR Code for this Page", size: size, resizable: false)
    }

    static func qrImage(for url: URL) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let extent = output.extent.insetBy(dx: -4, dy: -4)
        let quietZone = CIImage(color: .white).cropped(to: extent)
        let code = output.composited(over: quietZone)
        let scale = max(1, floor(264 / extent.width))
        let image = code.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
    }

    @objc func translatePage(_ sender: Any?) {
        guard let url = Self.translationURL(for: webView?.url) else { return }
        webView?.load(URLRequest(url: url))
    }

    @objc func inspectInSafari(_ sender: Any?) {
        guard let window = webView?.window else { return }
        let alert = NSAlert()
        alert.messageText = "Inspect this Sloppy page in Safari"
        alert.informativeText = "In Safari, choose Develop → This Mac → Sloppy → " + (webView?.title ?? "this page") + ".\n\nIf Develop is hidden, enable ‘Show features for web developers’ in Safari Settings → Advanced."
        alert.addButton(withTitle: "Open Safari")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn,
                  let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else { return }
            NSWorkspace.shared.openApplication(at: safari, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    static func translationURL(for url: URL?) -> URL? {
        guard let url = BrowserSearchEngine.websiteURL(url), let host = url.host?.lowercased(),
              !WorkspaceBrowserAddress.isLoopback(host), host.contains("."), !host.contains(":"), !host.hasSuffix(".local"),
              !host.hasSuffix(".lan"), !host.hasSuffix(".internal") else { return nil }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        if octets.count == 4 {
            if octets[0] == 0 || octets[0] == 10 || octets[0] == 127 || octets[0] >= 224 ||
               (octets[0] == 169 && octets[1] == 254) || (octets[0] == 172 && (16...31).contains(octets[1])) ||
               (octets[0] == 192 && octets[1] == 168) { return nil }
        }
        var result = URLComponents()
        result.scheme = "https"
        result.host = "translate.google.com"
        result.path = "/translate"
        result.queryItems = [.init(name: "sl", value: "auto"), .init(name: "tl", value: "ru"), .init(name: "u", value: url.absoluteString)]
        result.percentEncodedQuery = result.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return result.url
    }

    private func showWindow(content: NSView, title: String, subtitle: String = "", size: NSSize, resizable: Bool = true) {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.subtitle = subtitle
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.center()
        let id = UUID()
        let controller = BrowserPageWindowController(window: window)
        controller.onClose = { [weak self] in self?.auxiliaryWindows.removeValue(forKey: id) }
        window.delegate = controller
        auxiliaryWindows[id] = controller
        controller.showWindow(nil)
    }

    private func presentError(_ title: String, error: Error) {
        guard let window = webView?.window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.beginSheetModal(for: window)
    }
}

@MainActor
private final class BrowserPageWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
}
#endif
