import Foundation
import SwiftUI
import SloppyA2UI
import SloppyClientCore
import SloppyClientUI

public struct ChatUISurfacesView: View {
    let apiClient: SloppyAPIClient
    let agentID: String
    let sessionID: String
    @State private var surfaces: [A2UISurfaceSnapshot] = []
    @State private var refreshSequence = 0
    @Environment(\.theme) private var theme
    public init(apiClient: SloppyAPIClient, agentID: String, sessionID: String) {
        self.apiClient = apiClient
        self.agentID = agentID
        self.sessionID = sessionID
    }
    public var body: some View {
        VStack(spacing: 0) {
            if !surfaces.isEmpty {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(surfaces, id: \.surfaceId) { surface in
                            ChatUIForm(surface: surface, scope: apiClient.endpoint.cacheNamespace + ":" + agentID + ":" + sessionID) {
                                submission in
                                _ = try await apiClient.submitUIAction(
                                    agentID: agentID, sessionID: sessionID, surfaceID: surface.surfaceId, submission: submission)
                                try await refresh()
                            }
                        }
                    }.padding(12)
                }
                .frame(maxHeight: 300)
                .background(theme.colors.background)
                .accessibilityIdentifier("a2ui.panel")
            }
        }
        .task(id: apiClient.endpoint.cacheNamespace + ":" + agentID + ":" + sessionID) {
            surfaces = []
            while !Task.isCancelled {
                try? await refresh()
                do { try await Task.sleep(for: .milliseconds(1500)) } catch { break }
            }
        }
    }
    @MainActor private func refresh() async throws {
        refreshSequence += 1
        let sequence = refreshSequence
        let loaded = try await apiClient.fetchUISurfaces(agentID: agentID, sessionID: sessionID)
        guard !Task.isCancelled, sequence == refreshSequence else { return }
        for old in surfaces
        where !loaded.contains(where: { $0.surfaceId == old.surfaceId && $0.isDeleted != true && $0.submittedActionId == nil }) {
            UserDefaults.standard.removeObject(
                forKey: "sloppy.a2ui:" + apiClient.endpoint.cacheNamespace + ":" + agentID + ":" + sessionID + ":" + old.surfaceId)
        }
        surfaces = loaded.filter { (try? $0.validate()) != nil && $0.isDeleted != true && $0.submittedActionId == nil }
    }
}

private struct ChatUIForm: View {
    let surface: A2UISurfaceSnapshot
    let scope: String
    let submit: (A2UISubmission) async throws -> Void
    @State private var draft: A2UIDraft?
    @State private var busy = false
    @State private var error: String?
    @State private var expanded = true
    @Environment(\.theme) private var theme
    private var storageKey: String { "sloppy.a2ui:" + scope + ":" + surface.surfaceId }
    private var current: A2UIDraft { draft ?? .init(surface: surface) }
    private var locked: Bool { busy || surface.submittedActionId != nil || current.pending != nil }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                node("root", depth: 0)
                if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("a2ui.error") }
            }.padding(.top, 10)
        } label: {
            Text(surface.submittedActionId == nil ? "Interactive form" : "Response sent").font(.headline)
        }
        .padding(14)
        .background(theme.colors.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.colors.border, lineWidth: 1))
        .task(id: surface.revision) {
            if draft == nil, let data = UserDefaults.standard.data(forKey: storageKey) {
                draft = try? JSONDecoder().decode(A2UIDraft.self, from: data)
            }
            var next = current
            next.reconcile(surface)
            draft = next
            save()
            if surface.submittedActionId != nil {
                expanded = false
                UserDefaults.standard.removeObject(forKey: storageKey)
            }
        }
    }
    private func save() { if let data = try? JSONEncoder().encode(current) { UserDefaults.standard.set(data, forKey: storageKey) } }
    private func set(_ path: String, _ value: A2UIValue) {
        var next = current
        next.values[path] = value
        draft = next
        save()
    }
    private func textBinding(_ field: A2UIComponent) -> Binding<String> {
        Binding(
            get: {
                let value = current.values[field.binding ?? ""]
                return value?.string ?? value?.number.map { String($0) } ?? ""
            },
            set: { value in
                set(field.binding ?? "", .string(value))
            })
    }
    private func send(_ id: String) {
        guard !busy, surface.submittedActionId == nil, surface.validationErrors(current.values).isEmpty else { return }
        var next = current
        let request = next.submission(for: id, surface: surface)
        draft = next
        save()
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await submit(request) } catch {
                self.error = error.localizedDescription
                if let apiError = error as? APIError, [400, 409].contains(apiError.statusCode ?? 0) {
                    var updated = current
                    updated.pending = nil
                    draft = updated
                    save()
                }
            }
        }
    }
    private func node(_ id: String, depth: Int) -> AnyView {
        guard depth <= 16, let field = surface.components.first(where: { $0.id == id }) else { return AnyView(EmptyView()) }
        let path = field.binding ?? ""
        let problem = surface.validationErrors(current.values)[path]
        switch field.component {
        case .text: return AnyView(Text(field.text ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading))
        case .row:
            return AnyView(
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(field.children ?? [], id: \.self) { child in node(child, depth: depth + 1) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(field.children ?? [], id: \.self) { child in node(child, depth: depth + 1) }
                    }
                })
        case .column:
            return AnyView(
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(field.children ?? [], id: \.self) { child in node(child, depth: depth + 1) }
                })
        case .button:
            return AnyView(
                Button(
                    surface.submittedActionId != nil
                        ? "Response sent" : busy ? "Sending…" : current.pending != nil ? "Retry send" : field.label ?? "Continue"
                ) { send(id) }
                .buttonStyle(.borderedProminent).disabled(
                    busy || surface.submittedActionId != nil || !surface.validationErrors(current.values).isEmpty
                )
                .accessibilityIdentifier("a2ui.button." + id))
        case .checkBox:
            return AnyView(
                VStack(alignment: .leading) {
                    Toggle(field.label ?? "", isOn: Binding(get: { current.values[path]?.boolean == true }, set: { set(path, .bool($0)) }))
                        .disabled(locked)
                        .accessibilityIdentifier("a2ui.field." + id)
                    if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
                })
        case .choicePicker:
            return AnyView(
                VStack(alignment: .leading) {
                    Text(field.label ?? "").font(.subheadline)
                    Menu {
                        ForEach(field.options ?? [], id: \.value) { option in Button(option.label) { set(path, .string(option.value)) } }
                    } label: {
                        Text(field.options?.first(where: { $0.value == current.values[path]?.string })?.label ?? "Choose…")
                    }
                    .disabled(locked).accessibilityIdentifier("a2ui.field." + id)
                    if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
                })
        case .textField:
            return AnyView(
                VStack(alignment: .leading) {
                    Text((field.label ?? "") + (field.required == true ? " *" : "")).font(.subheadline)
                    TextField(field.label ?? "", text: textBinding(field)).textFieldStyle(.roundedBorder).disabled(locked)
                        .accessibilityIdentifier("a2ui.field." + id)
                    if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
                })
        }
    }
}
