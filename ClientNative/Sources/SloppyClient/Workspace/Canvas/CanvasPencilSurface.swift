import SwiftUI

enum CanvasInputTool: String, CaseIterable, Identifiable {
    case select, region, pencil, eraser

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .select: "arrow.up.left"
        case .region: "viewfinder"
        case .pencil: "pencil.tip"
        case .eraser: "eraser"
        }
    }
}

#if os(iOS)
import PencilKit
import UIKit

@MainActor
struct CanvasPencilSurface: UIViewRepresentable {
    let drawingData: Data?
    let tool: CanvasInputTool
    let onDrawingChanged: @MainActor (Data, Data?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChanged: onDrawingChanged)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView(frame: .zero)
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = .pencilOnly
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        context.coordinator.install(drawingData, in: canvas)
        updateTool(tool, in: canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.install(drawingData, in: canvas)
        updateTool(tool, in: canvas)
    }

    private func updateTool(_ tool: CanvasInputTool, in canvas: PKCanvasView) {
        canvas.isUserInteractionEnabled = tool == .pencil || tool == .eraser
        switch tool {
        case .select, .region:
            break
        case .pencil:
            canvas.tool = PKInkingTool(.pen, color: .label, width: 3)
        case .eraser:
            canvas.tool = PKEraserTool(.vector)
        }
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let onDrawingChanged: @MainActor (Data, Data?) -> Void
        var installedData: Data?
        var saveTask: Task<Void, Never>?

        init(onDrawingChanged: @escaping @MainActor (Data, Data?) -> Void) {
            self.onDrawingChanged = onDrawingChanged
        }

        func install(_ data: Data?, in canvas: PKCanvasView) {
            guard data != installedData else { return }
            installedData = data
            guard let data, let drawing = try? PKDrawing(data: data) else { return }
            canvas.drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let drawing = canvasView.drawing
            let data = drawing.dataRepresentation()
            let canvasSize = canvasView.bounds.size
            installedData = data
            saveTask?.cancel()
            saveTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                let preview = drawing.image(
                    from: CGRect(origin: .zero, size: canvasSize),
                    scale: 1
                ).pngData()
                onDrawingChanged(data, preview)
            }
        }
    }
}
#else
@MainActor
struct CanvasPencilSurface: View {
    let drawingData: Data?
    let tool: CanvasInputTool
    let onDrawingChanged: @MainActor (Data, Data?) -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
    }
}
#endif
