import AdaEngine
import Foundation

@MainActor
struct AdaUIInspectionService {
    private let appWorlds: AppWorlds

    init(appWorlds: AppWorlds) {
        self.appWorlds = appWorlds
    }

    func listWindows() -> [UIWindowSummary] {
        self.allWindows().map { self.makeWindowSnapshot($0).summary }
    }

    func getWindow(windowID: Int?) throws -> UIWindowSnapshot {
        let window = try self.resolveWindow(windowID: windowID)
        return self.makeWindowSnapshot(window)
    }

    func getTree(windowID: Int?) throws -> UIWindowSnapshot {
        try self.getWindow(windowID: windowID)
    }

    func getNode(windowID: Int?, selector: UINodeSelector) throws -> UINodeSnapshot {
        try self.resolveUniqueMatch(windowID: windowID, selector: selector).snapshot
    }

    func findNodes(windowID: Int?, selector: UINodeSelector) throws -> [UINodeSnapshot] {
        let window = try self.resolveWindow(windowID: windowID)
        return self.matches(in: window, selector: selector).map(\.snapshot)
    }

    func hitTest(windowID: Int?, point: Point) throws -> UIHitTestResult {
        let window = try self.resolveWindow(windowID: windowID)
        let event = MouseEvent(
            window: window.id,
            button: .left,
            mousePosition: point,
            phase: .began,
            modifierKeys: [],
            time: 0
        )

        if let hitView = window.hitTest(point, with: event),
           let container = self.container(owning: hitView) ?? self.containers(in: window).first(where: { $0.uiHitTest(at: point) != nil }),
           let result = container.uiHitTest(at: point) {
            return result
        }

        throw AdaMCPError.uiNodeNotFound("hit_test@\(point.x),\(point.y)")
    }

    func getLayoutDiagnostics(windowID: Int?, selector: UINodeSelector?, subtreeDepth: Int?) throws -> UILayoutDiagnostics {
        let window = try self.resolveWindow(windowID: windowID)
        let container: any UIInspectableViewContainer

        if let selector {
            container = try self.resolveUniqueMatch(windowID: window.id.id, selector: selector).container
        } else {
            container = try self.primaryContainer(in: window)
        }

        do {
            return try container.uiLayoutDiagnostics(matching: selector, subtreeDepth: subtreeDepth)
        } catch let error as UIInspectionError {
            throw self.map(error)
        }
    }

    func setDebugOverlay(windowID: Int?, mode: UIDebugOverlayMode) throws -> UIActionResult {
        let window = try self.resolveWindow(windowID: windowID)
        let containers = self.containers(in: window)
        for container in containers {
            container.uiSetDebugOverlay(mode)
        }

        let focusedNode = containers.lazy.compactMap { container in
            try? container.uiLayoutDiagnostics(matching: nil, subtreeDepth: 0).focusedNode
        }.compactMap { $0 }.first

        return UIActionResult(
            action: "set_debug_overlay",
            windowId: window.id.id,
            target: nil,
            focusedNode: focusedNode,
            overlayMode: mode,
            viewportSize: window.frame.size
        )
    }

    func focusNode(windowID: Int?, selector: UINodeSelector) throws -> UIActionResult {
        let match = try self.resolveUniqueMatch(windowID: windowID, selector: selector)
        do {
            return try match.container.uiFocusNode(matching: .runtimeID(match.snapshot.runtimeId))
        } catch let error as UIInspectionError {
            throw self.map(error)
        }
    }

    func focusNext(windowID: Int?) throws -> UIActionResult {
        let window = try self.resolveWindow(windowID: windowID)
        let container = try self.primaryContainer(in: window)
        return container.uiFocusNext() ?? UIActionResult(
            action: "focus_next",
            windowId: window.id.id,
            target: nil,
            focusedNode: nil,
            overlayMode: container.uiInspectionOverlayMode,
            viewportSize: window.frame.size
        )
    }

    func focusPrevious(windowID: Int?) throws -> UIActionResult {
        let window = try self.resolveWindow(windowID: windowID)
        let container = try self.primaryContainer(in: window)
        return container.uiFocusPrevious() ?? UIActionResult(
            action: "focus_previous",
            windowId: window.id.id,
            target: nil,
            focusedNode: nil,
            overlayMode: container.uiInspectionOverlayMode,
            viewportSize: window.frame.size
        )
    }

    func scrollToNode(windowID: Int?, selector: UINodeSelector) throws -> UIActionResult {
        let match = try self.resolveUniqueMatch(windowID: windowID, selector: selector)
        do {
            return try match.container.uiScrollToNode(matching: .runtimeID(match.snapshot.runtimeId))
        } catch let error as UIInspectionError {
            throw self.map(error)
        }
    }

