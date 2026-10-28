import Foundation
import SwiftUI

enum SidebarProjectDropPlacement: Sendable {
    case before
    case after
}

#if os(macOS)
import Observation
import UniformTypeIdentifiers

enum SidebarProjectDrag {
    static let contentType = UTType(exportedAs: "team.sloppy.sidebar-project", conformingTo: .data)

    static func provider(projectID: String, name: String) -> NSItemProvider {
        let provider = NSItemProvider(item: Data(projectID.utf8) as NSData, typeIdentifier: contentType.identifier)
        provider.suggestedName = name
        return provider
    }
}

@Observable
@MainActor
final class SidebarProjectDropState {
    private(set) var placement: SidebarProjectDropPlacement?

    func update(locationY: CGFloat, height: CGFloat) {
        placement = locationY < height / 2 ? .before : .after
    }

    func reset() { placement = nil }

    func performDrop(providers: [NSItemProvider],
                     move: @MainActor @Sendable @escaping (String, SidebarProjectDropPlacement) -> Bool) -> Bool {
        guard let placement,
              let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(SidebarProjectDrag.contentType.identifier) }) else {
            reset()
            return false
        }
        reset()
        provider.loadDataRepresentation(forTypeIdentifier: SidebarProjectDrag.contentType.identifier) { data, _ in
            guard let data, let projectID = String(data: data, encoding: .utf8), !projectID.isEmpty else { return }
            Task { @MainActor in _ = move(projectID, placement) }
        }
        return true
    }
}

/// Native dragging keeps navigation clicks and section controls independent.
struct SidebarProjectDropTarget: ViewModifier {
    let state: SidebarProjectDropState
    let move: @MainActor @Sendable (String, SidebarProjectDropPlacement) -> Bool
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .overlay(alignment: state.placement == .before ? .top : .bottom) {
                if let placement = state.placement {
                    HStack(spacing: 0) {
                        Circle().frame(width: 6, height: 6)
                        Rectangle().frame(height: 2)
                    }
                    .foregroundStyle(Color.accentColor)
                    .offset(y: placement == .before ? -4 : 4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onDrop(of: [SidebarProjectDrag.contentType], delegate: SidebarProjectDropDelegate(
                state: state, height: height, move: move
            ))
            .onDisappear { state.reset() }
    }
}

private struct SidebarProjectDropDelegate: DropDelegate {
    let state: SidebarProjectDropState
    let height: CGFloat
    let move: @MainActor @Sendable (String, SidebarProjectDropPlacement) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [SidebarProjectDrag.contentType])
    }

    func dropEntered(info: DropInfo) { state.update(locationY: info.location.y, height: height) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        state.update(locationY: info.location.y, height: height)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { state.reset() }

    func performDrop(info: DropInfo) -> Bool {
        state.update(locationY: info.location.y, height: height)
        return state.performDrop(providers: info.itemProviders(for: [SidebarProjectDrag.contentType]), move: move)
    }
}
#endif
