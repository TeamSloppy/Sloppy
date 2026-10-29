import Foundation
import Protocols
import SloppyA2UI
import TauTUI

struct SloppyTUIForm {
    var surface: AgentUISurfaceSnapshot
    var draft: A2UIDraft
    var agentID: String
    var sessionID: String
    var draftNamespace = ""
    var storageKey: String { "sloppy.tui.a2ui:" + draftNamespace + ":" + agentID + ":" + sessionID + ":" + surface.surfaceId }
    static func submissionWasRejected(_ error: Error) -> Bool {
        if let error = error as? CoreService.AgentUIError {
            switch error {
            case .invalidAction, .actionConflict, .revisionConflict, .forbidden: return true
            }
        }
        if case CLIClientError.httpError(let status, _) = error { return [400, 403, 409].contains(status) }
        if case RemoteSloppyTUIBackendError.httpError(let status) = error { return [400, 403, 409].contains(status) }
        return false
    }
    var available: [AgentUISurfaceSnapshot] = []
    var focus = 0
    var busy = false
    var error: String?
    var fields: [A2UIComponent] {
        var result: [A2UIComponent] = []
        func visit(_ id: String) {
            guard let node = surface.components.first(where: { $0.id == id }) else { return }
            if node.isInput || node.component == .button { result.append(node) }
            for child in node.children ?? [] { visit(child) }
        }
        visit("root")
        return result
    }
    var markdown: String {
        var lines = [
            "# Interactive form", "\(available.count) form(s) · Ctrl+N/P: switch forms",
            "Tab / Shift-Tab: move · arrows: choose · Enter: next/send · Escape: return to chat", "",
        ]
        for node in surface.components.filter({ $0.component == .text }).prefix(2) { lines.append(String((node.text ?? "").prefix(120))) }
        for (index, field) in fields.enumerated() where abs(index - focus) <= 1 {
            let value = draft.values[field.binding ?? ""]
            var displayed = ""
            if field.component == .button {
                displayed =
                    surface.submittedActionId != nil ? "Response sent" : draft.pending != nil ? "Retry send" : field.label ?? "Continue"
            } else if field.component == .choicePicker {
                displayed = field.options?.first(where: { $0.value == value?.string })?.label ?? "Choose with arrows"
            } else if let flag = value?.boolean {
                displayed = flag ? "[x]" : "[ ]"
            } else if let text = value?.string {
                displayed = text
            } else if let number = value?.number {
                displayed = String(number)
            }
            lines.append("\(index == focus ? "→" : " ") \(String((field.label ?? field.id).prefix(28))): \(String(displayed.prefix(40)))")
        }
        lines += surface.validationErrors(draft.values).values.sorted()
        if let error { lines.append(error) }
        if busy { lines.append("Sending…") }
        return lines.joined(separator: "\n\n")
    }
}

