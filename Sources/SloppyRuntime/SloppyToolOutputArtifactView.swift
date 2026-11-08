#if canImport(SwiftUI)
import Foundation
import SwiftUI
import Protocols

/// Ready-to-embed output presentation. It reads the host's verified store, without a Core server.
@available(macOS 14, iOS 17, *)
public struct SloppyToolOutputArtifactView: View {
    private let host: SloppyRuntimeHost
    private let workspaceURL: URL
    private let artifact: AgentToolOutputArtifact
    @State private var preview = ""
    @State private var failure: String?
    @State private var exportURL: URL?
    @State private var presentedArtifactID: String?

    public init(host: SloppyRuntimeHost, workspaceURL: URL, artifact: AgentToolOutputArtifact) {
        self.host = host; self.workspaceURL = workspaceURL; self.artifact = artifact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Tool output").font(.headline)
                Spacer()
                Text(artifact.attachment.sizeBytes.formatted(.byteCount(style: .file))).font(.caption)
            }
            if let failure { Text(failure).foregroundStyle(.red) }
            ScrollView([.horizontal, .vertical]) {
                Text(preview).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }.frame(maxHeight: 240)
            if artifact.attachment.sizeBytes > 16_384 { Text("Preview of the first 16 KiB. Export keeps the complete output.").font(.caption) }
            if let exportURL {
                ShareLink("Save or share complete output", item: exportURL)
            } else {
                Button("Prepare complete output") {
                    let requestedID = artifact.attachment.id
                    Task {
                        do {
                            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sloppy-share-" + UUID().uuidString)
                            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                            let file = directory.appendingPathComponent("tool-output.json")
                            do {
                                try await host.exportToolOutput(workspaceURL: workspaceURL, persistedSessionID: artifact.sessionId,
                                    artifactID: artifact.attachment.id, to: file)
                            } catch { try? FileManager.default.removeItem(at: directory); throw error }
                            guard presentedArtifactID == requestedID else {
                                try? FileManager.default.removeItem(at: directory); return
                            }
                            exportURL = file
                        } catch { if presentedArtifactID == requestedID { failure = error.localizedDescription } }
                    }
                }
            }
        }
        .padding(20)
        .foregroundStyle(Color(red: 36 / 255, green: 37 / 255, blue: 33 / 255))
        .background(Color(red: 245 / 255, green: 242 / 255, blue: 233 / 255))
        .task(id: artifact.attachment.id) {
            presentedArtifactID = artifact.attachment.id
            discardExport()
            preview = ""; failure = nil
            do {
                let chunk = try await host.readToolOutput(workspaceURL: workspaceURL, persistedSessionID: artifact.sessionId,
                    artifactID: artifact.attachment.id, limit: 16_384)
                preview = String(decoding: chunk.data, as: UTF8.self)
            } catch { failure = error.localizedDescription }
        }
        .onDisappear {
            presentedArtifactID = nil
            discardExport()
        }
    }

    private func discardExport() {
        guard let exportURL else { return }
        try? FileManager.default.removeItem(at: exportURL.deletingLastPathComponent())
        self.exportURL = nil
    }
}
#endif
