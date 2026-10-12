import Foundation

import Protocols

/// Offline TTS through the macOS `say` tool. Text is passed on stdin, never as an argument.
struct SystemSpeechProvider: VoiceSpeechProvider {
    static let executablePath = "/usr/bin/say"

    let defaultVoice: String

    static var isAvailable: Bool {
        #if os(macOS)
        FileManager.default.isExecutableFile(atPath: executablePath)
        #else
        false
        #endif
    }

    func speech(request: VoiceModeSpeechRequest) async throws -> VoiceModeSpeechResponse {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw CoreService.VoiceModeError.invalidPayload
        }
        guard Self.isAvailable else {
            throw CoreService.VoiceModeError.providerNotConfigured("system")
        }
        let requested = request.voice?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let voice = requested.isEmpty ? defaultVoice : requested
        let executable = Self.executablePath
        let audio = try await Task.detached(priority: .userInitiated) {
            try Self.run(executable: executable, voice: voice, text: text)
        }.value
        return VoiceModeSpeechResponse(
            audioBase64: audio.base64EncodedString(),
            mimeType: "audio/mp4",
            provider: "system",
            model: "macos-say",
            voice: voice.isEmpty ? "default" : voice
        )
    }

    private static func run(executable: String, voice: String, text: String) throws -> Data {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("sloppy-say-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: output) }

        var arguments = ["-o", output.path, "--file-format=m4af", "--data-format=aac", "-f", "-"]
        if !voice.isEmpty {
            arguments = ["-v", voice] + arguments
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors

        try process.run()
        input.fileHandleForWriting.write(Data(text.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile().prefix(240), as: UTF8.self)
            throw CoreService.VoiceModeError.requestFailed("system_say_\(process.terminationStatus): \(message)")
        }
        let data = try Data(contentsOf: output)
        guard !data.isEmpty else {
            throw CoreService.VoiceModeError.requestFailed("system_say_empty_output")
        }
        return data
    }
}