@MainActor extension SloppyTUIScreen {
    func openUIForm() async {
        do {
            let forms = try await service.listAgentUISurfaces(agentID: agent.id, sessionID: session.id)
            guard
                let surface = forms.last(where: {
                    $0.submittedActionId == nil && $0.components.contains(where: { $0.component == .button })
                }), (try? surface.validate()) != nil
            else {
                showSystemNotice("No pending interactive form in this chat.")
                return
            }
            let key = "sloppy.tui.a2ui:" + service.uiDraftNamespace + ":" + agent.id + ":" + session.id + ":" + surface.surfaceId
            var draft =
                UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(A2UIDraft.self, from: $0) }
                ?? .init(surface: surface)
            draft.reconcile(surface)
            uiForm = .init(
                surface: surface, draft: draft, agentID: agent.id, sessionID: session.id, draftNamespace: service.uiDraftNamespace,
                available: forms.filter { $0.submittedActionId == nil && $0.isDeleted != true })
            uiRefreshTask?.cancel()
            uiRefreshTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(2)) } catch { break }
                    guard let self, let target = self.uiForm else { break }
                    if let latest = try? await self.service.listAgentUISurfaces(agentID: target.agentID, sessionID: target.sessionID) {
                        guard var form = self.uiForm, form.agentID == target.agentID, form.sessionID == target.sessionID,
                            form.surface.surfaceId == target.surface.surfaceId
                        else { continue }
                        form.available = latest.filter { $0.submittedActionId == nil && $0.isDeleted != true }
                        if let surface = latest.first(where: { $0.surfaceId == form.surface.surfaceId }),
                            surface.revision >= form.surface.revision
                        {
                            form.draft.reconcile(surface)
                            form.surface = surface
                        } else if !latest.contains(where: { $0.surfaceId == form.surface.surfaceId }) {
                            form.surface.isDeleted = true
                            form.error = "This interface was closed."
                        }
                        self.uiForm = form
                        self.saveUIForm()
                        self.requestRender()
                    }
                }
            }
            requestRender()
        } catch { showSystemNotice("Cannot open UI: \(error.localizedDescription)") }
    }
    func saveUIForm() {
        guard let form = uiForm else { return }
        let key = form.storageKey
        if form.surface.submittedActionId != nil {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(form.draft) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    func handleUIForm(_ input: TerminalInput) -> Bool {
        guard var form = uiForm else { return false }
        if case .key(.escape, _) = input {
            saveUIForm()
            uiForm = nil
            uiRefreshTask?.cancel()
            requestRender()
            return true
        }
        if case .key(.character(let character), let modifiers) = input, modifiers.contains(.control), character == "n" || character == "p",
            !form.available.isEmpty, !form.busy
        {
            saveUIForm()
            let old = form.available.firstIndex(where: { $0.surfaceId == form.surface.surfaceId }) ?? 0
            let next = form.available[(old + (character == "n" ? 1 : form.available.count - 1)) % form.available.count]
            let key = "sloppy.tui.a2ui:" + form.draftNamespace + ":" + form.agentID + ":" + form.sessionID + ":" + next.surfaceId
            var draft =
                UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(A2UIDraft.self, from: $0) }
                ?? .init(surface: next)
            draft.reconcile(next)
            form.surface = next
            form.draft = draft
            form.focus = 0
            form.error = nil
            uiForm = form
            requestRender()
            return true
        }
        guard form.surface.isDeleted != true, !form.busy, !form.fields.isEmpty, form.surface.submittedActionId == nil else { return true }
        form.focus = min(form.focus, form.fields.count - 1)
        let field = form.fields[form.focus]
        let path = field.binding ?? ""
        func setText(_ value: String) { form.draft.values[path] = .string(value) }
        if case .paste(let text) = input, field.component == .textField, form.draft.pending == nil {
            setText((form.draft.values[path]?.string ?? form.draft.values[path]?.number.map { String($0) } ?? "") + text)
        } else if case .key(let key, let modifiers) = input {
            switch key {
            case .tab: form.focus = (form.focus + (modifiers.contains(.shift) ? form.fields.count - 1 : 1)) % form.fields.count
            case .enter:
                if field.component == .button {
                    guard form.surface.validationErrors(form.draft.values).isEmpty else { return true }
                    let submission = form.draft.submission(for: field.id, surface: form.surface)
                    form.busy = true
                    form.error = nil
                    uiForm = form
                    saveUIForm()
                    requestRender()
                    let target = form
                    Task { @MainActor in
                        do {
                            let receipt = try await self.service.submitAgentUIAction(
                                agentID: target.agentID, sessionID: target.sessionID, surfaceID: target.surface.surfaceId,
                                submission: submission)
                            if self.uiForm?.sessionID == target.sessionID, self.uiForm?.surface.surfaceId == target.surface.surfaceId {
                                self.uiForm?.surface.revision = receipt.revision
                                self.uiForm?.surface.submittedActionId = submission.actionId
                                self.uiForm?.draft.pending = nil
                            }
                        } catch {
                            if self.uiForm?.sessionID == target.sessionID, self.uiForm?.surface.surfaceId == target.surface.surfaceId {
                                self.uiForm?.error = error.localizedDescription
                                if SloppyTUIForm.submissionWasRejected(error) { self.uiForm?.draft.pending = nil }
                            }
                        }
                        if self.uiForm?.sessionID == target.sessionID, self.uiForm?.surface.surfaceId == target.surface.surfaceId {
                            self.uiForm?.busy = false
                            self.saveUIForm()
                            self.requestRender()
                        }
                    }
                    return true
                }
                form.focus = (form.focus + 1) % form.fields.count
            case .arrowUp, .arrowDown, .arrowLeft, .arrowRight:
                guard form.draft.pending == nil else { return true }
                if field.component == .checkBox {
                    form.draft.values[path] = .bool(form.draft.values[path]?.boolean != true)
                } else if field.component == .choicePicker, let options = field.options, !options.isEmpty {
                    let old = options.firstIndex(where: { $0.value == form.draft.values[path]?.string }) ?? -1
                    let delta: Int
                    switch key {
                    case .arrowUp, .arrowLeft: delta = -1
                    default: delta = 1
                    }
                    form.draft.values[path] = .string(options[(old + delta + options.count) % options.count].value)
                } else {
                    switch key {
                    case .arrowUp, .arrowLeft: form.focus = (form.focus + form.fields.count - 1) % form.fields.count
                    default: form.focus = (form.focus + 1) % form.fields.count
                    }
                }
            case .delete where field.component == .textField && form.draft.pending == nil:
                setText("")
            case .character("u") where modifiers.contains(.control) && field.component == .textField && form.draft.pending == nil:
                setText("")
            case .backspace where field.component == .textField && form.draft.pending == nil:
                var text = form.draft.values[path]?.string ?? form.draft.values[path]?.number.map { String($0) } ?? ""
                if !text.isEmpty { text.removeLast() }
                setText(text)
            case .character(let character) where form.draft.pending == nil:
                if field.component == .checkBox && character == " " {
                    form.draft.values[path] = .bool(form.draft.values[path]?.boolean != true)
                } else if field.component == .textField && !modifiers.contains(.control) {
                    let text = form.draft.values[path]?.string ?? form.draft.values[path]?.number.map { String($0) } ?? ""
                    if text.utf8.count < 16_384 { setText(text + String(character)) }
                }
            default: break
            }
        }
        uiForm = form
        saveUIForm()
        requestRender()
        return true
    }
}
