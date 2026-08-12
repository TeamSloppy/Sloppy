import Foundation
import SloppyClientCore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
struct CanvasWorkspaceEditorView: View {
    let viewModel: CanvasWorkspaceViewModel

    @State private var inputTool: CanvasInputTool = .select
    @State private var prompt = ""
    @State private var zoom: CGFloat = 1
    @State private var canvasScrollPosition = ScrollPosition()
    @State private var viewport = CanvasViewport.zero
    @State private var pinchContext: CanvasPinchContext?
    @State private var cursorLocation: CGPoint?
    @State private var regionStart: CGPoint?
    @State private var regionEnd: CGPoint?
    @State private var regionRequest: CanvasRegionRequest?
    @State private var regionCaptureHandle = CanvasRegionCaptureHandle()

    private let canvasSize = CGSize(width: 3200, height: 2400)
    private let minimumZoom: CGFloat = 0.25
    private let maximumZoom: CGFloat = 2.5

    private var effectiveZoom: CGFloat {
        zoom
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            nativeCanvas

            CanvasRegionCaptureSource(handle: regionCaptureHandle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            if inputTool == .region || regionRequest != nil {
                regionSelectionOverlay
            }

            floatingCanvasControls

            if viewModel.isMiniMapPresented {
                CanvasWorkspaceMiniMap(
                    document: viewModel.document,
                    canvasSize: canvasSize,
                    viewport: viewport,
                    zoom: effectiveZoom
                )
                    .frame(width: 190, height: 132)
                    .padding(.trailing, 16)
                    .padding(.top, 72)
                    .transition(.opacity)
            }
        }
        .safeAreaInset(edge: .leading, spacing: 0) {
            if viewModel.isLayersPanelPresented {
                CanvasWorkspaceLayersPanel(viewModel: viewModel)
                    .frame(width: 280)
                    .padding(.leading, 12)
                    .padding(.vertical, 12)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .trailing, spacing: 0) {
            if viewModel.isInspectorPresented {
                CanvasWorkspaceInspector(viewModel: viewModel, prompt: $prompt)
                    .frame(width: 350)
                    .padding(.trailing, 12)
                    .padding(.vertical, 12)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !viewModel.isInspectorPresented {
                compactComposer
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            editorToolbar
        }
        .animation(.snappy, value: viewModel.isInspectorPresented)
        .animation(.snappy, value: viewModel.isLayersPanelPresented)
        .animation(.easeInOut(duration: 0.18), value: viewModel.isMiniMapPresented)
        .accessibilityIdentifier("native-canvas-workspace-editor")
    }

    @ViewBuilder
    private var nativeCanvas: some View {
        #if os(macOS)
        scrollableCanvas
            .background {
                CanvasTrackpadZoomSource(onMagnify: handleTrackpadMagnification)
            }
        #else
        scrollableCanvas
            .simultaneousGesture(zoomGesture)
        #endif
    }

    private var scrollableCanvas: some View {
        ScrollView([.horizontal, .vertical]) {
            canvasContent
                .frame(width: canvasSize.width, height: canvasSize.height)
                .scaleEffect(effectiveZoom, anchor: .topLeading)
                .frame(
                    width: canvasSize.width * effectiveZoom,
                    height: canvasSize.height * effectiveZoom,
                    alignment: .topLeading
                )
        }
        .scrollPosition($canvasScrollPosition)
        .onScrollGeometryChange(for: CanvasViewport.self) { geometry in
            CanvasViewport(offset: geometry.contentOffset, size: geometry.containerSize)
        } action: { _, newValue in
            viewport = newValue
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                cursorLocation = location
            case .ended:
                cursorLocation = nil
            }
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(inputTool != .select)
        .background(Color.secondary.opacity(0.055))
    }

    private var canvasContent: some View {
        ZStack(alignment: .topLeading) {
                CanvasWorkspaceGrid()
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectedElementID = nil
                    }

                CanvasWorkspaceConnections(
                    elements: viewModel.document?.elements ?? [],
                    connections: viewModel.document?.connections ?? []
                )
                .frame(width: canvasSize.width, height: canvasSize.height)

                ForEach(visibleElements.sorted { $0.zIndex < $1.zIndex }) { element in
                    CanvasWorkspaceElementView(
                        element: element,
                        html: widgetHTML(for: element),
                        isSelected: viewModel.selectedElementID == element.id,
                        onSelect: { viewModel.selectedElementID = element.id },
                        onUpdate: { updated in
                            Task { await viewModel.updateElement(updated) }
                        }
                    )
                    .frame(width: element.bounds.width, height: element.bounds.height)
                    .rotationEffect(.degrees(element.rotation))
                    .position(
                        x: element.bounds.x + element.bounds.width / 2,
                        y: element.bounds.y + element.bounds.height / 2
                    )
                    .zIndex(Double(element.zIndex))
                }

                CanvasPencilSurface(
                    drawingData: viewModel.pencilDrawingData,
                    tool: inputTool,
                    onDrawingChanged: { data, previewPNG in
                        Task { await viewModel.savePencilDrawing(data, previewPNG: previewPNG) }
                    }
                )
                .frame(width: canvasSize.width, height: canvasSize.height)
                .allowsHitTesting(inputTool == .pencil || inputTool == .eraser)
                .accessibilityLabel("Apple Pencil drawing surface")
                .zIndex(inputTool == .pencil || inputTool == .eraser ? 1_000_000 : -1)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let context: CanvasPinchContext
                if let pinchContext {
                    context = pinchContext
                } else {
                    let focalPoint = value.startLocation
                    context = CanvasPinchContext(
                        baseZoom: zoom,
                        canvasPoint: canvasPoint(at: focalPoint, zoom: zoom),
                        focalPoint: focalPoint
                    )
                    pinchContext = context
                }
                applyZoom(
                    clampedZoom(context.baseZoom * value.magnification),
                    around: context.focalPoint,
                    canvasPoint: context.canvasPoint
                )
            }
            .onEnded { value in
                if let context = pinchContext {
                    applyZoom(
                        clampedZoom(context.baseZoom * value.magnification),
                        around: context.focalPoint,
                        canvasPoint: context.canvasPoint
                    )
                }
                pinchContext = nil
            }
    }

    #if os(macOS)
    private func handleTrackpadMagnification(_ event: CanvasTrackpadMagnification) {
        switch event.phase {
        case .began:
            pinchContext = CanvasPinchContext(
                baseZoom: zoom,
                canvasPoint: canvasPoint(at: event.location, zoom: zoom),
                focalPoint: event.location
            )
        case .changed:
            if pinchContext == nil {
                pinchContext = CanvasPinchContext(
                    baseZoom: zoom,
                    canvasPoint: canvasPoint(at: event.location, zoom: zoom),
                    focalPoint: event.location
                )
            }
            guard let context = pinchContext else { return }
            applyZoom(
                clampedZoom(context.baseZoom * event.magnification),
                around: context.focalPoint,
                canvasPoint: context.canvasPoint
            )
        case .ended:
            if let context = pinchContext {
                applyZoom(
                    clampedZoom(context.baseZoom * event.magnification),
                    around: context.focalPoint,
                    canvasPoint: context.canvasPoint
                )
            }
            pinchContext = nil
        }
    }
    #endif

    private var floatingCanvasControls: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                CanvasInputToolPill(selection: $inputTool)
                Spacer()
                CanvasZoomPill(
                    zoom: effectiveZoom,
                    canZoomOut: zoom > minimumZoom,
                    canZoomIn: zoom < maximumZoom,
                    onZoomOut: { setZoom(zoom - 0.15) },
                    onReset: { setZoom(1) },
                    onZoomIn: { setZoom(zoom + 0.15) }
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .allowsHitTesting(true)
    }

    private var regionSelectionOverlay: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(regionSelectionGesture)

                if let rect = activeRegionRect {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                        .frame(width: rect.width, height: rect.height)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                        }
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }

                if let request = regionRequest {
                    CanvasRegionPromptCard(
                        request: request,
                        isSending: viewModel.isSendingPrompt,
                        onChange: { regionRequest = $0 },
                        onCancel: cancelRegionRequest,
                        onSend: sendRegionRequest
                    )
                    .frame(width: min(360, max(280, proxy.size.width - 32)))
                    .position(regionPromptPosition(for: request.rect, in: proxy.size))
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
        }
        .animation(.snappy(duration: 0.18), value: regionRequest != nil)
        .accessibilityIdentifier("canvas-region-selection-overlay")
    }

