import SwiftUI

/// A range in one rendered selection container, including horizontally scrolling blocks.
public struct TextAnnotationLocation: Sendable, Equatable {
  public let scope: String
  public let content: String
  public let range: NSRange

  public init(scope: String, content: String, range: NSRange) {
    self.scope = scope
    self.content = content
    self.range = range
  }
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  /// Holds a weak view anchor; its rectangle is resolved from the current text layout.
  @MainActor
  public struct TextSelectionContext {
    public let text: String
    public let location: TextAnnotationLocation
    public weak var sourceView: NSView?
    private let resolveRect: @MainActor () -> CGRect

    init(text: String, location: TextAnnotationLocation, sourceView: NSView,
         resolveRect: @escaping @MainActor () -> CGRect) {
      self.text = text
      self.location = location
      self.sourceView = sourceView
      self.resolveRect = resolveRect
    }

    public var sourceRect: CGRect { resolveRect() }

    @discardableResult
    public func show(_ popover: NSPopover) -> Bool {
      guard let sourceView, sourceView.window != nil, !sourceRect.isEmpty else { return false }
      sourceView.scrollToVisible(sourceRect)
      popover.show(relativeTo: sourceRect, of: sourceView, preferredEdge: .maxY)
      return true
    }
  }

  public struct TextAnnotation: Identifiable {
    public let id: UUID
    public let location: TextAnnotationLocation
    let activate: @MainActor (TextSelectionContext) -> Void
    let resolve: @MainActor (TextSelectionContext) -> Void

    public init(id: UUID, location: TextAnnotationLocation,
                activate: @escaping @MainActor (TextSelectionContext) -> Void,
                resolve: @escaping @MainActor (TextSelectionContext) -> Void) {
      self.id = id
      self.location = location
      self.activate = activate
      self.resolve = resolve
    }
  }

  extension EnvironmentValues {
    @Entry var textualTextAnnotations: [TextAnnotation] = []
  }

  extension TextualNamespace where Base: View {
    public func textAnnotations(_ annotations: [TextAnnotation]) -> some View {
      base.environment(\.textualTextAnnotations, annotations)
    }
  }
#endif

extension EnvironmentValues {
  @Entry var textualTextSelectionScope = "root"
}
