#if os(macOS)
import Foundation
import Network

final class BrowserHTTPFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "sloppy.browser.fixture")

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws -> URL {
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { _, _, _, _ in
                // Deliberately slow response catches open() reading the previous document.
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                    let body = """
                    <!doctype html><html><head><title>Loaded through HTTP</title>
                    <style>body{font:20px system-ui;padding:40px;background:#f5f7fb;color:#172033}button,input{font:inherit;padding:12px}#result{margin-top:24px}</style></head>
                    <body><h1>Sloppy browser smoke test</h1><input id="name" placeholder="Name">
                    <button id="check" onclick="document.getElementById('result').textContent='Verified: '+document.getElementById('name').value">Check</button>
                    <div id="result">Ready</div></body></html>
                    """
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                }
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.listener.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    self?.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
        guard let port = listener.port,
              let url = URL(string: "http://127.0.0.1:\(port.rawValue)/") else { throw URLError(.badURL) }
        return url
    }

    deinit { listener.cancel() }
}
#endif
