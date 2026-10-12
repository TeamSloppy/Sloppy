import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createCoreApi } from "../api/coreApi";
import { normalizeVoiceConfig } from "./voiceModeClient";

export type VoiceInputState = "idle" | "recording" | "transcribing" | "error";

const RECORDER_MIME_CANDIDATES = ["audio/webm;codecs=opus", "audio/webm", "audio/mp4", "audio/ogg;codecs=opus"];

function pickRecorderMimeType(): string {
  const recorder = (typeof window !== "undefined" ? (window as any).MediaRecorder : null) as any;
  if (!recorder || typeof recorder.isTypeSupported !== "function") {
    return "";
  }
  return RECORDER_MIME_CANDIDATES.find((candidate) => recorder.isTypeSupported(candidate)) || "";
}

function blobToBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(reader.error);
    reader.onload = () => {
      const result = String(reader.result || "");
      resolve(result.slice(result.indexOf(",") + 1));
    };
    reader.readAsDataURL(blob);
  });
}

function languageHint(language: string): string | undefined {
  const value = String(language || "auto").trim();
  if (!value || value === "auto") {
    return undefined;
  }
  // Transcription APIs expect ISO-639-1 ("ru"), while settings may hold a locale ("ru-RU").
  return value.split("-")[0].toLowerCase();
}

/**
 * Push-to-talk dictation: records with MediaRecorder, sends audio to Core
 * (`/v1/voice/transcriptions`) and hands the transcript to `onTranscript`.
 * State is driven only by recorder/API results, never by transcript text.
 */
export function useVoiceInput({ onTranscript }: { onTranscript: (text: string) => void }) {
  const coreApi = useMemo(() => createCoreApi(), []);
  const [config, setConfig] = useState<ReturnType<typeof normalizeVoiceConfig> | null>(null);
  const [state, setState] = useState<VoiceInputState>("idle");
  const [error, setError] = useState("");
  const recorderRef = useRef<MediaRecorder | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const onTranscriptRef = useRef(onTranscript);
  onTranscriptRef.current = onTranscript;

  useEffect(() => {
    let cancelled = false;
    coreApi
      .fetchVoiceConfig()
      .then((response) => {
        if (!cancelled && response) {
          setConfig(normalizeVoiceConfig(response));
        }
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [coreApi]);

  const releaseStream = useCallback(() => {
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
  }, []);

  useEffect(() => releaseStream, [releaseStream]);

  const hasRecorder = typeof window !== "undefined" && Boolean((window as any).MediaRecorder && navigator.mediaDevices?.getUserMedia);
  const serverTranscription = Boolean(config?.effectiveTranscriptionProvider);
  const available = Boolean(config?.enabled && hasRecorder && serverTranscription);

  let unavailableReason = "";
  if (!config?.enabled) {
    unavailableReason = "Voice mode is off. Enable it in Settings → Voice Mode.";
  } else if (!serverTranscription) {
    unavailableReason = "Configure OpenAI or Groq transcription in Settings → Voice Mode.";
  } else if (!hasRecorder) {
    unavailableReason = "This browser cannot record audio.";
  }

  const fail = useCallback(
    (message: string) => {
      releaseStream();
      recorderRef.current = null;
      setError(message);
      setState("error");
    },
    [releaseStream]
  );

  const start = useCallback(async () => {
    if (!available || state === "recording" || state === "transcribing") {
      return;
    }
    setError("");
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      streamRef.current = stream;
      const mimeType = pickRecorderMimeType();
      const recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);
      chunksRef.current = [];
      recorder.ondataavailable = (event) => {
        if (event.data && event.data.size > 0) {
          chunksRef.current.push(event.data);
        }
      };
      recorder.onerror = () => fail("Recording failed.");
      recorder.onstop = async () => {
        const type = recorder.mimeType || mimeType || "audio/webm";
        const blob = new Blob(chunksRef.current, { type });
        chunksRef.current = [];
        releaseStream();
        recorderRef.current = null;
        if (blob.size === 0) {
          setState("idle");
          return;
        }
        setState("transcribing");
        try {
          const response = await coreApi.transcribeVoice({
            audioBase64: await blobToBase64(blob),
            mimeType: type.split(";")[0],
            language: languageHint(config?.input.language || "auto")
          });
          const text = String(response?.text || "").trim();
          if (!response) {
            fail("Transcription failed. Check the voice provider settings.");
            return;
          }
          if (text) {
            onTranscriptRef.current(text);
          }
          setState("idle");
        } catch {
          fail("Transcription failed.");
        }
      };
      recorderRef.current = recorder;
      recorder.start();
      setState("recording");
    } catch (cause: any) {
      fail(cause?.name === "NotAllowedError" ? "Microphone permission was denied." : "Could not start recording.");
    }
  }, [available, config, coreApi, fail, releaseStream, state]);

  const stop = useCallback(() => {
    const recorder = recorderRef.current;
    if (recorder && recorder.state !== "inactive") {
      recorder.stop();
    }
  }, []);

  const cancel = useCallback(() => {
    const recorder = recorderRef.current;
    if (recorder) {
      recorder.onstop = null;
      if (recorder.state !== "inactive") {
        recorder.stop();
      }
    }
    chunksRef.current = [];
    releaseStream();
    recorderRef.current = null;
    setState("idle");
  }, [releaseStream]);

  const toggle = useCallback(() => {
    if (state === "recording") {
      stop();
    } else if (state === "error") {
      setError("");
      setState("idle");
      void start();
    } else {
      void start();
    }
  }, [start, state, stop]);

  return { state, error, available, unavailableReason, toggle, cancel };
}
