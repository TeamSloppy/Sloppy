import Foundation

#if os(macOS)
import AppKit
import WebKit
#endif

struct WorkspaceBrowserReadResult: Sendable {
    var url: String
    var title: String
    var visibleText: String
}

struct WorkspaceBrowserActionResult: Sendable {
    var ok: Bool
    var message: String
}

struct WorkspaceBrowserScreenshotResult: Sendable {
    var imageData: Data
}

@MainActor
final class WorkspaceBrowserToolRuntime {
#if os(macOS)
    private weak var webView: WKWebView?

    init(webView: WKWebView?) {
        self.webView = webView
    }

    func open(url: String) async throws -> WorkspaceBrowserReadResult {
        guard let webView else {
            throw WorkspaceBrowserRuntimeError.unavailable
        }

        let normalized = url.contains("://") ? url : "https://\(url)"
        guard let resolvedURL = URL(string: normalized) else {
            throw WorkspaceBrowserRuntimeError.invalidURL
        }

        webView.load(URLRequest(url: resolvedURL))
        return try await read()
    }

    func read() async throws -> WorkspaceBrowserReadResult {
        guard let webView else {
            throw WorkspaceBrowserRuntimeError.unavailable
        }

        let raw = try await evaluate(jsReadVisibleState())
        let payload = raw as? [String: Any]
        let url = payload?["url"] as? String ?? webView.url?.absoluteString ?? ""
        let title = payload?["title"] as? String ?? webView.title ?? ""
        let visibleText = payload?["visibleText"] as? String ?? ""
        return WorkspaceBrowserReadResult(url: url, title: title, visibleText: visibleText)
    }

    func click(selector: String) async throws -> WorkspaceBrowserActionResult {
        _ = try await evaluate(jsClick(selector: selector))
        return WorkspaceBrowserActionResult(ok: true, message: "Clicked \(selector)")
    }

    func type(selector: String, text: String) async throws -> WorkspaceBrowserActionResult {
        _ = try await evaluate(jsType(selector: selector, text: text))
        return WorkspaceBrowserActionResult(ok: true, message: "Typed into \(selector)")
    }

    func scroll(x: Double, y: Double) async throws -> WorkspaceBrowserActionResult {
        _ = try await evaluate(jsScroll(x: x, y: y))
        return WorkspaceBrowserActionResult(ok: true, message: "Scrolled to \(x),\(y)")
    }

    func scrollTo(selector: String) async throws -> WorkspaceBrowserActionResult {
        _ = try await evaluate(jsScrollTo(selector: selector))
        return WorkspaceBrowserActionResult(ok: true, message: "Scrolled to \(selector)")
    }

    func screenshot() async throws -> WorkspaceBrowserScreenshotResult {
        guard let webView else {
            throw WorkspaceBrowserRuntimeError.unavailable
        }

        let image = try await webView.takeSnapshot(configuration: nil)

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            throw WorkspaceBrowserRuntimeError.snapshotFailed
        }
        return WorkspaceBrowserScreenshotResult(imageData: png)
    }

    private func evaluate(_ script: String) async throws -> Any {
        guard let webView else {
            throw WorkspaceBrowserRuntimeError.unavailable
        }

        return try await webView.evaluateJavaScript(script) as Any
    }
#else
    init(webView: AnyObject?) {}

    func open(url: String) async throws -> WorkspaceBrowserReadResult { throw WorkspaceBrowserRuntimeError.unavailable }
    func read() async throws -> WorkspaceBrowserReadResult { throw WorkspaceBrowserRuntimeError.unavailable }
    func click(selector: String) async throws -> WorkspaceBrowserActionResult { throw WorkspaceBrowserRuntimeError.unavailable }
    func type(selector: String, text: String) async throws -> WorkspaceBrowserActionResult { throw WorkspaceBrowserRuntimeError.unavailable }
    func scroll(x: Double, y: Double) async throws -> WorkspaceBrowserActionResult { throw WorkspaceBrowserRuntimeError.unavailable }
    func scrollTo(selector: String) async throws -> WorkspaceBrowserActionResult { throw WorkspaceBrowserRuntimeError.unavailable }
    func screenshot() async throws -> WorkspaceBrowserScreenshotResult { throw WorkspaceBrowserRuntimeError.unavailable }
#endif

    private func jsReadVisibleState() -> String {
        """
        (() => ({
          url: window.location.href,
          title: document.title || "",
          visibleText: (document.body?.innerText || "").trim().slice(0, 12000)
        }))();
        """
    }

    private func jsClick(selector: String) -> String {
        let escaped = selector.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        return """
        (() => {
          const node = document.querySelector('\(escaped)');
          if (!node) { throw new Error('selector_not_found'); }
          node.scrollIntoView({ block: 'center', inline: 'center' });
          node.click();
          return true;
        })();
        """
    }

    private func jsType(selector: String, text: String) -> String {
        let escapedSelector = selector.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        return """
        (() => {
          const node = document.querySelector('\(escapedSelector)');
          if (!node) { throw new Error('selector_not_found'); }
          node.focus();
          if ('value' in node) {
            node.value = '';
            node.value = '\(escapedText)';
          } else {
            node.textContent = '\(escapedText)';
          }
          node.dispatchEvent(new Event('input', { bubbles: true }));
          node.dispatchEvent(new Event('change', { bubbles: true }));
          return true;
        })();
        """
    }

    private func jsScroll(x: Double, y: Double) -> String {
        """
        (() => {
          window.scrollTo(\(x), \(y));
          return true;
        })();
        """
    }

    private func jsScrollTo(selector: String) -> String {
        let escaped = selector.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        return """
        (() => {
          const node = document.querySelector('\(escaped)');
          if (!node) { throw new Error('selector_not_found'); }
          node.scrollIntoView({ block: 'center', inline: 'center' });
          return true;
        })();
        """
    }
}

enum WorkspaceBrowserRuntimeError: Error {
    case unavailable
    case invalidURL
    case snapshotFailed
}
