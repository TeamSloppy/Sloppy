import Foundation

/// A single image-to-canvas transform. Stored annotations never use viewport coordinates.
struct ChatImageViewport: Equatable {
    private(set) var zoom: CGFloat = 1
    private(set) var pan: CGSize = .zero
    static let zoomRange: ClosedRange<CGFloat> = 0.1...32

    func frame(imageSize: CGSize, canvasSize: CGSize) -> CGRect {
        let fit = ChatImageRegion.imageFrame(imageSize: imageSize, canvasSize: canvasSize)
        let size = CGSize(width: fit.width * zoom, height: fit.height * zoom)
        let offset = boundedPan(pan, imageSize: size, canvasSize: canvasSize)
        return CGRect(x: (canvasSize.width - size.width) / 2 + offset.width,
                      y: (canvasSize.height - size.height) / 2 + offset.height,
                      width: size.width, height: size.height)
    }

    mutating func setZoom(_ value: CGFloat, imageSize: CGSize, canvasSize: CGSize) {
        let old = zoom
        zoom = value.isFinite ? min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, value)) : 1
        pan = CGSize(width: pan.width * zoom / old, height: pan.height * zoom / old)
        constrain(imageSize: imageSize, canvasSize: canvasSize)
    }

    mutating func move(by delta: CGSize, imageSize: CGSize, canvasSize: CGSize) {
        pan.width += delta.width
        pan.height += delta.height
        constrain(imageSize: imageSize, canvasSize: canvasSize)
    }

    mutating func reset() { zoom = 1; pan = .zero }

    mutating func constrain(imageSize: CGSize, canvasSize: CGSize) {
        let fit = ChatImageRegion.imageFrame(imageSize: imageSize, canvasSize: canvasSize)
        pan = boundedPan(pan, imageSize: CGSize(width: fit.width * zoom, height: fit.height * zoom), canvasSize: canvasSize)
    }

    private func boundedPan(_ value: CGSize, imageSize: CGSize, canvasSize: CGSize) -> CGSize {
        let x = max(0, (imageSize.width - canvasSize.width) / 2)
        let y = max(0, (imageSize.height - canvasSize.height) / 2)
        return CGSize(width: min(x, max(-x, value.width)), height: min(y, max(-y, value.height)))
    }
}