    private var regionSelectionGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                guard regionRequest == nil else { return }
                if regionStart == nil {
                    regionStart = value.startLocation
                }
                regionEnd = value.location
            }
            .onEnded { value in
                guard regionRequest == nil else { return }
                let rect = normalizedRegionRect(from: value.startLocation, to: value.location)
                guard rect.width >= 32, rect.height >= 32 else {
                    regionStart = nil
                    regionEnd = nil
                    return
                }
                let png = regionCaptureHandle.pngData(for: rect.insetBy(dx: 2, dy: 2))
                regionRequest = CanvasRegionRequest(rect: rect, pngData: png)
            }
    }

    private var activeRegionRect: CGRect? {
        if let request = regionRequest { return request.rect }
        guard let regionStart, let regionEnd else { return nil }
        return normalizedRegionRect(from: regionStart, to: regionEnd)
    }

    private func normalizedRegionRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func regionPromptPosition(for rect: CGRect, in size: CGSize) -> CGPoint {
        let cardWidth = min(360, max(280, size.width - 32))
        let x = min(size.width - cardWidth / 2 - 16, max(cardWidth / 2 + 16, rect.midX))
        let preferredY = rect.maxY + 118
        let fallbackY = rect.minY - 118
        return CGPoint(x: x, y: preferredY + 116 < size.height ? preferredY : max(116, fallbackY))
    }

    private func cancelRegionRequest() {
        regionRequest = nil
        regionStart = nil
        regionEnd = nil
    }

    private func sendRegionRequest() {
        guard let request = regionRequest,
              request.pngData != nil,
              !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            await viewModel.sendPrompt(
                request.prompt,
                regionAction: request.action,
                regionPNG: request.pngData
            )
            cancelRegionRequest()
            inputTool = .select
        }
    }

    private func setZoom(_ value: CGFloat) {
        let focalPoint = cursorLocation ?? CGPoint(
            x: viewport.size.width / 2,
            y: viewport.size.height / 2
        )
        let retainedCanvasPoint = canvasPoint(at: focalPoint, zoom: zoom)
        withAnimation(.snappy(duration: 0.18)) {
            applyZoom(clampedZoom(value), around: focalPoint, canvasPoint: retainedCanvasPoint)
        }
    }

    private func canvasPoint(at focalPoint: CGPoint, zoom: CGFloat) -> CGPoint {
        CGPoint(
            x: (viewport.offset.x + focalPoint.x) / zoom,
            y: (viewport.offset.y + focalPoint.y) / zoom
        )
    }

    private func applyZoom(_ newZoom: CGFloat, around focalPoint: CGPoint, canvasPoint: CGPoint) {
        zoom = newZoom
        let requestedOffset = CGPoint(
            x: canvasPoint.x * newZoom - focalPoint.x,
            y: canvasPoint.y * newZoom - focalPoint.y
        )
        canvasScrollPosition.scrollTo(point: clampedScrollOffset(requestedOffset, zoom: newZoom))
    }

    private func clampedScrollOffset(_ offset: CGPoint, zoom: CGFloat) -> CGPoint {
        let maximumX = max(0, canvasSize.width * zoom - viewport.size.width)
        let maximumY = max(0, canvasSize.height * zoom - viewport.size.height)
        return CGPoint(
            x: min(maximumX, max(0, offset.x)),
            y: min(maximumY, max(0, offset.y))
        )
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(maximumZoom, max(minimumZoom, value))
    }

    private var visibleElements: [CanvasWorkspaceElement] {
        (viewModel.document?.elements ?? []).filter { $0.id != "native-pencil-drawing" }
    }

    private func widgetHTML(for element: CanvasWorkspaceElement) -> String? {
        guard let id = element.data["artifactId"]?.stringValue else { return nil }
        return viewModel.widgetHTML[id]
    }

    private var editorToolbar: some View {
        HStack(spacing: 10) {
            Text(viewModel.title)
                .font(.headline)
                .lineLimit(1)

            Text("r\(viewModel.document?.revision ?? 0)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Menu {
                Button("Sticky Note", systemImage: "note.text") { Task { await viewModel.addElement(.sticky) } }
                Button("Text", systemImage: "textformat") { Task { await viewModel.addElement(.text) } }
                Button("Shape", systemImage: "square.on.circle") { Task { await viewModel.addElement(.shape) } }
                Button("Frame", systemImage: "rectangle.dashed") { Task { await viewModel.addElement(.frame) } }
            } label: {
                Label("Add", systemImage: "plus")
            }

            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await viewModel.deleteSelectedElement() }
            }
            .disabled(viewModel.selectedElementID == nil)
            .labelStyle(.iconOnly)

            Spacer()

            Text(viewModel.editorStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button {
                viewModel.isMiniMapPresented.toggle()
            } label: {
                Label("Mini Map", systemImage: "map")
            }
            .labelStyle(.iconOnly)
            .help(viewModel.isMiniMapPresented ? "Hide Mini Map" : "Show Mini Map")
            .accessibilityLabel(viewModel.isMiniMapPresented ? "Hide Mini Map" : "Show Mini Map")

            Button {
                viewModel.isLayersPanelPresented.toggle()
            } label: {
                Label("Layers", systemImage: "sidebar.left")
            }
            .labelStyle(.iconOnly)
            .help(viewModel.isLayersPanelPresented ? "Hide Layers" : "Show Layers")
            .accessibilityLabel(viewModel.isLayersPanelPresented ? "Hide Layers" : "Show Layers")

            Button {
                viewModel.isInspectorPresented.toggle()
            } label: {
                Label("Agent Session", systemImage: "sidebar.right")
            }
            .labelStyle(.iconOnly)
            .help(viewModel.isInspectorPresented ? "Hide Agent Session" : "Show Agent Session")
            .accessibilityLabel(viewModel.isInspectorPresented ? "Hide Agent Session" : "Show Agent Session")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var compactComposer: some View {
        HStack(spacing: 10) {
            agentPicker
            TextField("Ask an agent to build on this canvas…", text: $prompt, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .onSubmit(sendPrompt)
            Button(action: sendPrompt) {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSendingPrompt)
        }
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(12)
        .frame(maxWidth: 760)
    }

    private var agentPicker: some View {
        Picker("Agent", selection: Binding(
            get: { viewModel.selectedAgentID ?? "" },
            set: { viewModel.selectAgent($0) }
        )) {
            ForEach(viewModel.agents) { agent in
                Text(agent.displayName).tag(agent.id)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 180)
    }

    private func sendPrompt() {
        let content = prompt
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        prompt = ""
        Task { await viewModel.sendPrompt(content) }
    }
}

private struct CanvasViewport: Equatable {
    var offset: CGPoint
    var size: CGSize

    static let zero = CanvasViewport(offset: .zero, size: .zero)
}

private struct CanvasPinchContext {
    var baseZoom: CGFloat
    var canvasPoint: CGPoint
    var focalPoint: CGPoint
}

private struct CanvasRegionRequest {
    var rect: CGRect
    var pngData: Data?
    var action: CanvasRegionAgentAction = .explain
    var prompt = ""
}

private struct CanvasRegionPromptCard: View {
    let request: CanvasRegionRequest
    let isSending: Bool
    let onChange: (CanvasRegionRequest) -> Void
    let onCancel: () -> Void
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ask about selection", systemImage: "viewfinder")
                    .font(.headline)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Cancel canvas selection")
            }

            HStack(spacing: 4) {
                ForEach(CanvasRegionAgentAction.allCases) { action in
                    Button {
                        var updated = request
                        updated.action = action
                        onChange(updated)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                            .font(.callout.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(request.action == action ? Color.white : Color.primary)
                    .background(
                        request.action == action ? Color.accentColor : Color.secondary.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .accessibilityAddTraits(request.action == action ? .isSelected : [])
                }
            }

            TextField("What should the agent focus on?", text: Binding(
                get: { request.prompt },
                set: { value in
                    var updated = request
                    updated.prompt = value
                    onChange(updated)
                }
            ), axis: .vertical)
            .lineLimit(2...5)
            .textFieldStyle(.plain)
            .padding(10)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .onSubmit(onSend)

            HStack {
                Label(
                    request.pngData == nil ? "Could not capture selection" : "canvas-selection.png",
                    systemImage: request.pngData == nil ? "exclamationmark.triangle" : "photo"
                )
                .font(.caption)
                .foregroundStyle(request.pngData == nil ? Color.orange : Color.secondary)

                Spacer()

                Button(action: onSend) {
                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Send", systemImage: "arrow.up")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || request.pngData == nil
                        || isSending
                )
            }
        }
        .padding(14)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.20), radius: 20, y: 8)
        .accessibilityIdentifier("canvas-region-prompt")
    }
}

