import Foundation

import Protocols

/// Offline speech-to-text through whisper.cpp (`whisper-cli`). Browser audio (webm/mp4/ogg) is converted
/// to 16 kHz mono WAV with ffmpeg first. No audio leaves the machine running Core (ADR 0005).
struct LocalWhisperTranscriber: VoiceTranscriptionProvider {
    static let executableNames = ["whisper-cli", "whisper-cpp"]
    static let ffmpegNames = ["ffmpeg"]

    struct Paths: Sendable, Equatable {
        let whisper: String
        let ffmpeg: String
        let model: String
    }

    let paths: Paths
    let threads: Int
    var timeout: TimeInterval = 90

    /// Returns resolved tool and model paths, or nil when anything required is missing.
    static func resolvePaths(_ config: CoreConfig.VoiceMode.Whisper) -> Paths? {
        guard let whisper = ExternalProcessRunner.resolveExecutable(explicit: config.executablePath, names: executableNames),
              let ffmpeg = ExternalProcessRunner.resolveExecutable(explicit: config.ffmpegPath, names: ffmpegNames)
        else {
            return nil
        }
        let configured = (config.modelPath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        // An empty model path means "use whatever the installer put in ~/.sloppy/models/whisper".
        let model = configured.isEmpty ? (WhisperInstaller.firstInstalledModelPath() ?? "") : configured
        guard !model.isEmpty, FileManager.default.isReadableFile(atPath: model) else {
            return nil
        }
        return Paths(whisper: whisper, ffmpeg: ffmpeg, model: model)
    }

    func transcribe(request: VoiceModeTranscriptionRequest) async throws -> VoiceModeTranscriptionResponse {
        guard let audio = Data(base64Encoded: request.audioBase64), !audio.isEmpty else {
            throw CoreService.VoiceModeError.invalidPayload
        }

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-whisper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let input = workDirectory.appendingPathComponent(OpenAICompatibleTranscriber.filename(for: request.mimeType))
        let wav = workDirectory.appendingPathComponent("audio.wav")
        try audio.write(to: input)

        let converted = try await run(
            paths.ffmpeg,
            Self.ffmpegArguments(input: input.path, output: wav.path)
        )
        guard converted.status == 0, FileManager.default.fileExists(atPath: wav.path) else {
            throw CoreService.VoiceModeError.requestFailed("whisper_ffmpeg_\(converted.status): \(Self.excerpt(converted.stderr))")
        }

        let result = try await run(
            paths.whisper,
            Self.whisperArguments(model: paths.model, wav: wav.path, language: request.language, prompt: request.prompt, threads: threads)
        )
        guard result.status == 0 else {
            throw CoreService.VoiceModeError.requestFailed("whisper_exit_\(result.status): \(Self.excerpt(result.stderr))")
        }

        return VoiceModeTranscriptionResponse(
            text: Self.cleanTranscript(String(decoding: result.stdout, as: UTF8.self)),
            provider: "whisper",
            model: (paths.model as NSString).lastPathComponent
        )
    }

    static func ffmpegArguments(input: String, output: String) -> [String] {
        ["-nostdin", "-y", "-loglevel", "error", "-i", input, "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", output]
    }

    static func whisperArguments(model: String, wav: String, language: String?, prompt: String?, threads: Int) -> [String] {
        var arguments = ["-m", model, "-f", wav, "-nt", "-np", "-t", String(max(1, threads))]
        let code = language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        arguments += ["-l", code.isEmpty ? "auto" : code]
        if let prompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
            arguments += ["--prompt", prompt]
        }
        return arguments
    }

    /// whisper.cpp prints one segment per line; join them and drop non-speech markers like `[BLANK_AUDIO]`.
    static func cleanTranscript(_ output: String) -> String {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !line.isEmpty && !(line.hasPrefix("[") && line.hasSuffix("]")) && !(line.hasPrefix("(") && line.hasSuffix(")"))
            }
            .joined(separator: " ")
    }

    private func run(_ executable: String, _ arguments: [String]) async throws -> ExternalProcessRunner.Result {
        do {
            return try await ExternalProcessRunner.run(executable: executable, arguments: arguments, timeout: timeout)
        } catch ExternalProcessRunner.RunError.timedOut {
            throw CoreService.VoiceModeError.requestFailed("whisper_timeout")
        }
    }

    private static func excerpt(_ data: Data) -> String {
        String(decoding: data.prefix(240), as: UTF8.self)
    }
}
