import Foundation
import SwiftUI

@MainActor
final class MobileRefreshRunner {
    private var task: Task<Void, Never>?
    private var taskID: UUID?

    func run(_ action: @escaping @MainActor () async -> Void) async {
        if let task {
            await task.value
            return
        }
        let id = UUID()
        // SwiftUI may cancel its refresh handler when the displayed content changes.
        let next = Task { @MainActor in await action() }
        taskID = id
        task = next
        await next.value
        if taskID == id {
            task = nil
            taskID = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        taskID = nil
    }
}

@MainActor
private final class MobileRefreshScope {
    private var actions: [UUID: @MainActor () async -> Void] = [:]
    private let runner = MobileRefreshRunner()

    func register(_ id: UUID, action: @escaping @MainActor () async -> Void) {
        actions[id] = action
    }

    func remove(_ id: UUID) {
        actions[id] = nil
        runner.cancel()
    }

    func refresh() async {
        let pending = Array(actions.values)
        await runner.run {
            for action in pending {
                guard !Task.isCancelled else { return }
                await action()
            }
        }
    }

    func cancel() { runner.cancel() }
}

private extension EnvironmentValues {
    @Entry var mobileRefreshScope: MobileRefreshScope?
}

private struct MobileRefreshModifier: ViewModifier {
    let revision: String?
    let action: @MainActor () async -> Void
    @State private var runner = MobileRefreshRunner()

    func body(content: Content) -> some View {
#if os(iOS)
        content
            .scrollBounceBehavior(.always, axes: .vertical)
            .refreshable { await runner.run(action) }
            .onChange(of: revision) { runner.cancel() }
            .onDisappear { runner.cancel() }
#else
        content.refreshable { await action() }
#endif
    }
}

private struct MobileRefreshContainerModifier: ViewModifier {
    let isEnabled: Bool
    @State private var scope = MobileRefreshScope()

    func body(content: Content) -> some View {
#if os(iOS)
        if isEnabled {
            content
                .refreshable { await scope.refresh() }
                .environment(\.mobileRefreshScope, scope)
                .scrollBounceBehavior(.always, axes: .vertical)
                .onDisappear { scope.cancel() }
        } else {
            content
        }
#else
        content
#endif
    }
}

private struct MobileRefreshSectionModifier: ViewModifier {
    let action: @MainActor () async -> Void
    @Environment(\.mobileRefreshScope) private var scope
    @State private var id = UUID()

    func body(content: Content) -> some View {
#if os(iOS)
        content
            .onAppear { scope?.register(id, action: action) }
            .onDisappear { scope?.remove(id) }
#else
        content
#endif
    }
}

public extension View {
    /// Adds native refresh to the scroll view and keeps its request alive across UI updates.
    func mobileRefreshable(id: String? = nil, _ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(MobileRefreshModifier(revision: id, action: action))
    }

    /// Hosts refresh actions supplied by sections inside this scroll view.
    func mobileRefreshContainer(isEnabled: Bool = true) -> some View {
        modifier(MobileRefreshContainerModifier(isEnabled: isEnabled))
    }

    /// Supplies a refresh action to an enclosing mobileRefreshContainer.
    func mobileRefreshSection(_ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(MobileRefreshSectionModifier(action: action))
    }
}