#if os(iOS)
@MainActor
private final class CanvasRegionCaptureHandle {
    weak var view: UIView?

    func pngData(for rect: CGRect) -> Data? {
        guard let view, let window = view.window, rect.width > 1, rect.height > 1 else { return nil }
        let rectInWindow = view.convert(rect, to: window)
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let source = image.cgImage else { return nil }
        let scale = image.scale
        let crop = CGRect(
            x: rectInWindow.minX * scale,
            y: rectInWindow.minY * scale,
            width: rectInWindow.width * scale,
            height: rectInWindow.height * scale
        ).integral.intersection(CGRect(origin: .zero, size: CGSize(width: source.width, height: source.height)))
        guard !crop.isEmpty, let cropped = source.cropping(to: crop) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: .up).pngData()
    }
}

private struct CanvasRegionCaptureSource: UIViewRepresentable {
    let handle: CanvasRegionCaptureHandle

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        handle.view = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        handle.view = view
    }
}
#elseif os(macOS)
private struct CanvasTrackpadMagnification {
    enum Phase {
        case began
        case changed
        case ended
    }

    var phase: Phase
    var magnification: CGFloat
    var location: CGPoint
}

private struct CanvasTrackpadZoomSource: NSViewRepresentable {
    let onMagnify: (CanvasTrackpadMagnification) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMagnify: onMagnify)
    }

    func makeNSView(context: Context) -> TrackpadHostView {
        let view = TrackpadHostView(frame: .zero)
        view.onWindowChanged = { [weak coordinator = context.coordinator] hostView in
            coordinator?.installRecognizer(for: hostView)
        }
        context.coordinator.hostView = view
        return view
    }

    func updateNSView(_ view: TrackpadHostView, context: Context) {
        context.coordinator.onMagnify = onMagnify
        context.coordinator.hostView = view
        context.coordinator.installRecognizer(for: view)
    }

    static func dismantleNSView(_ view: TrackpadHostView, coordinator: Coordinator) {
        coordinator.uninstallRecognizer()
    }

    final class TrackpadHostView: NSView {
        var onWindowChanged: ((TrackpadHostView) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChanged?(self)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSGestureRecognizerDelegate {
        var onMagnify: (CanvasTrackpadMagnification) -> Void
        weak var hostView: TrackpadHostView?
        weak var installedView: NSView?
        var recognizer: NSMagnificationGestureRecognizer?

        init(onMagnify: @escaping (CanvasTrackpadMagnification) -> Void) {
            self.onMagnify = onMagnify
        }

        func installRecognizer(for hostView: TrackpadHostView) {
            guard let contentView = hostView.window?.contentView else { return }
            if installedView === contentView, recognizer != nil { return }
            uninstallRecognizer()
            let recognizer = NSMagnificationGestureRecognizer(target: self, action: #selector(didMagnify(_:)))
            recognizer.delegate = self
            contentView.addGestureRecognizer(recognizer)
            installedView = contentView
            self.recognizer = recognizer
        }

        func uninstallRecognizer() {
            if let recognizer {
                installedView?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            installedView = nil
        }

        @objc private func didMagnify(_ recognizer: NSMagnificationGestureRecognizer) {
            guard let hostView else { return }
            let location = recognizer.location(in: hostView)
            guard hostView.bounds.contains(location) else { return }
            let phase: CanvasTrackpadMagnification.Phase
            switch recognizer.state {
            case .began:
                phase = .began
            case .changed:
                phase = .changed
            case .ended, .cancelled, .failed:
                phase = .ended
            default:
                return
            }
            onMagnify(CanvasTrackpadMagnification(
                phase: phase,
                magnification: max(0.01, 1 + recognizer.magnification),
                location: location
            ))
        }

        func gestureRecognizer(
            _ gestureRecognizer: NSGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

@MainActor
private final class CanvasRegionCaptureHandle {
    weak var view: NSView?

    func pngData(for rect: CGRect) -> Data? {
        guard let view, let window = view.window, let contentView = window.contentView,
              rect.width > 1, rect.height > 1 else { return nil }
        let rectInContent = view.convert(rect, to: contentView)
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: rectInContent) else { return nil }
        contentView.cacheDisplay(in: rectInContent, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }
}

private struct CanvasRegionCaptureSource: NSViewRepresentable {
    let handle: CanvasRegionCaptureHandle

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        handle.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        handle.view = view
    }
}
#endif

private struct CanvasInputToolPill: View {
    @Binding var selection: CanvasInputTool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CanvasInputTool.allCases) { tool in
                Button {
                    selection = tool
                } label: {
                    Label(tool.rawValue.capitalized, systemImage: tool.systemImage)
                        .labelStyle(.iconOnly)
                        .frame(width: 34, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == tool ? Color.white : Color.primary)
                .background(selection == tool ? Color.accentColor : Color.clear, in: Capsule())
                .help(tool.rawValue.capitalized)
                .accessibilityLabel(tool.rawValue.capitalized)
                .accessibilityAddTraits(selection == tool ? .isSelected : [])
            }
        }
        .padding(5)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().stroke(Color.secondary.opacity(0.18), lineWidth: 1) }
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Canvas input tools")
    }
}

private struct CanvasZoomPill: View {
    let zoom: CGFloat
    let canZoomOut: Bool
    let canZoomIn: Bool
    let onZoomOut: () -> Void
    let onReset: () -> Void
    let onZoomIn: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onZoomOut) { Image(systemName: "minus") }
                .disabled(!canZoomOut)
                .accessibilityLabel("Zoom Out")
            Button(action: onReset) {
                Text(zoom, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 42)
            }
            .accessibilityLabel("Reset Zoom")
            Button(action: onZoomIn) { Image(systemName: "plus") }
                .disabled(!canZoomIn)
                .accessibilityLabel("Zoom In")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 6)
        .frame(height: 40)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().stroke(Color.secondary.opacity(0.18), lineWidth: 1) }
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Canvas zoom")
    }
}

