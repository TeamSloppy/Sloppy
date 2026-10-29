import Foundation
import Observation
import SloppyClientCore

@Observable @MainActor
final class WorkspaceCanvasModel {
    let service: WorkspaceService
    var workspace: CanvasWorkspaceSummary?
    var document: CanvasWorkspaceDocument?
    var selection: String?
    var error: String?
    var isLoading = false
    var isSaving = false
    var zoom: Double = 1
    var text = ""
    var x = "0"
    var y = "0"
    var width = "220"
    var height = "160"
    var chatSession: ChatSessionSummary?
    private var generation = 0

    init(service: WorkspaceService) { self.service = service }
    var selected: CanvasWorkspaceElement? { document?.elements.first { $0.id == selection } }

    func open(_ workspace: CanvasWorkspaceSummary) async {
        generation += 1
        let request = generation
        if self.workspace?.id != workspace.id { chatSession = nil }
        self.workspace = workspace
        document = nil
        selection = nil
        error = nil
        isLoading = true
        defer { if request == generation { isLoading = false } }
        do {
            let document = try await service.canvasDocument(workspaceID: workspace.id)
            guard request == generation else { return }
            self.document = document
        } catch { if request == generation { self.error = error.localizedDescription } }
    }

    func close() { generation += 1; workspace = nil; document = nil; selection = nil; chatSession = nil; isLoading = false }
    func select(_ element: CanvasWorkspaceElement) {
        selection = element.id
        text = element.title
        x = String(format: "%.2f", element.bounds.x); y = String(format: "%.2f", element.bounds.y)
        width = String(element.bounds.width); height = String(element.bounds.height)
    }

    func add(_ kind: CanvasWorkspaceElementKind) async {
        guard let document, !isSaving else { return }
        let offset = Double(document.elements.count % 8) * 28
        let element = CanvasWorkspaceElement(id: "el-\(UUID().uuidString.lowercased())", kind: kind,
            bounds: .init(x: 60 + offset, y: 60 + offset, width: kind == .frame ? 520 : 220, height: kind == .text ? 100 : 160),
            zIndex: (document.elements.map(\.zIndex).max() ?? 0) + 1, data: ["text": .string("New \(kind.rawValue)")])
        if await commit([.init(kind: .createElement, element: element)], summary: "Added \(kind.rawValue)") { select(element) }
    }

    func saveSelection() async {
        guard var element = selected else { return }
        guard let x = Double(x), x.isFinite, let y = Double(y), y.isFinite,
              let width = Double(width), width.isFinite, width >= 20, width <= 10000,
              let height = Double(height), height.isFinite, height >= 20, height <= 10000 else {
            error = "Enter valid coordinates and a size between 20 and 10000."; return
        }
        element.data["text"] = .string(text)
        element.bounds = .init(x: x, y: y, width: width, height: height)
        _ = await commit([.init(kind: .updateElement, element: element)], summary: "Updated element")
    }

    func move(_ id: String, dx: Double, dy: Double) async {
        guard var element = document?.elements.first(where: { $0.id == id }) else { return }
        element.bounds.x += dx / zoom; element.bounds.y += dy / zoom
        if await commit([.init(kind: .updateElement, element: element)], summary: "Moved element") { select(element) }
    }

    func deleteSelection() async {
        guard let selection else { return }
        if await commit([.init(kind: .deleteElement, targetId: selection)], summary: "Deleted element") { self.selection = nil }
    }

    @discardableResult
    func commit(_ operations: [CanvasWorkspaceOperation], summary: String) async -> Bool {
        guard let document, let workspace, !isSaving else { return false }
        let requestGeneration = generation
        let ids = Set(operations.compactMap { $0.element?.id ?? $0.targetId })
        let expected = Dictionary(uniqueKeysWithValues: document.elements.filter { ids.contains($0.id) }.map { ($0.id, $0.revision) })
        let request = CanvasWorkspaceTransactionRequest(id: "tx-\(UUID().uuidString)", baseRevision: document.revision,
            expectedElementRevisions: expected, operations: operations, summary: summary)
        isSaving = true; error = nil
        defer { isSaving = false }
        do {
            _ = try await service.commitCanvas(workspaceID: workspace.id, request: request)
            // Reload authoritative revisions, including revisions assigned to created elements.
            let saved = try await service.canvasDocument(workspaceID: workspace.id)
            guard requestGeneration == generation else { return false }
            self.document = saved
            return true
        } catch {
            guard requestGeneration == generation else { return false }
            self.error = error.localizedDescription
            if let latest = try? await service.canvasDocument(workspaceID: workspace.id), requestGeneration == generation {
                self.document = latest
            }
            return false
        }
    }
}
