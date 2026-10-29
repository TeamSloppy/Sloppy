@_spi(AdaEngine) import AdaEngine
import SwiftTerm
struct WorkspaceTerminalSurface: UIViewRepresentable {
    let session: WorkspaceTerminalSession
    func makeUIView(in context: Context) -> WorkspaceTerminalView { WorkspaceTerminalView(frame: .zero) }
    func sizeThatFits(_ proposal: ProposedViewSize, view: WorkspaceTerminalView, context: Context) -> Size {
        proposal.replacingUnspecifiedDimensions()
    }
    func updateUIView(_ view: WorkspaceTerminalView, in context: Context) {
        if view.session !== session { view.session?.onChange = nil }
        view.session = session
        session.onChange = { [weak view] in view?.setNeedsDisplay() }
        view.setNeedsLayout()
        view.setNeedsDisplay()
    }
}

final class WorkspaceTerminalView: UIView {
    var session: WorkspaceTerminalSession?
    private let cellWidth: Float = 8.4
    private let cellHeight: Float = 19
    private var isSelecting = false
    private struct GlyphKey: Hashable {
        let text: String
        let foreground: AdaEngine.Color
        let bold: Bool
        let width: Int8
    }
    private var glyphs: [GlyphKey: TextLayoutManager] = [:]
    override var acceptsKeyboardFocus: Bool { true }

    override func layoutSubviews() {
        super.layoutSubviews()
        session?.resize(columns: Int(max(0, bounds.width - 12) / cellWidth), rows: Int(max(0, bounds.height - 8) / cellHeight))
    }

    override func onFocusChanged(isFocused: Bool) {
        session?.terminal.setTerminalFocus(isFocused)
        setNeedsDisplay()
    }

    override func onTextInputEvent(_ event: TextInputEvent) {
        if event.action == .insert || event.action == .commitText {
            // Enter, Tab, Escape and control chords are delivered by onKeyEvent.
            let text = event.text.filter { $0 == " " || !$0.unicodeScalars.allSatisfy { $0.value < 32 || $0.value == 127 } }
            session?.send(text)
        }
        if event.action == .deleteBackward { session?.send("\u{7f}") }
    }

    override func onKeyEvent(_ event: KeyEvent) {
        guard event.status == .down, let session else { return }
        if event.keyCode == .v, WorkspaceTerminalKeyboard.isClipboardChord(event.modifiers)
            || event.modifiers.contains(.control) && !event.modifiers.contains(.alt) {
            session.pasteClipboard()
            return
        }
        if WorkspaceTerminalKeyboard.isClipboardChord(event.modifiers), event.keyCode == .c {
            UIClipboard.setString(session.terminal.selectionText(session.selection))
            return
        }
        if let text = WorkspaceTerminalKeyboard.sequence(event, applicationCursor: session.terminal.applicationCursor) { session.send(text) }
    }

    override func onMouseEvent(_ event: MouseEvent) {
        guard let session else { return }
        let column = max(0, min(session.terminal.cols - 1, Int((event.mousePosition.x - 6) / cellWidth)))
        let row = max(0, min(session.terminal.rows - 1, Int((event.mousePosition.y - 4) / cellHeight)))
        if event.button == .scrollWheel {
            if !session.terminal.sendHostMouse(action: .wheel, button: event.scrollDelta.y > 0 ? .wheelUp : .wheelDown,
                                                modifiers: 0, col: column, row: row, pixelX: max(0, Int(event.mousePosition.x)),
                                                pixelY: max(0, Int(event.mousePosition.y))) {
                session.terminal.scrollViewport(event.scrollDelta.y > 0 ? -3 : 3)
            }
            setNeedsDisplay()
            return
        }
        guard event.button == .left || event.button == .none else { return }
        let action: TerminalMouseAction = event.phase == .began ? .press : event.phase == .ended ? .release : .move
        if session.terminal.sendHostMouse(action: action, button: event.button == .none ? .none : .left,
                                          modifiers: 0, col: column, row: row, pixelX: max(0, Int(event.mousePosition.x)),
                                          pixelY: max(0, Int(event.mousePosition.y))) { return }
        if event.phase == .began {
            isSelecting = true
            session.terminal.updateSelection(session.selection, action: 0, column: column, row: row)
        } else if isSelecting {
            session.terminal.updateSelection(session.selection, action: 1, column: column, row: row)
        }
        if event.phase == .ended || event.phase == .cancelled { isSelecting = false }
        setNeedsDisplay()
    }

