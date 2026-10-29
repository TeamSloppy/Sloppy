import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CoreGraphics
import SloppyClientUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct ChatImageAnnotationEditor: View {
    let attachment: ChatComposerAttachment
    private let save: (@MainActor (ChatComposerAttachment) -> Void)?
    private let decodedImage: CGImage?

    private enum Tool: String, CaseIterable {
        case pan, pen, arrow, rectangle, comment
        var title: String { switch self {
        case .pan: "Pan"
        case .pen: "Draw"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .comment: "Comment"
        } }
        var symbol: String { switch self {
        case .pan: "hand.draw"
        case .pen: "pencil.tip"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .comment: "text.bubble"
        } }
        var strokeKind: ChatImageStroke.Kind? { switch self {
        case .pen: .pen
        case .arrow: .arrow
        case .rectangle: .rectangle
        default: nil
        } }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var viewport = ChatImageViewport()
    @State private var canvasSize: CGSize = .zero
    @State private var tool: Tool
    @State private var ink: ChatImageStroke.Ink = .coral
    @State private var lineWidth: Double = 0.004
    @State private var gestureZoom: CGFloat?
    @State private var lastPanTranslation: CGSize = .zero
    @State private var annotations: [ChatImageAnnotation]
    @State private var strokes: [ChatImageStroke]
    @State private var redoStrokes: [ChatImageStroke] = []
    @State private var pendingStroke: ChatImageStroke?
    @State private var selectedID: UUID?
    @State private var provisionalRegion: ChatImageRegion?
    @FocusState private var focusedAnnotationID: UUID?
    @State private var exportDocument: ChatImageExportDocument?
    @State private var exportType: UTType = .png
    @State private var exportName = "image.png"
    @State private var isExporting = false
    @State private var errorMessage: String?
    @State private var confirmsDiscard = false

    init(attachment: ChatComposerAttachment, save: @escaping @MainActor ([ChatImageAnnotation]) -> Void) {
        self.attachment = attachment
        self.save = { save($0.annotations) }
        decodedImage = ChatImageExport.decode(attachment.data)
        _annotations = State(initialValue: attachment.annotations)
        _strokes = State(initialValue: attachment.markup?.strokes ?? [])
        _selectedID = State(initialValue: attachment.annotations.last?.id)
        _tool = State(initialValue: .comment)
    }

    init(attachment: ChatComposerAttachment, onSave: (@MainActor (ChatComposerAttachment) -> Void)? = nil) {
        self.attachment = attachment
        save = onSave
        decodedImage = ChatImageExport.decode(attachment.data)
        _annotations = State(initialValue: attachment.annotations)
        _strokes = State(initialValue: attachment.markup?.strokes ?? [])
        _selectedID = State(initialValue: attachment.annotations.last?.id)
        _tool = State(initialValue: .pan)
    }

    private var isPanning: Bool { tool == .pan }
    private var hasEdits: Bool { annotations != attachment.annotations || strokes != (attachment.markup?.strokes ?? []) }
    private var chrome: Color { Color(red: 0.15, green: 0.15, blue: 0.15) }
    private var imageSize: CGSize { decodedImage.map { CGSize(width: $0.width, height: $0.height) } ?? .zero }
    private var zoomLabel: String {
        let fit = ChatImageRegion.imageFrame(imageSize: imageSize, canvasSize: canvasSize)
        let scale = imageSize.width > 0 ? fit.width / imageSize.width * viewport.zoom : 1
        return "\(Int((scale * 100).rounded()))%"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let decodedImage {
                canvas(image: Image(decorative: decodedImage, scale: 1), size: imageSize)
                    .overlay(alignment: .top) {
                        VStack(spacing: 8) {
                            tools
                            if tool.strokeKind != nil { drawingOptions }
                        }.padding(14)
                    }
                    .overlay(alignment: .bottom) {
                        if tool == .comment, !annotations.isEmpty {
                            annotationComments
                                .padding(16).frame(maxWidth: 500).frame(height: 172)
                                .background(chrome, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
                                .padding(16)
                        }
                    }
            } else {
                ContentUnavailableView("Image unavailable", systemImage: "photo",
                                       description: Text("This attachment could not be opened."))
            }
            HStack {
                Text(hint).lineLimit(2)
                Spacer()
                if decodedImage != nil { Text("\(Int(imageSize.width)) × \(Int(imageSize.height))").monospacedDigit() }
            }
            .font(.caption).foregroundStyle(.white.opacity(0.55)).padding(.horizontal, 18).padding(.vertical, 10)
        }
        .foregroundStyle(.white.opacity(0.9))
        .background(Color(red: 0.075, green: 0.075, blue: 0.075))
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(minWidth: 680, idealWidth: 1200, minHeight: 520, idealHeight: 820)
        #endif
        .presentationDetents([.large])
        .interactiveDismissDisabled(hasEdits)
        .onChange(of: tool) { _, _ in
            pendingStroke = nil
            provisionalRegion = nil
            focusedAnnotationID = nil
        }
        .fileExporter(isPresented: $isExporting, document: exportDocument, contentType: exportType,
                      defaultFilename: exportName) { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
        }
        .alert("Couldn’t save image", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .confirmationDialog("Discard unsaved image edits?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard edits", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
    }

    private var hint: String {
        switch tool {
        case .pan:
            #if os(macOS)
            "Drag to pan · Pinch to zoom · ⌘0 to fit"
            #else
            "Drag to pan · Pinch to zoom"
            #endif
        case .comment: "Click for a point, or drag to annotate an area."
        default:
            #if os(macOS)
            "Drag to draw · Hold Option to pan · Undo to remove the last mark"
            #else
            "Drag to draw · Undo to remove the last mark"
            #endif
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                imageTitle
                Spacer(minLength: 12)
                zoomControls
                downloadMenu
                if save != nil { saveButton }
                closeButton
            }
            VStack(spacing: 10) {
                HStack { imageTitle; Spacer(); if save != nil { saveButton }; closeButton }
                HStack { zoomControls; Spacer(); downloadMenu }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12).background(chrome.opacity(0.6))
        .buttonStyle(.plain)
    }

    private var imageTitle: some View {
        Label(attachment.name, systemImage: "photo")
            .font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
    }

    private var closeButton: some View {
        Button {
            if hasEdits { confirmsDiscard = true } else { dismiss() }
        } label: { Image(systemName: "xmark").frame(width: 32, height: 32).background(.white.opacity(0.08), in: Circle()) }
        .keyboardShortcut(.cancelAction).accessibilityLabel("Close image viewer")
    }

    private var saveButton: some View {
        Button("Add to chat") { saveChanges() }
            .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 8)
            .background(.white.opacity(0.12), in: Capsule())
            .keyboardShortcut(.defaultAction)
            .disabled(decodedImage == nil)
            .accessibilityIdentifier("chat.image.annotations.save")
    }

    private var tools: some View {
        HStack(spacing: 4) {
            ForEach(Tool.allCases, id: \.self) { item in
                Button { tool = item } label: {
                    Label(item.title, systemImage: item.symbol)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 16)).frame(width: 40, height: 36)
                        .background(tool == item ? .white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 9))
                }
                .help(item.title).accessibilityLabel(item.title)
                .accessibilityAddTraits(tool == item ? .isSelected : [])
                .accessibilityIdentifier("chat.image.tool.\(item.rawValue)")
            }
            Divider().frame(height: 20).padding(.horizontal, 4)
            Button { if let last = strokes.popLast() { redoStrokes.append(last) } } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 34, height: 36)
            }
            .disabled(strokes.isEmpty || focusedAnnotationID != nil).help("Undo drawing")
            .keyboardShortcut("z", modifiers: .command)
            .accessibilityLabel("Undo drawing").accessibilityIdentifier("chat.image.markup.undo")
            Button { if let last = redoStrokes.popLast() { strokes.append(last) } } label: {
                Image(systemName: "arrow.uturn.forward").frame(width: 34, height: 36)
            }
            .disabled(redoStrokes.isEmpty || focusedAnnotationID != nil).help("Redo drawing")
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .accessibilityLabel("Redo drawing").accessibilityIdentifier("chat.image.markup.redo")
        }
        .padding(5).background(chrome.opacity(0.97), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12)))
        .buttonStyle(.plain).fixedSize()
    }

    private var drawingOptions: some View {
        HStack(spacing: 12) {
            ForEach(ChatImageStroke.Ink.allCases, id: \.self) { color in
                Button { ink = color } label: {
                    Circle().fill(color.color).frame(width: 20, height: 20)
                        .padding(3).overlay(Circle().stroke(ink == color ? .white : .clear, lineWidth: 1.5))
                }.accessibilityLabel("\(color.rawValue.capitalized) ink")
                    .accessibilityAddTraits(ink == color ? .isSelected : [])
            }
            Divider().frame(height: 18)
            ForEach([0.002, 0.004, 0.008], id: \.self) { width in
                Button { lineWidth = width } label: {
                    Capsule().fill(.white).frame(width: 22, height: width * 800)
                        .frame(width: 26, height: 26)
                        .background(lineWidth == width ? .white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
                }.accessibilityLabel(width == 0.002 ? "Thin stroke" : width == 0.004 ? "Medium stroke" : "Thick stroke")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(chrome.opacity(0.97), in: Capsule()).buttonStyle(.plain).fixedSize()
    }

    private var zoomControls: some View {
        HStack(spacing: 6) {
            Button { zoom(by: 1 / 1.25) } label: { Image(systemName: "minus").frame(width: 26, height: 30) }
                .keyboardShortcut("-", modifiers: .command).accessibilityLabel("Zoom out")
                .accessibilityIdentifier("chat.image.annotations.zoom-out")
            Menu {
                Button("Fit to view") { viewport.reset() }
                ForEach([25, 50, 100, 150, 200, 400, 800], id: \.self) { percent in
                    Button("\(percent)%") { setPixelZoom(CGFloat(percent) / 100) }
                }
            } label: { Text(zoomLabel).monospacedDigit().frame(minWidth: 44) }
            .menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel("Zoom \(zoomLabel)")
            Button { zoom(by: 1.25) } label: { Image(systemName: "plus").frame(width: 26, height: 30) }
                .keyboardShortcut("=", modifiers: .command).accessibilityLabel("Zoom in")
                .accessibilityIdentifier("chat.image.annotations.zoom-in")
            Button { viewport.reset() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 30, height: 30) }
                .keyboardShortcut("0", modifiers: .command).help("Fit to view")
                .accessibilityLabel("Fit to view").accessibilityIdentifier("chat.image.annotations.fit")
        }.padding(.horizontal, 6).background(.white.opacity(0.07), in: Capsule())
    }

    private func zoom(by factor: CGFloat) {
        viewport.setZoom(viewport.zoom * factor, imageSize: imageSize, canvasSize: canvasSize)
    }

    private func setPixelZoom(_ scale: CGFloat) {
        let fit = ChatImageRegion.imageFrame(imageSize: imageSize, canvasSize: canvasSize)
        guard fit.width > 0 else { return }
        viewport.setZoom(scale * imageSize.width / fit.width, imageSize: imageSize, canvasSize: canvasSize)
    }

    private var downloadMenu: some View {
        Menu {
            Button("Download original", systemImage: "photo") { prepareExport(.original) }
            Button("Download annotated PNG", systemImage: "pencil.tip.crop.circle") { prepareExport(.annotated) }
            Divider()
            Button("Download all (.zip)", systemImage: "archivebox") { prepareExport(.all) }
        } label: { Image(systemName: "arrow.down.to.line").frame(width: 32, height: 32).background(.white.opacity(0.08), in: Circle()) }
        .menuStyle(.borderlessButton).fixedSize().disabled(decodedImage == nil)
        .help("Download").accessibilityLabel("Download image and annotations")
        .accessibilityIdentifier("chat.image.download")
    }

    private enum Export { case original, annotated, all }

    private func prepareExport(_ format: Export) {
        guard let decodedImage else { return }
        do {
            let base = (attachment.name as NSString).deletingPathExtension
            let data: Data
            switch format {
            case .original:
                data = attachment.data
                exportType = UTType(mimeType: attachment.mimeType) ?? .data
                exportName = attachment.name
            case .annotated:
                data = try ChatImageExport.png(image: decodedImage, strokes: strokes, annotations: annotations)
                exportType = .png
                exportName = base + "-annotated.png"
            case .all:
                let png = try ChatImageExport.png(image: decodedImage, strokes: strokes, annotations: annotations)
                data = ChatImageArchive.make(original: attachment.data,
                    originalExtension: UTType(mimeType: attachment.mimeType)?.preferredFilenameExtension ?? "image",
                    annotated: png, notes: try ChatImageExport.notes(annotations: annotations, strokes: strokes))
                exportType = .zip
                exportName = base + "-all.zip"
            }
            exportDocument = ChatImageExportDocument(data: data)
            isExporting = true
        } catch { errorMessage = error.localizedDescription }
    }

    private func saveChanges() {
        guard let decodedImage else { return }
        do {
            var edited = attachment
            edited.annotations = annotations.filter { $0.browserSource == nil || !$0.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            edited.markup = strokes.isEmpty ? nil : ChatImageMarkup(strokes: strokes,
                pngData: try ChatImageExport.png(image: decodedImage, strokes: strokes))
            guard edited.sizeBytes <= 25 * 1_024 * 1_024 else {
                errorMessage = "The marked-up image is larger than 25 MB. Remove some marks or export it instead."
                return
            }
            save?(edited)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func pointerChanged(from start: CGPoint, to end: CGPoint, frame: CGRect) {
        if let kind = tool.strokeKind {
            guard frame.contains(start) else { return }
            if pendingStroke == nil { pendingStroke = ChatImageStroke(kind: kind, ink: ink, width: lineWidth, start: start, frame: frame) }
            pendingStroke?.append(end, in: frame)
        } else if tool == .comment {
            provisionalRegion = ChatImageRegion.selection(from: start, to: end, imageFrame: frame)
        }
    }

    private func pointerEnded(from start: CGPoint, to end: CGPoint, frame: CGRect) {
        pointerChanged(from: start, to: end, frame: frame)
        if let pendingStroke {
            strokes.append(pendingStroke)
            redoStrokes.removeAll()
        } else if let provisionalRegion { addAnnotation(provisionalRegion) }
        pendingStroke = nil
        provisionalRegion = nil
    }

    private func canvas(image: Image, size: CGSize) -> some View {
        GeometryReader { geometry in
            let frame = viewport.frame(imageSize: size, canvasSize: geometry.size)
            ZStack(alignment: .topLeading) {
                Color(red: 0.075, green: 0.075, blue: 0.075)
                image.resizable()
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .allowsHitTesting(false)

                #if os(macOS)
                ChatImageAnnotationPointerInput(isPanning: isPanning, changed: { start, end in
                    pointerChanged(from: start, to: end, frame: frame)
                }, ended: { start, end in
                    pointerEnded(from: start, to: end, frame: frame)
                }, pan: { delta in
                    provisionalRegion = nil
                    pendingStroke = nil
                    viewport.move(by: delta, imageSize: size, canvasSize: geometry.size)
                }, magnify: { factor in
                    provisionalRegion = nil
                    pendingStroke = nil
                    viewport.setZoom(viewport.zoom * factor, imageSize: size, canvasSize: geometry.size)
                })
                .frame(width: geometry.size.width, height: geometry.size.height)
                #else
                Color.clear
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { value in
                                if isPanning {
                                    viewport.move(by: CGSize(width: value.translation.width - lastPanTranslation.width,
                                                             height: value.translation.height - lastPanTranslation.height),
                                                  imageSize: size, canvasSize: geometry.size)
                                    lastPanTranslation = value.translation
                                    return
                                }
                                pointerChanged(from: value.startLocation, to: value.location, frame: frame)
                            }
                            .onEnded { value in
                                lastPanTranslation = .zero
                                guard !isPanning else { return }
                                pointerEnded(from: value.startLocation, to: value.location, frame: frame)
                            }
                            .exclusively(before: SpatialTapGesture().onEnded { value in
                                guard !isPanning else { return }
                                pointerEnded(from: value.location, to: value.location, frame: frame)
                            })
                    )
                    .simultaneousGesture(MagnifyGesture().onChanged { value in
                        pendingStroke = nil
                        provisionalRegion = nil
                        if gestureZoom == nil { gestureZoom = viewport.zoom }
                        viewport.setZoom((gestureZoom ?? 1) * value.magnification, imageSize: size, canvasSize: geometry.size)
                    }.onEnded { _ in gestureZoom = nil })
                    .accessibilityLabel("Screenshot annotation canvas")
                    .accessibilityIdentifier("chat.image.annotations.canvas")
                #endif

                ChatImageMarkupLayer(strokes: strokes + (pendingStroke.map { [$0] } ?? []), frame: frame)

                ForEach(annotations) { annotation in
                    regionOutline(annotation.region, in: frame)
                        .allowsHitTesting(false)
                }
                if let provisionalRegion {
                    regionOutline(provisionalRegion, in: frame).allowsHitTesting(false)
                }
                ForEach(Array(annotations.enumerated()), id: \.element.id) { number, annotation in
                    Button {
                        tool = .comment
                        selectedID = annotation.id
                        focusedAnnotationID = annotation.id
                    } label: {
                        Text("\(number + 1)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(ChatAnnotationStyle.ink)
                            .frame(width: 28, height: 28)
                            .background(ChatAnnotationStyle.mint, in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .position(x: frame.minX + annotation.region.x * frame.width,
                              y: frame.minY + annotation.region.y * frame.height)
                    .accessibilityLabel("Edit annotation \(number + 1)")
                }
            }
            .onAppear { canvasSize = geometry.size }
            .onChange(of: geometry.size) { _, newSize in
                canvasSize = newSize
                viewport.constrain(imageSize: size, canvasSize: newSize)
            }
        }
        .frame(minHeight: 160, maxHeight: .infinity)
        .clipped()
    }

    private func regionOutline(_ region: ChatImageRegion, in frame: CGRect) -> some View {
        Rectangle()
            .fill(ChatAnnotationStyle.mint.opacity(0.15))
            .overlay(Rectangle().stroke(ChatAnnotationStyle.mint, lineWidth: 2))
            .frame(width: max(2, region.width * frame.width), height: max(2, region.height * frame.height))
            .offset(x: frame.minX + region.x * frame.width, y: frame.minY + region.y * frame.height)
    }

    private var annotationComments: some View {
        VStack(alignment: .leading, spacing: 12) {
            if annotations.isEmpty {
                Text("Mark the screenshot, then write a comment for that location.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(annotations.enumerated()), id: \.element.id) { number, annotation in
                            HStack {
                                Button("\(number + 1) · \(annotation.region.coordinateDescription)") {
                                    selectedID = annotation.id
                                    focusedAnnotationID = annotation.id
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                                Button {
                                    annotations.removeAll { $0.id == annotation.id }
                                    if selectedID == annotation.id { selectedID = annotations.last?.id }
                                } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove annotation \(number + 1)")
                            }
                            .padding(8)
                            .background(selectedID == annotation.id ? ChatAnnotationStyle.mint.opacity(0.25) : .clear)
                        }
                    }
                }
                Divider()
                if let selectedID, let index = annotations.firstIndex(where: { $0.id == selectedID }) {
                    Text("Comment for annotation \(index + 1)").font(.subheadline.weight(.semibold))
                    TextField("What should the agent pay attention to?", text: Binding(
                        get: { annotations.first(where: { $0.id == selectedID })?.comment ?? "" },
                        set: { comment in
                            guard let current = annotations.firstIndex(where: { $0.id == selectedID }) else { return }
                            annotations[current].comment = comment
                        }
                    ), axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.plain)
                        .focused($focusedAnnotationID, equals: selectedID)
                        .id(selectedID)
                        .task(id: selectedID) {
                            await Task.yield()
                            guard !Task.isCancelled else { return }
                            focusedAnnotationID = selectedID
                        }
                        .accessibilityIdentifier("chat.image.annotations.comment")
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func addAnnotation(_ region: ChatImageRegion) {
        let source = attachment.annotations.compactMap(\.browserSource).first.map {
            ChatImageAnnotation.BrowserSource(url: $0.url, title: $0.title)
        }
        let annotation = ChatImageAnnotation(region: region, browserSource: source)
        annotations.append(annotation)
        selectedID = annotation.id
        focusedAnnotationID = annotation.id
    }


}

enum ChatAnnotationStyle {
    static let mint = Color(red: 200 / 255, green: 226 / 255, blue: 174 / 255)
    static let ink = Color(red: 36 / 255, green: 37 / 255, blue: 33 / 255)
    static let paper = Color(red: 245 / 255, green: 242 / 255, blue: 233 / 255)
    static let forest = Color(red: 32 / 255, green: 38 / 255, blue: 30 / 255)

    static func background(_ scheme: ColorScheme) -> Color { scheme == .dark ? forest : paper }
    static func foreground(_ scheme: ColorScheme) -> Color { scheme == .dark ? paper : ink }
}
