import Foundation

import Protocols

/// Installs on-device recognition (whisper.cpp, ffmpeg, a ggml model) on request from the settings screen.
/// Deterministic and user-initiated: fixed Homebrew formulas and a fixed model catalog, no arbitrary URLs.
actor WhisperInstaller {
    struct CatalogModel: Sendable {
        let id: String
        let title: String
        let fileName: String
        let sizeBytes: Int64
        let recommended: Bool

        var url: URL {
            URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
        }
    }

    static let catalog: [CatalogModel] = [
        .init(id: "large-v3-turbo-q5_0", title: "Large v3 turbo (best accuracy)", fileName: "ggml-large-v3-turbo-q5_0.bin", sizeBytes: 574_041_195, recommended: true),
        .init(id: "small-q5_1", title: "Small (balanced)", fileName: "ggml-small-q5_1.bin", sizeBytes: 190_085_487, recommended: false),
        .init(id: "base-q5_1", title: "Base (fastest, lower accuracy)", fileName: "ggml-base-q5_1.bin", sizeBytes: 59_707_625, recommended: false),
    ]

    static var modelsDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".sloppy/models/whisper", isDirectory: true)
    }

    static func modelPath(for model: CatalogModel) -> String {
        modelsDirectory.appendingPathComponent(model.fileName).path
    }

    /// First installed catalog model, best accuracy first. Used when no model path is configured.
    static func firstInstalledModelPath() -> String? {
        catalog
            .map(modelPath(for:))
            .first { FileManager.default.isReadableFile(atPath: $0) }
    }

    private static let brewEnvironment = [
        "HOMEBREW_NO_AUTO_UPDATE": "1",
        "HOMEBREW_NO_INSTALL_CLEANUP": "1",
        "HOMEBREW_NO_ENV_HINTS": "1",
        "NONINTERACTIVE": "1",
    ]

    private(set) var job = VoiceModeWhisperInstallJob()
    private var task: Task<Void, Never>?

    func currentJob() -> VoiceModeWhisperInstallJob {
        job
    }

    /// Starts an install. Returns false when one is already running.
    func start(model: CatalogModel, whisper: CoreConfig.VoiceMode.Whisper) -> Bool {
        guard job.state != "running" else {
            return false
        }
        job = VoiceModeWhisperInstallJob(state: "running", step: nil, progress: nil, message: nil, model: model.id)
        task = Task { [weak self] in
            await self?.run(model: model, whisper: whisper)
        }
        return true
    }

    private func run(model: CatalogModel, whisper: CoreConfig.VoiceMode.Whisper) async {
        do {
            let brew = ExternalProcessRunner.resolveExecutable(explicit: "", names: ["brew"])

            if ExternalProcessRunner.resolveExecutable(explicit: whisper.executablePath, names: LocalWhisperTranscriber.executableNames) == nil {
                try await brewInstall(formula: "whisper-cpp", step: "whisper_cpp", brew: brew)
            }
            if ExternalProcessRunner.resolveExecutable(explicit: whisper.ffmpegPath, names: LocalWhisperTranscriber.ffmpegNames) == nil {
                try await brewInstall(formula: "ffmpeg", step: "ffmpeg", brew: brew)
            }
            let path = try await downloadModel(model)
            job = VoiceModeWhisperInstallJob(state: "succeeded", step: nil, progress: 1, message: nil, model: model.id, modelPath: path)
        } catch {
            let message = (error as? InstallError)?.message ?? "Installation failed."
            job = VoiceModeWhisperInstallJob(state: "failed", step: job.step, progress: nil, message: message, model: model.id)
        }
    }

    private func brewInstall(formula: String, step: String, brew: String?) async throws {
        guard let brew else {
            throw InstallError(message: "Homebrew was not found. Install it from https://brew.sh or use the manual commands.")
        }
        job = VoiceModeWhisperInstallJob(state: "running", step: step, progress: nil, message: nil, model: job.model)
        let result: ExternalProcessRunner.Result
        do {
            result = try await ExternalProcessRunner.run(
                executable: brew,
                arguments: ["install", formula],
                timeout: 1800,
                environment: Self.brewEnvironment
            )
        } catch {
            throw InstallError(message: "brew install \(formula) did not finish in time.")
        }
        guard result.status == 0 else {
            let detail = String(decoding: result.stderr.suffix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw InstallError(message: "brew install \(formula) failed: \(detail)")
        }
    }

    private func downloadModel(_ model: CatalogModel) async throws -> String {
        let destination = Self.modelPath(for: model)
        if FileManager.default.isReadableFile(atPath: destination) {
            return destination
        }
        try FileManager.default.createDirectory(at: Self.modelsDirectory, withIntermediateDirectories: true)
        let partial = destination + ".part"
        try? FileManager.default.removeItem(atPath: partial)
        job = VoiceModeWhisperInstallJob(state: "running", step: "model", progress: 0, message: nil, model: model.id)

        guard let curl = ExternalProcessRunner.resolveExecutable(explicit: "", names: ["curl"]) else {
            throw InstallError(message: "curl was not found, so the model could not be downloaded.")
        }

        let progressTask = Task { [weak self] in
            while !Task.isCancelled {
                let size = (try? FileManager.default.attributesOfItem(atPath: partial)[.size] as? Int64) ?? 0
                await self?.updateProgress(Double(size) / Double(model.sizeBytes), model: model.id)
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        defer { progressTask.cancel() }

        let result: ExternalProcessRunner.Result
        do {
            result = try await ExternalProcessRunner.run(
                executable: curl,
                arguments: ["-L", "--fail", "--silent", "--show-error", "-o", partial, model.url.absoluteString],
                timeout: 3600
            )
        } catch {
            try? FileManager.default.removeItem(atPath: partial)
            throw InstallError(message: "Model download did not finish in time.")
        }
        guard result.status == 0 else {
            try? FileManager.default.removeItem(atPath: partial)
            let detail = String(decoding: result.stderr.suffix(200), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw InstallError(message: "Model download failed: \(detail)")
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: partial)[.size] as? Int64) ?? 0
        guard size > model.sizeBytes / 2 else {
            try? FileManager.default.removeItem(atPath: partial)
            throw InstallError(message: "Model download was incomplete.")
        }
        try FileManager.default.moveItem(atPath: partial, toPath: destination)
        return destination
    }

    private func updateProgress(_ value: Double, model: String) {
        guard job.state == "running", job.step == "model", job.model == model else {
            return
        }
        job.progress = min(max(value, 0), 0.99)
    }

    struct InstallError: Error {
        let message: String
    }
}