private struct CanvasWorkspaceGrid: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 24
            for x in stride(from: 0, through: size.width, by: step) {
                for y in stride(from: 0, through: size.height, by: step) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.secondary.opacity(0.24)))
                }
            }
        }
    }
}

private struct CanvasWorkspaceConnections: View {
    let elements: [CanvasWorkspaceElement]
    let connections: [CanvasWorkspaceConnection]

    var body: some View {
        Canvas { context, _ in
            for connection in connections {
                guard let source = elements.first(where: { $0.id == connection.sourceElementId }),
                      let target = elements.first(where: { $0.id == connection.targetElementId }) else { continue }
                var path = Path()
                path.move(to: CGPoint(x: source.bounds.x + source.bounds.width, y: source.bounds.y + source.bounds.height / 2))
                path.addLine(to: CGPoint(x: target.bounds.x, y: target.bounds.y + target.bounds.height / 2))
                context.stroke(path, with: .color(.accentColor.opacity(0.7)), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct CanvasWorkspaceElementView: View {
    let element: CanvasWorkspaceElement
    let html: String?
    let isSelected: Bool
    let onSelect: () -> Void
    let onUpdate: (CanvasWorkspaceElement) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isEditing = false
    @State private var draftText = ""
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        Group {
            if element.kind == .widget, let html {
                WorkspaceWebView(html: html, title: element.title)
            } else if element.kind == .image {
                imageContent
            } else {
                nativeContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: element.kind == .sticky ? 4 : 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: element.kind == .sticky ? 4 : 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.22), lineWidth: isSelected ? 2 : 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 7, y: 3)
        .offset(dragOffset)
        .contentShape(Rectangle())
        .highPriorityGesture(
            TapGesture(count: 2).onEnded {
                onSelect()
                beginEditing()
            }
        )
        .simultaneousGesture(
            TapGesture().onEnded(onSelect)
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    guard !isEditing else { return }
                    dragOffset = value.translation
                }
                .onEnded { value in
                    guard !isEditing else { return }
                    var updated = element
                    updated.bounds.x += value.translation.width
                    updated.bounds.y += value.translation.height
                    dragOffset = .zero
                    onUpdate(updated)
                }
        )
        .onChange(of: isSelected) { wasSelected, isSelected in
            if wasSelected, !isSelected {
                finishEditing()
            }
        }
        .onChange(of: isEditorFocused) { wasFocused, isFocused in
            if wasFocused, !isFocused {
                finishEditing()
            }
        }
        .accessibilityLabel(element.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay(alignment: .topTrailing) {
            if isSelected, isTextEditable, !isEditing {
                Button(action: beginEditing) {
                    Image(systemName: "pencil")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .padding(8)
                .help("Edit")
                .accessibilityLabel("Edit \(element.kind.rawValue)")
            }
        }
    }

    private var nativeContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(element.kind.rawValue.capitalized, systemImage: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isEditing {
                    Button("Done") { finishEditing() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            if isEditing {
                TextEditor(text: $draftText)
                    .font(element.kind == .text ? .title3 : .body)
                    .scrollContentBackground(.hidden)
                    .padding(-5)
                    .focused($isEditorFocused)
                    .onAppear {
                        isEditorFocused = true
                    }
                    .accessibilityLabel("\(element.kind.rawValue.capitalized) text")
            } else {
                Text(element.title)
                    .font(element.kind == .text ? .title3 : .body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(14)
    }

    private var isTextEditable: Bool {
        element.kind == .sticky || element.kind == .text || element.kind == .shape
    }

    private func beginEditing() {
        guard isTextEditable else { return }
        draftText = element.title
        isEditing = true
    }

    private func finishEditing() {
        guard isEditing else { return }
        isEditing = false
        isEditorFocused = false
        guard draftText != element.title else { return }

        var updated = element
        updated.data["text"] = .string(draftText)
        onUpdate(updated)
    }

    @ViewBuilder
    private var imageContent: some View {
        if let address = element.data["url"]?.stringValue, let url = URL(string: address) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView()
            }
        } else {
            ContentUnavailableView("Image", systemImage: "photo", description: Text("Ask an agent to add a visual"))
        }
    }

    private var background: some ShapeStyle {
        switch element.kind {
        case .sticky:
            AnyShapeStyle(Color.yellow.opacity(0.82))
        case .shape:
            AnyShapeStyle(Color.accentColor.opacity(0.18))
        case .frame:
            AnyShapeStyle(Color.clear)
        default:
            AnyShapeStyle(.regularMaterial)
        }
    }

    private var icon: String {
        switch element.kind {
        case .sticky: "note.text"
        case .text: "textformat"
        case .shape: "square.on.circle"
        case .image: "photo"
        case .table: "tablecells"
        case .frame: "rectangle.dashed"
        case .widget: "safari"
        }
    }
}

private struct CanvasWorkspaceMiniMap: View {
    let document: CanvasWorkspaceDocument?
    let canvasSize: CGSize
    let viewport: CanvasViewport
    let zoom: CGFloat

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / canvasSize.width, size.height / canvasSize.height)
            let canvasOrigin = CGPoint(
                x: (size.width - canvasSize.width * scale) / 2,
                y: (size.height - canvasSize.height * scale) / 2
            )
            let canvasRect = CGRect(
                origin: canvasOrigin,
                size: CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
            )

            context.fill(
                Path(roundedRect: canvasRect, cornerRadius: 4),
                with: .color(.secondary.opacity(0.06))
            )

            for element in document?.elements ?? [] where element.id != "native-pencil-drawing" {
                let rect = CGRect(
                    x: canvasOrigin.x + element.bounds.x * scale,
                    y: canvasOrigin.y + element.bounds.y * scale,
                    width: max(3, element.bounds.width * scale),
                    height: max(3, element.bounds.height * scale)
                )
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(element.kind == .sticky ? .yellow : .secondary.opacity(0.7)))
            }

            if viewport.size.width > 0, viewport.size.height > 0 {
                let safeZoom = max(zoom, 0.01)
                let cameraSize = CGSize(
                    width: min(canvasSize.width, viewport.size.width / safeZoom),
                    height: min(canvasSize.height, viewport.size.height / safeZoom)
                )
                let maximumCameraOrigin = CGPoint(
                    x: max(0, canvasSize.width - cameraSize.width),
                    y: max(0, canvasSize.height - cameraSize.height)
                )
                let cameraOrigin = CGPoint(
                    x: min(maximumCameraOrigin.x, max(0, viewport.offset.x / safeZoom)),
                    y: min(maximumCameraOrigin.y, max(0, viewport.offset.y / safeZoom))
                )
                let cameraRect = CGRect(
                    x: canvasOrigin.x + cameraOrigin.x * scale,
                    y: canvasOrigin.y + cameraOrigin.y * scale,
                    width: cameraSize.width * scale,
                    height: cameraSize.height * scale
                )
                let cameraPath = Path(roundedRect: cameraRect, cornerRadius: 3)

                context.fill(cameraPath, with: .color(.accentColor.opacity(0.14)))
                context.stroke(
                    cameraPath,
                    with: .color(.accentColor),
                    style: StrokeStyle(lineWidth: 2, lineJoin: .round)
                )
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 10, y: 3)
        .accessibilityLabel("Workspace Mini Map")
        .accessibilityValue("Current view at \(Int(zoom * 100)) percent zoom")
    }
}
