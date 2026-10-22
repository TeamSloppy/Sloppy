import Foundation
import SwiftUI
import SloppyClientUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct ChatImageAnnotationEditor: View {
    let attachment: ChatComposerAttachment
    let save: @MainActor ([ChatImageAnnotation]) -> Void
    private let decodedImage: (image: Image, size: CGSize)?

    @Environment(\.theme) private var theme
    @State private var viewport = ChatImageViewport()
    @State private var canvasSize: CGSize = .zero
    @State private var isPanning = false
    @State private var gestureZoom: CGFloat?
    @State private var lastPanTranslation: CGSize = .zero
    @State private var annotations: [ChatImageAnnotation]
    @State private var selectedID: UUID?
    @State private var provisionalRegion: ChatImageRegion?
    @FocusState private var focusedAnnotationID: UUID?
    @Environment(\.dismiss) private var dismiss

    init(attachment: ChatComposerAttachment, save: @escaping @MainActor ([ChatImageAnnotation]) -> Void) {
        self.attachment = attachment
        self.save = save
        self.decodedImage = Self.decodeImage(attachment.data)
        _annotations = State(initialValue: attachment.annotations)
        _selectedID = State(initialValue: attachment.annotations.last?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(attachment.name).font(.headline).lineLimit(1)
                    Text("Click to mark a point. Drag for an area. Use Pan or two-finger scroll to move the image.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add to chat") {
                    save(annotations.filter { $0.browserSource == nil || !$0.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("chat.image.annotations.save")
            }

            if let decodedImage {
                viewportControls(imageSize: decodedImage.size)
                canvas(image: decodedImage.image, size: decodedImage.size)
            } else {
                ContentUnavailableView("Image unavailable", systemImage: "photo",
                                       description: Text("This attachment could not be opened."))
            }

            annotationComments
                .frame(height: 150)
        }
        .padding(20)
        .foregroundStyle(theme.colors.textPrimary)
        .background(theme.colors.surface)
        #if os(macOS)
        .frame(minWidth: 680, idealWidth: 1000, minHeight: 650, idealHeight: 820)
        #endif
        .presentationDetents([.large])
    }

    private func viewportControls(imageSize: CGSize) -> some View {
        HStack(spacing: 12) {
            Button { viewport.setZoom(viewport.zoom / 1.25, imageSize: imageSize, canvasSize: canvasSize) } label: {
                Label("Zoom out", systemImage: "minus.magnifyingglass")
            }
            .labelStyle(.iconOnly)
            .help("Zoom out (Command–minus)")
            .keyboardShortcut("-", modifiers: .command)
            .disabled(viewport.zoom <= ChatImageViewport.zoomRange.lowerBound)
            .accessibilityIdentifier("chat.image.annotations.zoom-out")
            Text("\(Int((viewport.zoom * 100).rounded()))%")
                .monospacedDigit().frame(minWidth: 48)
                .accessibilityLabel("Zoom \(Int((viewport.zoom * 100).rounded())) percent of fit")
            Button { viewport.setZoom(viewport.zoom * 1.25, imageSize: imageSize, canvasSize: canvasSize) } label: {
                Label("Zoom in", systemImage: "plus.magnifyingglass")
            }
            .labelStyle(.iconOnly)
            .help("Zoom in (Command–plus)")
            .keyboardShortcut("=", modifiers: .command)
            .disabled(viewport.zoom >= ChatImageViewport.zoomRange.upperBound)
            .accessibilityIdentifier("chat.image.annotations.zoom-in")
            Button("Fit to view") { viewport.reset() }
                .keyboardShortcut("0", modifiers: .command)
                .accessibilityIdentifier("chat.image.annotations.fit")
            Divider().frame(height: 20)
            Toggle("Pan", isOn: $isPanning).toggleStyle(.button)
                .help("Drag to pan without adding annotations. Two-finger scroll also pans.")
                .accessibilityIdentifier("chat.image.annotations.pan")
            Spacer()
            if isPanning {
                panButton("Pan left", symbol: "arrow.left", delta: CGSize(width: 40, height: 0), key: .leftArrow, imageSize: imageSize)
                panButton("Pan right", symbol: "arrow.right", delta: CGSize(width: -40, height: 0), key: .rightArrow, imageSize: imageSize)
                panButton("Pan up", symbol: "arrow.up", delta: CGSize(width: 0, height: 40), key: .upArrow, imageSize: imageSize)
                panButton("Pan down", symbol: "arrow.down", delta: CGSize(width: 0, height: -40), key: .downArrow, imageSize: imageSize)
            }
        }
        .foregroundStyle(theme.colors.textPrimary)
        .onChange(of: isPanning) { _, _ in provisionalRegion = nil }
    }

    private func panButton(_ title: String, symbol: String, delta: CGSize, key: KeyEquivalent, imageSize: CGSize) -> some View {
        Button { viewport.move(by: delta, imageSize: imageSize, canvasSize: canvasSize) } label: {
            Label(title, systemImage: symbol)
        }
        .labelStyle(.iconOnly)
        .help(title)
        .keyboardShortcut(key, modifiers: [.command, .option])
    }

    private func canvas(image: Image, size: CGSize) -> some View {
        GeometryReader { geometry in
            let frame = viewport.frame(imageSize: size, canvasSize: geometry.size)
            ZStack(alignment: .topLeading) {
                theme.colors.background
                image.resizable()
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .allowsHitTesting(false)

                #if os(macOS)
                ChatImageAnnotationPointerInput(isPanning: isPanning, changed: { start, end in
                    provisionalRegion = ChatImageRegion.selection(from: start, to: end, imageFrame: frame)
                }, ended: { start, end in
                    provisionalRegion = nil
                    guard let region = ChatImageRegion.selection(from: start, to: end, imageFrame: frame) else { return }
                    addAnnotation(region)
                }, pan: { delta in
                    provisionalRegion = nil
                    viewport.move(by: delta, imageSize: size, canvasSize: geometry.size)
                }, magnify: { factor in
                    provisionalRegion = nil
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
                                provisionalRegion = ChatImageRegion.selection(
                                    from: value.startLocation, to: value.location, imageFrame: frame)
                            }
                            .onEnded { value in
                                lastPanTranslation = .zero
                                guard !isPanning else { return }
                                provisionalRegion = nil
                                guard let region = ChatImageRegion.selection(
                                    from: value.startLocation, to: value.location, imageFrame: frame
                                ) else { return }
                                addAnnotation(region)
                            }
                            .exclusively(before: SpatialTapGesture().onEnded { value in
                                guard !isPanning, let region = ChatImageRegion.selection(
                                    from: value.location, to: value.location, imageFrame: frame
                                ) else { return }
                                addAnnotation(region)
                            })
                    )
                    .simultaneousGesture(MagnifyGesture().onChanged { value in
                        if gestureZoom == nil { gestureZoom = viewport.zoom }
                        viewport.setZoom((gestureZoom ?? 1) * value.magnification, imageSize: size, canvasSize: geometry.size)
                    }.onEnded { _ in gestureZoom = nil })
                    .accessibilityLabel("Screenshot annotation canvas")
                    .accessibilityIdentifier("chat.image.annotations.canvas")
                #endif

                ForEach(annotations) { annotation in
                    regionOutline(annotation.region, in: frame)
                        .allowsHitTesting(false)
                }
                if let provisionalRegion {
                    regionOutline(provisionalRegion, in: frame).allowsHitTesting(false)
                }
                ForEach(Array(annotations.enumerated()), id: \.element.id) { number, annotation in
                    Button {
                        selectedID = annotation.id
                        focusedAnnotationID = annotation.id
                    } label: {
                        Text("\(number + 1)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(theme.colors.background)
                            .frame(width: 28, height: 28)
                            .background(theme.colors.accent, in: Circle())
                            .overlay(Circle().stroke(theme.colors.borderBold, lineWidth: 1))
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
            .fill(theme.colors.accent.opacity(0.15))
            .overlay(Rectangle().stroke(theme.colors.accent, lineWidth: 2))
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
                            .background(selectedID == annotation.id ? theme.colors.accent.opacity(0.25) : .clear)
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

    private static func decodeImage(_ data: Data) -> (image: Image, size: CGSize)? {
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return (Image(nsImage: image), image.size)
        #elseif canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return (Image(uiImage: image), image.size)
        #else
        return nil
        #endif
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
