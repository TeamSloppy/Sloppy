import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createCoreApi } from "../api/coreApi";
import { bytesToBase64, floatToPcm16, pcm16ToWav, resampleTo, WORKLET_SOURCE } from "./audioUtils";
import { VoiceActivityDetector } from "./voiceActivity";
import { normalizeVoiceConfig } from "./voiceModeClient";

export type HandsFreeState = "off" | "starting" | "listening" | "hearing" | "transcribing" | "error";

const TRANSCRIPTION_SAMPLE_RATE = 16000;
const PREROLL_MS = 450;

export type HandsFreeOptions = {
  /** Called with each recognized utterance. `autoSend` reflects the Voice Mode input settings. */
  onUtterance: (text: string, meta: { autoSend: boolean }) => void;
  /** True while assistant audio is audible, so the detector can raise its threshold and detect barge-in. */
  isPlaybackActive?: () => boolean;
  /** Called once when the user starts talking over assistant audio. */
  onBargeIn?: () => void;
};

function concatFrames(frames: Float32Array[]): Float32Array {
  const total = frames.reduce((sum, frame) => sum + frame.length, 0);
  const merged = new Float32Array(total);
  let offset = 0;
  for (const frame of frames) {
    merged.set(frame, offset);
    offset += frame.length;
  }
  return merged;
}

function rmsOf(frame: Float32Array): number {
  let sum = 0;
  for (let i = 0; i < frame.length; i += 1) {
    sum += frame[i] * frame[i];
  }
  return Math.sqrt(sum / Math.max(1, frame.length));
}

function languageHint(language: string): string | undefined {
  const value = String(language || "auto").trim();
  return !value || value === "auto" ? undefined : value.split("-")[0].toLowerCase();
}

/**
 * Hands-free conversation input: continuous capture, voice activity detection, one transcription request
 * per utterance. State comes from the detector and request results, never from transcript text.
 */
