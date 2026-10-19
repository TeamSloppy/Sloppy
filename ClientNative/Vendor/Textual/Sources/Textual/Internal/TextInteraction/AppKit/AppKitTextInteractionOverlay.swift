#if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit) && !targetEnvironment(macCatalyst)
  import SwiftUI

  // MARK: - Overview
  //
  // `AppKitTextInteractionOverlay` bridges the shared `TextSelectionModel` into an `NSView`.
  //
  // The overlay reads exclusion rectangles for hit-testing. This allows embedded scrollable regions (like
  // code blocks) to receive touch events while the parent handles text selection. The view also
  // manages selection gestures, keyboard-driven updates, and context menus while SwiftUI renders
  // the text.

  struct AppKitTextInteractionOverlay: NSViewRepresentable {
    @Environment(\.textualTextSelectionActions) private var selectionActions
    @Environment(\.textualTextAnnotations) private var annotations
    @Environment(\.textualTextSelectionScope) private var selectionScope

    private let model: TextSelectionModel
    private let overflowFrames: [CGRect]

    init(model: TextSelectionModel, overflowFrames: [CGRect]) {
      self.model = model
      self.overflowFrames = overflowFrames
    }

    func makeNSView(context: Context) -> NSTextInteractionView {
      let view = NSTextInteractionView(
        model: model,
        exclusionRects: overflowFrames,
        openURL: context.environment.openURL,
        selectionActions: selectionActions
      )
      view.annotationScope = selectionScope
      view.annotations = annotations
      return view
    }

    func updateNSView(_ nsView: NSTextInteractionView, context: Context) {
      nsView.model = model
      nsView.exclusionRects = overflowFrames
      nsView.openURL = context.environment.openURL
      nsView.selectionActions = selectionActions
      nsView.annotationScope = selectionScope
      nsView.annotations = annotations
    }
  }
#endif
