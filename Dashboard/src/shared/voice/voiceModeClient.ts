type VoiceConfigRecord = Record<string, any>;

export function normalizeVoiceConfig(config: VoiceConfigRecord = {}) {
  return {
    enabled: Boolean(config.enabled),
    effectiveProvider: config.effectiveProvider === "openai" ? "openai" : "local",
    input: {
      mode: config.input?.mode === "auto_submit" ? "auto_submit" : "push_to_talk",
      language: String(config.input?.language || "auto"),
      previewBeforeSend: config.input?.previewBeforeSend !== false
    },
    local: {
      enabled: config.local?.enabled !== false,
      voiceName: String(config.local?.voiceName || ""),
      rate: Number.isFinite(Number(config.local?.rate)) ? Number(config.local.rate) : 1,
      pitch: Number.isFinite(Number(config.local?.pitch)) ? Number(config.local.pitch) : 1
    }
  };
}

export function browserVoiceSupport(windowLike: any = window) {
  return {
    recognition: typeof windowLike.SpeechRecognition === "function" || typeof windowLike.webkitSpeechRecognition === "function",
    synthesis: Boolean(windowLike.speechSynthesis),
    recorder: Boolean(windowLike.MediaRecorder && windowLike.navigator?.mediaDevices?.getUserMedia)
  };
}