export function useHandsFree(options: HandsFreeOptions) {
  const coreApi = useMemo(() => createCoreApi(), []);
  const optionsRef = useRef(options);
  optionsRef.current = options;

  const [config, setConfig] = useState<ReturnType<typeof normalizeVoiceConfig> | null>(null);
  const [state, setState] = useState<HandsFreeState>("off");
  const [error, setError] = useState("");

  const streamRef = useRef<MediaStream | null>(null);
  const contextRef = useRef<AudioContext | null>(null);
  const hearingRef = useRef(false);
  const pendingRef = useRef(0);
  const activeRef = useRef(false);
  const queueRef = useRef<Promise<void>>(Promise.resolve());
  const configRef = useRef(config);
  configRef.current = config;

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

  const hasAudio =
    typeof window !== "undefined" &&
    Boolean(window.AudioContext && (window as any).AudioWorklet !== undefined && navigator.mediaDevices?.getUserMedia);
  const available = Boolean(config?.enabled && config.effectiveTranscriptionProvider && hasAudio);
  const autoSend = Boolean(config && config.input.mode === "auto_submit" && config.input.previewBeforeSend === false);

  let unavailableReason = "";
  if (!config?.enabled) {
    unavailableReason = "Voice mode is off. Enable it in Settings → Voice Mode.";
  } else if (!config.effectiveTranscriptionProvider) {
    unavailableReason = "Configure speech recognition (OpenAI, Groq or on-device) in Settings → Voice Mode.";
  } else if (!hasAudio) {
    unavailableReason = "This browser does not support continuous audio capture.";
  }

  const refreshState = useCallback(() => {
    if (!activeRef.current) {
      return;
    }
    setState(hearingRef.current ? "hearing" : pendingRef.current > 0 ? "transcribing" : "listening");
  }, []);

  const transcribeUtterance = useCallback(
    (samples: Float32Array, sampleRate: number) => {
      pendingRef.current += 1;
      refreshState();
      // Utterances are transcribed in order so replies keep the order in which they were spoken.
      queueRef.current = queueRef.current.then(async () => {
        try {
          const pcm = floatToPcm16(resampleTo(samples, sampleRate, TRANSCRIPTION_SAMPLE_RATE));
          const wav = pcm16ToWav(pcm, TRANSCRIPTION_SAMPLE_RATE);
          const response = await coreApi.transcribeVoice({
            audioBase64: bytesToBase64(wav),
            mimeType: "audio/wav",
            language: languageHint(configRef.current?.input.language || "auto")
          });
          if (!activeRef.current) {
            return;
          }
          if (!response) {
            setError("Transcription failed. Check the voice provider settings.");
          } else {
            const text = String(response.text || "").trim();
            if (text) {
              setError("");
              optionsRef.current.onUtterance(text, {
                autoSend: Boolean(
                  configRef.current && configRef.current.input.mode === "auto_submit" && configRef.current.input.previewBeforeSend === false
                )
              });
            }
          }
        } catch {
          if (activeRef.current) {
            setError("Transcription failed.");
          }
        } finally {
          pendingRef.current -= 1;
          refreshState();
        }
      });
    },
    [coreApi, refreshState]
  );

  const teardown = useCallback(() => {
    activeRef.current = false;
    hearingRef.current = false;
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
    contextRef.current?.close().catch(() => {});
    contextRef.current = null;
  }, []);

  useEffect(() => teardown, [teardown]);

  const stop = useCallback(() => {
    teardown();
    setState("off");
  }, [teardown]);

  const start = useCallback(async () => {
    if (!available || activeRef.current) {
      return;
    }
    setError("");
    setState("starting");
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true }
      });
      streamRef.current = stream;
      const context = new AudioContext();
      contextRef.current = context;
      const workletUrl = URL.createObjectURL(new Blob([WORKLET_SOURCE], { type: "application/javascript" }));
      try {
        await context.audioWorklet.addModule(workletUrl);
      } finally {
        URL.revokeObjectURL(workletUrl);
      }

      const detector = new VoiceActivityDetector();
      const preroll: Float32Array[] = [];
      let prerollMs = 0;
      let utterance: Float32Array[] | null = null;
      const sampleRate = context.sampleRate;

      const node = new AudioWorkletNode(context, "sloppy-pcm-capture");
      node.port.onmessage = (event: MessageEvent<Float32Array>) => {
        if (!activeRef.current) {
          return;
        }
        const frame = event.data;
        const frameMs = (frame.length / sampleRate) * 1000;
        preroll.push(frame);
        prerollMs += frameMs;
        while (prerollMs > PREROLL_MS && preroll.length > 1) {
          prerollMs -= (preroll.shift() as Float32Array).length / sampleRate * 1000;
        }

        const playbackActive = Boolean(optionsRef.current.isPlaybackActive?.());
        for (const vadEvent of detector.process(rmsOf(frame), frameMs, playbackActive)) {
          if (vadEvent.type === "speech_start") {
            utterance = [...preroll];
            hearingRef.current = true;
            refreshState();
          } else if (vadEvent.type === "barge_in") {
            optionsRef.current.onBargeIn?.();
          } else {
            const finished = utterance;
            utterance = null;
            hearingRef.current = false;
            if (vadEvent.type === "speech_end" && finished) {
              transcribeUtterance(concatFrames(finished), sampleRate);
            }
            refreshState();
          }
        }
        if (utterance && detector.isSpeaking && utterance[utterance.length - 1] !== frame) {
          utterance.push(frame);
        }
      };

      context.createMediaStreamSource(stream).connect(node);
      activeRef.current = true;
      setState("listening");
    } catch (cause: any) {
      teardown();
      setError(cause?.name === "NotAllowedError" ? "Microphone permission was denied." : "Could not start hands-free mode.");
      setState("error");
    }
  }, [available, refreshState, teardown, transcribeUtterance]);

  return { state, error, available, unavailableReason, autoSend, active: state !== "off" && state !== "error", start, stop };
}