    override func draw(in rect: Rect, with context: UIGraphicsContext) {
        guard let session else { return }
        let snapshot = session.terminal.makeRenderSnapshot(scope: .full)
        let selection = session.terminal.selectionState(session.selection)
        context.drawRect(bounds, color: color(snapshot.backgroundColor))
        for row in snapshot.lines {
            for (column, cell) in row.cells.enumerated() where cell.width > 0 {
                let rect = Rect(x: 6 + Float(column) * cellWidth, y: 4 + Float(row.y) * cellHeight,
                                width: cellWidth * Float(cell.width), height: cellHeight)
                var foreground = resolve(cell.attribute.fg, snapshot: snapshot, foreground: true)
                var background = resolve(cell.attribute.bg, snapshot: snapshot, foreground: false)
                if cell.attribute.style.contains(.inverse) != snapshot.reverseVideo { swap(&foreground, &background) }
                context.drawRect(rect, color: background)
                if selection.spans.contains(where: { $0.row == row.y && column >= $0.startColumn && column < $0.endColumn }) {
                    context.drawRect(rect, color: AdaEngine.Color(red: 0.25, green: 0.45, blue: 0.8).opacity(0.5))
                }
                guard !cell.text.isEmpty, cell.text != " ", !cell.attribute.style.contains(.invisible) else { continue }
                let key = GlyphKey(text: cell.text, foreground: foreground, bold: cell.attribute.style.contains(.bold), width: cell.width)
                let layout: TextLayoutManager
                if let cached = glyphs[key] {
                    layout = cached
                } else {
                    if glyphs.count > 4096 { glyphs.removeAll(keepingCapacity: true) }
                    layout = TextLayoutManager()
                    var attributes = TextAttributeContainer()
                    attributes.font = Font.monospaced(size: 14)
                    attributes.foregroundColor = foreground
                    layout.setTextContainer(TextContainer(text: AttributedText(cell.text, attributes: attributes)))
                    layout.fitToSize(rect.size)
                    glyphs[key] = layout
                }
                // Layout glyphs already use points. A rectangle transform would scale them by the cell size.
                if let line = layout.textLines.first {
                    let ascent = Float(line.typographicBounds.ascent)
                    let descent = Float(line.typographicBounds.descent)
                    var textContext = context
                    textContext.translateBy(x: rect.minX, y: -rect.minY - (cellHeight - ascent - descent) / 2 - ascent)
                    textContext.draw(line)
                }
            }
        }
        if !snapshot.cursor.hidden {
            context.drawRect(Rect(x: 6 + Float(snapshot.cursor.x) * cellWidth, y: 4 + Float(snapshot.cursor.y) * cellHeight + cellHeight - 2,
                                  width: cellWidth, height: 2), color: color(snapshot.cursorColor ?? snapshot.foregroundColor))
        }
        session.terminal.clearUpdateRange()
    }

    private func resolve(_ value: SwiftTerm.Attribute.Color, snapshot: TerminalRenderSnapshot, foreground: Bool) -> AdaEngine.Color {
        switch value {
        case .defaultColor: color(foreground ? snapshot.foregroundColor : snapshot.backgroundColor)
        case .defaultInvertedColor: color(foreground ? snapshot.backgroundColor : snapshot.foregroundColor)
        case let .ansi256(code): color(snapshot.palette[Int(code)])
        case let .trueColor(red, green, blue): AdaEngine.Color(red: Float(red) / 255, green: Float(green) / 255, blue: Float(blue) / 255)
        }
    }

    private func color(_ value: SwiftTerm.Color) -> AdaEngine.Color {
        AdaEngine.Color(red: Float(value.red) / 65535, green: Float(value.green) / 65535, blue: Float(value.blue) / 65535)
    }
}