    func tapNode(windowID: Int?, selector: UINodeSelector) throws -> UIActionResult {
        let match = try self.resolveUniqueMatch(windowID: windowID, selector: selector)
        do {
            return try match.container.uiTapNode(matching: .runtimeID(match.snapshot.runtimeId))
        } catch let error as UIInspectionError {
            throw self.map(error)
        }
    }

    private func windowManager() -> UIWindowManager? {
        self.appWorlds.getResource(WindowManagerResource.self)?.windowManager ?? UIWindowManager.shared
    }

    private func allWindows() -> [UIWindow] {
        guard let windowManager = self.windowManager() else {
            return []
        }

        return windowManager.windows.values
            .map(\.value)
            .sorted { $0.id.id < $1.id.id }
    }

    private func resolveWindow(windowID: Int?) throws -> UIWindow {
        let windows = self.allWindows()
        guard !windows.isEmpty else {
            throw AdaMCPError.uiUnavailable
        }

        if let windowID {
            guard let window = windows.first(where: { $0.id.id == windowID }) else {
                throw AdaMCPError.uiWindowNotFound(windowID)
            }
            return window
        }

        if let activeWindow = self.windowManager()?.activeWindow {
            return activeWindow
        }

        return windows[0]
    }

    private func containers(in window: UIWindow) -> [any UIInspectableViewContainer] {
        window.uiInspectableContainers()
    }

    private func primaryContainer(in window: UIWindow) throws -> any UIInspectableViewContainer {
        let containers = self.containers(in: window)
        guard !containers.isEmpty else {
            throw AdaMCPError.uiUnavailable
        }

        if let focusedContainer = containers.first(where: {
            (try? $0.uiLayoutDiagnostics(matching: nil, subtreeDepth: 0).focusedNode) != nil
        }) {
            return focusedContainer
        }

        return containers[0]
    }

    private func makeWindowSnapshot(_ window: UIWindow) -> UIWindowSnapshot {
        let containers = self.containers(in: window)
        let roots = containers.flatMap { $0.uiTreeRoots() }
        return UIWindowSnapshot(
            summary: UIWindowSummary(
                windowId: window.id.id,
                title: window.title,
                frame: window.frame,
                isActive: window.isActive,
                overlayMode: containers.first?.uiInspectionOverlayMode ?? .off,
                rootCount: roots.count
            ),
            roots: roots
        )
    }

    private func matches(
        in window: UIWindow,
        selector: UINodeSelector
    ) -> [(container: any UIInspectableViewContainer, snapshot: UINodeSnapshot)] {
        self.containers(in: window).flatMap { container in
            container.uiFindNodes(matching: selector).map { snapshot in
                (container, snapshot)
            }
        }
    }

    private func resolveUniqueMatch(
        windowID: Int?,
        selector: UINodeSelector
    ) throws -> (container: any UIInspectableViewContainer, snapshot: UINodeSnapshot) {
        let window = try self.resolveWindow(windowID: windowID)
        let matches = self.matches(in: window, selector: selector)

        guard let first = matches.first else {
            throw AdaMCPError.uiNodeNotFound(selector.externalValue)
        }

        guard matches.count == 1 else {
            throw AdaMCPError.uiNodeAmbiguous(
                selector: selector.externalValue,
                candidates: matches.map { $0.snapshot.summary }
            )
        }

        return first
    }

    private func container(owning view: UIView?) -> (any UIInspectableViewContainer)? {
        var current = view
        while let currentView = current {
            if let container = currentView as? any UIInspectableViewContainer {
                return container
            }
            current = currentView.parentView
        }
        return nil
    }

    private func map(_ error: UIInspectionError) -> AdaMCPError {
        switch error {
        case .nodeNotFound(let selector):
            .uiNodeNotFound(selector)
        case .ambiguousSelector(let selector, let candidates):
            .uiNodeAmbiguous(selector: selector, candidates: candidates)
        case .scrollContainerNotFound(let selector):
            .uiScrollContainerNotFound(selector)
        case .noFocusableNode(let selector):
            .uiNoFocusableNode(selector)
        }
    }
}

private extension UINodeSnapshot {
    var summary: UINodeSummary {
        UINodeSummary(
            runtimeId: self.runtimeId,
            accessibilityIdentifier: self.accessibilityIdentifier,
            nodeType: self.nodeType,
            viewType: self.viewType,
            frame: self.frame,
            absoluteFrame: self.absoluteFrame,
            canBecomeFocused: self.canBecomeFocused,
            isFocused: self.isFocused,
            isHidden: self.isHidden,
            isInteractable: self.isInteractable
        )
    }
}
