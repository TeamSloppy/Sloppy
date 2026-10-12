import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

extension ChatScreenViewModel {
    public func attachProjectFileReference(projectId: String, path: String, type: String) {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }

        let reference = type == "directory"
            ? "@project[\(projectId)]:dir:\(trimmedPath)"
            : "@project[\(projectId)]:file:\(trimmedPath)"
        composerDraft.text = composerDraft.text.isEmpty
            ? reference
            : "\(composerDraft.text)\n\(reference)"
        saveActiveComposerDraft()
    }

    public func attachFileURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let maximumAttachmentSize = Self.maximumAttachmentSize
        Task { @MainActor in
            let results = await Task.detached(priority: .userInitiated) {
                urls.map { url in
                    Self.loadAttachmentResult(
                        from: url,
                        maximumSize: maximumAttachmentSize
                    )
                }
            }.value

            for result in results {
                acceptAttachmentLoadResult(result)
            }
        }
    }

    public func attachData(_ data: Data, suggestedName: String, mimeType: String) {
        guard composerAttachments.count < Self.maximumAttachmentCount else {
            sendErrorMessage = "You can attach up to \(Self.maximumAttachmentCount) files"
            return
        }
        guard data.count <= Self.maximumAttachmentSize else {
            sendErrorMessage = "\(suggestedName) is larger than 25 MB"
            return
        }

        let trimmedName = suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMIMEType = mimeType.trimmingCharacters(in: .whitespacesAndNewlines)
        composerAttachments.append(
            ChatComposerAttachment(
                name: trimmedName.isEmpty ? "Attachment" : trimmedName,
                mimeType: trimmedMIMEType.isEmpty ? "application/octet-stream" : trimmedMIMEType,
                data: data
            )
        )
        sendErrorMessage = nil
        saveActiveComposerDraft()
    }

    public func removeComposerAttachment(id: ChatComposerAttachment.ID) {
        composerAttachments.removeAll { $0.id == id }
        saveActiveComposerDraft()
    }

    @discardableResult
    public func attachItemProviders(_ providers: [NSItemProvider]) -> Bool {
        var didAcceptProvider = false
        let maximumAttachmentSize = Self.maximumAttachmentSize

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                didAcceptProvider = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                    guard let url = Self.fileURL(from: item) else { return }
                    let result = Self.loadAttachmentResult(
                        from: url,
                        maximumSize: maximumAttachmentSize
                    )
                    Task { @MainActor [weak self] in
                        self?.acceptAttachmentLoadResult(result)
                    }
                }
                continue
            }

            let registeredTypes = provider.registeredTypeIdentifiers.compactMap(UTType.init)
            if let directoryType = registeredTypes.first(where: { $0.conforms(to: .directory) }) {
                didAcceptProvider = true
                provider.loadFileRepresentation(forTypeIdentifier: directoryType.identifier) { [weak self] url, _ in
                    guard let url else { return }
                    let result = Self.loadAttachmentResult(
                        from: url,
                        maximumSize: maximumAttachmentSize
                    )
                    Task { @MainActor [weak self] in
                        self?.acceptAttachmentLoadResult(result)
                    }
                }
                continue
            }

            guard let contentType = registeredTypes.first(where: { $0.conforms(to: .image) })
                ?? registeredTypes.first(where: ChatComposerPasteboard.isAttachmentType)
                ?? registeredTypes.first(where: { $0.conforms(to: .data) || $0.conforms(to: .url) }) else {
                continue
            }

            didAcceptProvider = true
            let suggestedName = Self.suggestedAttachmentName(
                providerName: provider.suggestedName,
                contentType: contentType
            )
            provider.loadDataRepresentation(forTypeIdentifier: contentType.identifier) { [weak self] data, _ in
                guard let data else {
                    Task { @MainActor in
                        self?.sendErrorMessage = "Could not load dropped attachment"
                    }
                    return
                }
                Task { @MainActor in
                    if contentType.conforms(to: .text),
                       let text = String(data: data, encoding: .utf8),
                       let payload = WorkspacePanelDragPayload.decode(from: text) {
                        self?.attachProjectFileReference(
                            projectId: payload.projectId,
                            path: payload.path,
                            type: payload.type
                        )
                        return
                    }
                    self?.attachData(
                        data,
                        suggestedName: suggestedName,
                        mimeType: contentType.preferredMIMEType ?? "application/octet-stream"
                    )
                }
            }
        }

        return didAcceptProvider
    }

    private nonisolated static func loadAttachmentResult(
        from url: URL,
        maximumSize: Int
    ) -> ChatComposerAttachmentLoadResult {
        do {
            return .success(
                try ChatComposerAttachmentLoader.load(
                    url: url,
                    maximumSize: maximumSize
                )
            )
        } catch {
            return .failure(
                "Could not attach \(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }

    private func acceptAttachmentLoadResult(_ result: ChatComposerAttachmentLoadResult) {
        switch result {
        case .success(let attachment):
            attachData(
                attachment.data,
                suggestedName: attachment.name,
                mimeType: attachment.mimeType
            )
        case .failure(let message):
            sendErrorMessage = message
        }
    }

    private nonisolated static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data,
           let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) {
            return URL(string: value)
        }
        if let value = item as? String {
            return URL(string: value)
        }
        return nil
    }

    private nonisolated static func suggestedAttachmentName(
        providerName: String?,
        contentType: UTType
    ) -> String {
        let trimmedName = providerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, !trimmedName.isEmpty {
            return trimmedName
        }
        return "Attachment.\(contentType.preferredFilenameExtension ?? "bin")"
    }
}
