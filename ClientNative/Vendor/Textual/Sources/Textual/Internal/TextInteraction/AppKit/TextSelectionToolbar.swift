#if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit) && !targetEnvironment(macCatalyst)
  import SwiftUI

  @MainActor
  final class TextSelectionToolbar {
    private(set) var panel: NSPanel?
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    func show(actions: [TextSelectionAction], context: TextSelectionContext) {
      close()
      let actions = actions.filter(\.showsInToolbar)
      guard !actions.isEmpty, let source = context.sourceView, let window = source.window,
        !context.sourceRect.intersection(source.visibleRect).isEmpty else { return }

      let scheme: ColorScheme = source.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
      let host = NSHostingView(rootView: SelectionToolbarButtons(actions: actions) { [weak self] action in
        self?.close()
        action.perform(with: context)
      }.preferredColorScheme(scheme))
      let size = host.fittingSize
      let anchor = window.convertToScreen(source.convert(context.sourceRect, to: nil))
      let screen = window.screen?.visibleFrame ?? anchor.insetBy(dx: -500, dy: -500)
      let x = min(max(anchor.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
      let y = anchor.maxY + size.height + 6 <= screen.maxY - 8
        ? anchor.maxY + 6 : anchor.minY - size.height - 6
      let panel = NSPanel(contentRect: NSRect(origin: CGPoint(x: x, y: y), size: size),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      panel.backgroundColor = .clear
      panel.isOpaque = false
      panel.hasShadow = true
      panel.hidesOnDeactivate = true
      panel.becomesKeyOnlyIfNeeded = true
      panel.isReleasedWhenClosed = false
      panel.contentView = host
      self.panel = panel
      window.addChildWindow(panel, ordered: .above)
      panel.orderFront(nil)

      eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
        guard let self, let panel = self.panel else { return event }
        if event.type == .keyDown, event.keyCode == 53 {
          self.close()
          return nil
        }
        if event.window !== panel { self.close() }
        return event
      }
      for name in [NSWindow.didResizeNotification, NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated { self?.close() }
        })
      }
    }

    func close() {
      if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
      eventMonitor = nil
      for observer in observers { NotificationCenter.default.removeObserver(observer) }
      observers = []
      if let panel {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.contentView = nil
      }
      panel = nil
    }
  }

  private struct SelectionToolbarButtons: View {
    let actions: [TextSelectionAction]
    let perform: (TextSelectionAction) -> Void

    var body: some View {
      HStack(spacing: 0) {
        ForEach(actions.indices, id: \.self) { index in
          if index > 0 {
            Rectangle().fill(.primary.opacity(0.12)).frame(width: 1)
          }
          Button { perform(actions[index]) } label: {
            Text(actions[index].title)
              .font(.system(size: 13))
              .padding(.horizontal, 10)
              .padding(.vertical, 7)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("textual.selection.action.\(index)")
        }
      }
      .fixedSize(horizontal: true, vertical: false)
      .frame(height: 30)
      .foregroundStyle(.primary)
      .background(Color(nsColor: .controlBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.14), lineWidth: 1) }
    }
  }
#endif
