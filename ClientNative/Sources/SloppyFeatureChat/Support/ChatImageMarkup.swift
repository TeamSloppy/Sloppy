import Foundation
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Editable strokes use the same top-left, normalized image space as comments.
public struct ChatImageStroke: Identifiable, Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable, CaseIterable { case pen, arrow, rectangle }
    public enum Ink: String, Sendable, Codable, CaseIterable {
        case coral, mint, paper, charcoal

        var color: Color {
            switch self {
            case .coral: Color(red: 217 / 255, green: 78 / 255, blue: 52 / 255)
            case .mint: ChatAnnotationStyle.mint
            case .paper: ChatAnnotationStyle.paper
            case .charcoal: ChatAnnotationStyle.ink
            }
        }
    }

    public struct Point: Sendable, Equatable, Codable {
        public let x: Double
        public let y: Double

        init(_ point: CGPoint, in frame: CGRect) {
            x = min(1, max(0, Double((point.x - frame.minX) / frame.width)))
            y = min(1, max(0, Double((point.y - frame.minY) / frame.height)))
        }

        func position(in frame: CGRect) -> CGPoint {
            CGPoint(x: frame.minX + x * frame.width, y: frame.minY + y * frame.height)
        }
    }

    public let id: UUID
    public let kind: Kind
    public let ink: Ink
    public let width: Double
    public var points: [Point]

    init(kind: Kind, ink: Ink, width: Double, start: CGPoint, frame: CGRect) {
        id = UUID()
        self.kind = kind
        self.ink = ink
        self.width = width
        points = [Point(start, in: frame)]
    }

    mutating func append(_ point: CGPoint, in frame: CGRect) {
        let next = Point(point, in: frame)
        if kind == .pen {
            if points.last != next { points.append(next) }
        } else {
            points = Array(points.prefix(1)) + [next]
        }
    }

    func path(in frame: CGRect) -> Path {
        var path = Path()
        guard let first = points.first?.position(in: frame) else { return path }
        let last = points.last?.position(in: frame) ?? first
        if kind == .rectangle {
            path.addRect(CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                                width: abs(last.x - first.x), height: abs(last.y - first.y)))
        } else {
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point.position(in: frame)) }
            if points.count == 1 { path.addLine(to: CGPoint(x: first.x + 0.01, y: first.y)) }
            if kind == .arrow, first != last {
                let angle = atan2(last.y - first.y, last.x - first.x)
                let length = max(width * frame.width * 5, frame.width * 0.018)
                for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                    path.move(to: last)
                    path.addLine(to: CGPoint(x: last.x - cos(angle + offset) * length,
                                            y: last.y - sin(angle + offset) * length))
                }
            }
        }
        return path
    }
}

public struct ChatImageMarkup: Sendable, Equatable {
    public let strokes: [ChatImageStroke]
    public let pngData: Data
}

struct ChatImageMarkupLayer: View {
    let strokes: [ChatImageStroke]
    let frame: CGRect

    var body: some View {
        ForEach(strokes) { stroke in
            stroke.path(in: frame)
                .stroke(stroke.ink.color, style: StrokeStyle(lineWidth: max(1, stroke.width * frame.width),
                                                           lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum ChatImageExport {
    /// ImageIO applies EXIF orientation once, so display, coordinates and exported pixels agree.
    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096,
        ] as CFDictionary)
    }

    @MainActor
    static func png(image: CGImage, strokes: [ChatImageStroke], annotations: [ChatImageAnnotation] = []) throws -> Data {
        let size = CGSize(width: image.width, height: image.height)
        let frame = CGRect(origin: .zero, size: size)
        let renderer = ImageRenderer(content: VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)
                ChatImageMarkupLayer(strokes: strokes, frame: frame)
                ForEach(Array(annotations.enumerated()), id: \.element.id) { index, note in
                    Rectangle().stroke(ChatAnnotationStyle.mint, lineWidth: max(2, size.width * 0.002))
                        .frame(width: max(2, note.region.width * size.width), height: max(2, note.region.height * size.height))
                        .offset(x: note.region.x * size.width, y: note.region.y * size.height)
                    Text("\(index + 1)").font(.system(size: max(16, size.width * 0.016), weight: .bold))
                        .foregroundStyle(ChatAnnotationStyle.ink).padding(6)
                        .background(ChatAnnotationStyle.mint, in: Circle())
                        .position(x: note.region.x * size.width, y: note.region.y * size.height)
                }
            }.frame(width: size.width, height: size.height).clipped()
            if !annotations.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(annotations.enumerated()), id: \.element.id) { index, note in
                        Text("\(index + 1). \(note.comment.isEmpty ? note.region.coordinateDescription : note.comment)")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.system(size: max(16, size.width * 0.015)))
                .foregroundStyle(ChatAnnotationStyle.ink).padding(max(16, size.width * 0.02))
                .frame(width: size.width, alignment: .leading).background(ChatAnnotationStyle.paper)
            }
        })
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }

    static func notes(annotations: [ChatImageAnnotation], strokes: [ChatImageStroke]) throws -> Data {
        struct Note: Encodable {
            let number: Int
            let x, y, width, height: Double
            let comment: String
            let pageURL: URL?
            let pageTitle: String?
            let selector: String?
        }
        struct Manifest: Encodable {
            let version = 1
            let coordinates = "normalized, top-left origin, EXIF-oriented original image"
            let annotations: [Note]
            let strokes: [ChatImageStroke]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Manifest(annotations: annotations.enumerated().map { index, note in
            Note(number: index + 1, x: note.region.x, y: note.region.y, width: note.region.width,
                 height: note.region.height, comment: note.comment, pageURL: note.browserSource?.url,
                 pageTitle: note.browserSource?.title, selector: note.browserSource?.selector)
        }, strokes: strokes))
    }
}

struct ChatImageExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.data]
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
