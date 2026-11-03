#if os(macOS)
import Foundation

struct DeviceFrameSource: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL

    static func decode(_ data: Data, baseURL: URL) throws -> [Self] {
        struct Grid: Decodable {
            struct Device: Decodable {
                struct Helper: Decodable { let streamUrl: String }
                let device: String?
                let name: String?
                let helper: Helper?
                let streamMjpegEndpoint: String?
            }
            let devices: [Device]
        }
        return try JSONDecoder().decode(Grid.self, from: data).devices.compactMap { device in
            guard let id = device.device, let path = device.helper?.streamUrl ?? device.streamMjpegEndpoint,
                  let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
                  url.scheme == baseURL.scheme, url.host == baseURL.host, url.port == baseURL.port,
                  url.user == nil, url.password == nil else { return nil }
            return Self(id: id, name: device.name ?? id, url: url)
        }
    }
}

/// Reads one complete multipart JPEG, then cancels the stream. No WebKit/GPU snapshot is involved.
enum DeviceFrameCapture {
    struct Parser {
        private var header = Data()
        private var length: Int?
        private var image = Data()

        mutating func append(_ byte: UInt8) throws -> Data? {
            if let length {
                image.append(byte)
                return image.count == length ? image : nil
            }
            header.append(byte)
            guard header.count <= 16_384 else { throw LocalDeviceBridge.failure("Invalid device stream header.") }
            if header.suffix(4) == Data([13, 10, 13, 10]) {
                let fields = String(decoding: header, as: UTF8.self).components(separatedBy: "\r\n")
                length = fields.compactMap { field -> Int? in
                    let parts = field.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2, parts[0].lowercased() == "content-length" else { return nil }
                    return Int(parts[1].trimmingCharacters(in: .whitespaces))
                }.first
                guard let length, (1...10_485_760).contains(length) else {
                    throw LocalDeviceBridge.failure("The device stream did not provide a bounded frame.")
                }
                image.reserveCapacity(length)
            }
            return nil
        }
    }

    static func jpeg(from url: URL) async throws -> Data {
        try await DeviceFrameRequest(url: url).load()
    }
}

/// Foundation demultiplexes live MJPEG into repeated image/jpeg responses. AsyncBytes
/// can wait indefinitely for their terminal response, so consume a single frame via its delegate.
private final class DeviceFrameRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let url: URL
    private let queue = OperationQueue()
    // All mutable state is confined to this serial delegate queue, including cancellation.
    private var session: URLSession?
    private var continuation: CheckedContinuation<Data, Error>?
    private var cancelled = false
    private var isJPEG = false
    private var image = Data()
    private var expectedLength: Int64 = -1
    private var parser = DeviceFrameCapture.Parser()

    init(url: URL) {
        self.url = url
        queue.maxConcurrentOperationCount = 1
        super.init()
    }

    func load() async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.addOperation {
                    if self.cancelled { continuation.resume(throwing: CancellationError()); return }
                    self.continuation = continuation
                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.timeoutIntervalForResource = 15
                    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: self.queue)
                    self.session = session
                    session.dataTask(with: URLRequest(url: self.url, cachePolicy: .reloadIgnoringLocalCacheData,
                                                     timeoutInterval: 10)).resume()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 15) { [weak self] in
                        guard let self else { return }
                        self.queue.addOperation { self.finish(.failure(URLError(.timedOut))) }
                    }
                }
            }
        } onCancel: {
            self.queue.addOperation { self.cancelled = true; self.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        session?.invalidateAndCancel()
        session = nil
        continuation.resume(with: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              response.url?.scheme == url.scheme, response.url?.host == url.host, response.url?.port == url.port else {
            completionHandler(.cancel)
            finish(.failure(URLError(.badServerResponse)))
            return
        }
        isJPEG = response.mimeType == "image/jpeg"
        expectedLength = response.expectedContentLength
        image = Data()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard continuation != nil else { return }
        if isJPEG {
            image.append(data)
            if image.count > 10_485_760 { finish(.failure(URLError(.dataLengthExceedsMaximum))) }
            else if (expectedLength > 0 && image.count >= expectedLength)
                || (expectedLength < 0 && image.suffix(2) == Data([255, 217])) {
                finish(.success(image))
            }
        } else {
            do { for byte in data { if let frame = try parser.append(byte) { finish(.success(frame)); return } } }
            catch { finish(.failure(error)) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(.failure(error ?? URLError(.networkConnectionLost)))
    }
}
#endif
