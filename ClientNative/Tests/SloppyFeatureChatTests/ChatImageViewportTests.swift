import Foundation
import Testing
@testable import SloppyFeatureChat

@Suite("Image annotation viewport")
struct ChatImageViewportTests {
    @Test(arguments: [CGFloat(1), 2, 4, 8])
    func originalCoordinatesSurviveZoomPanAndResize(zoom: CGFloat) throws {
        let image = CGSize(width: 1600, height: 900)
        var viewport = ChatImageViewport()
        for canvas in [CGSize(width: 800, height: 700), CGSize(width: 1000, height: 400)] {
            viewport.setZoom(zoom, imageSize: image, canvasSize: canvas)
            viewport.move(by: CGSize(width: 70, height: -35), imageSize: image, canvasSize: canvas)
            let frame = viewport.frame(imageSize: image, canvasSize: canvas)
            let point = CGPoint(x: frame.minX + frame.width * 0.512, y: frame.minY + frame.height * 0.332)
            let region = try #require(ChatImageRegion.selection(from: point, to: point, imageFrame: frame))
            #expect(abs(region.x - 0.512) < 0.000001)
            #expect(abs(region.y - 0.332) < 0.000001)
            let end = CGPoint(x: frame.minX + frame.width * 0.2, y: frame.minY + frame.height * 0.1)
            let area = try #require(ChatImageRegion.selection(from: point, to: end, imageFrame: frame))
            #expect(abs(area.x - 0.2) < 0.000001)
            #expect(abs(area.width - 0.312) < 0.000001)
            #expect(abs(area.height - 0.232) < 0.000001)
        }
        viewport.reset()
        #expect(viewport.zoom == 1)
        #expect(viewport.pan == .zero)
    }

    @Test func fitRejectsLetterboxAndClampsPanAndZoom() {
        let image = CGSize(width: 800, height: 400)
        let canvas = CGSize(width: 800, height: 800)
        var viewport = ChatImageViewport()
        let fit = viewport.frame(imageSize: image, canvasSize: canvas)
        #expect(fit == CGRect(x: 0, y: 200, width: 800, height: 400))
        #expect(ChatImageRegion.selection(from: CGPoint(x: 100, y: 100), to: .zero, imageFrame: fit) == nil)
        viewport.setZoom(1000, imageSize: image, canvasSize: canvas)
        #expect(viewport.zoom == ChatImageViewport.zoomRange.upperBound)
        viewport.move(by: CGSize(width: 100000, height: -100000), imageSize: image, canvasSize: canvas)
        let moved = viewport.frame(imageSize: image, canvasSize: canvas)
        #expect(moved.minX == 0)
        #expect(moved.maxY == canvas.height)
        viewport.setZoom(-20, imageSize: image, canvasSize: canvas)
        #expect(viewport.zoom == ChatImageViewport.zoomRange.lowerBound)
        #expect(viewport.pan == .zero)
        viewport.setZoom(.nan, imageSize: image, canvasSize: canvas)
        #expect(viewport.zoom == 1)
    }
}
