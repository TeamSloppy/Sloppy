import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import SloppyFeatureChat

@Suite("Image viewer markup and export")
struct ChatImageMarkupTests {
    @Test func strokesKeepOriginalCoordinatesAcrossViewportChanges() throws {
        let image = CGSize(width: 1600, height: 900)
        let canvas = CGSize(width: 800, height: 600)
        var viewport = ChatImageViewport()
        viewport.setZoom(3, imageSize: image, canvasSize: canvas)
        viewport.move(by: CGSize(width: -100, height: 60), imageSize: image, canvasSize: canvas)
        let frame = viewport.frame(imageSize: image, canvasSize: canvas)
        let start = CGPoint(x: frame.minX + frame.width * 0.3, y: frame.minY + frame.height * 0.4)
        var stroke = ChatImageStroke(kind: .arrow, ink: .coral, width: 0.004, start: start, frame: frame)
        stroke.append(CGPoint(x: frame.maxX + 100, y: frame.minY - 100), in: frame)
        #expect(abs(try #require(stroke.points.first).x - 0.3) < 0.00001)
        #expect(abs(try #require(stroke.points.first).y - 0.4) < 0.00001)
        #expect(stroke.points.last?.x == 1)
        #expect(stroke.points.last?.y == 0)
        viewport.reset()
        let reset = viewport.frame(imageSize: image, canvasSize: canvas)
        #expect(stroke.points.first?.position(in: reset) == CGPoint(x: 240, y: 255))
        let data = try JSONEncoder().encode(stroke)
        #expect(try JSONDecoder().decode(ChatImageStroke.self, from: data) == stroke)
    }

    @Test @MainActor func exportRendersPixelsNotesAndUploadWithoutChangingOriginal() throws {
        let context = try #require(CGContext(data: nil, width: 320, height: 160, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 160))
        let image = try #require(context.makeImage())
        let frame = CGRect(x: 0, y: 0, width: 320, height: 160)
        var stroke = ChatImageStroke(kind: .pen, ink: .coral, width: 0.025, start: CGPoint(x: 50, y: 80), frame: frame)
        stroke.append(CGPoint(x: 270, y: 80), in: frame)
        let png = try ChatImageExport.png(image: image, strokes: [stroke])
        let original = try ChatImageExport.png(image: image, strokes: [])
        #expect(png != original)
        let note = ChatImageAnnotation(region: .init(x: 0.2, y: 0.3, width: 0.2, height: 0.1), comment: "Fix this button")
        let annotated = try ChatImageExport.png(image: image, strokes: [stroke], annotations: [note])
        let source = try #require(CGImageSourceCreateWithData(annotated as CFData, nil))
        let result = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(result.width == 320)
        #expect(result.height > 160)
        let pixels = try #require(CGContext(data: nil, width: 320, height: 160, bitsPerComponent: 8,
            bytesPerRow: 1280, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let marked = try #require(ChatImageExport.decode(png))
        pixels.draw(marked, in: frame)
        let bytes = try #require(pixels.data).assumingMemoryBound(to: UInt8.self)
        #expect(bytes[(80 * 320 + 160) * 4] > 180)
        #expect(bytes[(80 * 320 + 160) * 4 + 1] < 120)

        var attachment = ChatComposerAttachment(name: "sample.jpg", mimeType: "image/jpeg", data: original, annotations: [note])
        attachment.markup = ChatImageMarkup(strokes: [stroke], pngData: png)
        #expect(attachment.data == original)
        #expect(attachment.upload.name == "sample.png")
        #expect(attachment.upload.mimeType == "image/png")
        #expect(attachment.upload.contentBase64 == png.base64EncodedString())
        #expect(attachment.messageAttachment.previewData == png)
        let content = ChatComposerQuote.messageContent("Review", quotes: [], attachments: [attachment])
        #expect(content.contains("Fix this button"))

        if let directory = ProcessInfo.processInfo.environment["SLOPPY_ANNOTATION_SCREENSHOTS"] {
            try annotated.write(to: URL(fileURLWithPath: directory).appendingPathComponent("viewer-export.png"))
        }
    }

    #if os(macOS)
    @Test func downloadAllArchiveExtractsOriginalPNGAndStructuredNotes() throws {
        let original = Data("original image bytes".utf8)
        let annotated = Data("annotated image bytes".utf8)
        let notes = try ChatImageExport.notes(annotations: [
            .init(region: .init(x: 0.25, y: 0.5), comment: "A note", browserSource: .init(
                url: URL(string: "https://example.com/page")!, title: "Page", selector: "#button"))
        ], strokes: [])
        let archive = ChatImageArchive.make(original: original, originalExtension: "png", annotated: annotated, notes: notes)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("image.zip")
        try archive.write(to: url)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", url.path, root.appendingPathComponent("out").path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let output = root.appendingPathComponent("out")
        #expect(try Data(contentsOf: output.appendingPathComponent("original.png")) == original)
        #expect(try Data(contentsOf: output.appendingPathComponent("annotated.png")) == annotated)
        #expect(try Data(contentsOf: output.appendingPathComponent("annotations.json")) == notes)
        let json = try #require(JSONSerialization.jsonObject(with: notes) as? [String: Any])
        let values = try #require(json["annotations"] as? [[String: Any]])
        #expect(values.first?["comment"] as? String == "A note")
        #expect(values.first?["x"] as? Double == 0.25)
        #expect(values.first?["selector"] as? String == "#button")
    }
    #endif
}
