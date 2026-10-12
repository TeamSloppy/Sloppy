import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createCoreApi } from "../api/coreApi";
import { normalizeVoiceConfig } from "./voiceModeClient";
import { splitSpeechChunks, markdownToSpeechText } from "./speechText";

export { extractSpeakableSentences, markdownToSpeechText, splitSpeechChunks } from "./speechText";

type QueueItem = { text: string; audio?: Promise<any> };
type Run = { cancelled: boolean; audio: HTMLAudioElement | null; running: boolean; id: string };

export function useVoicePlayback() {
  const coreApi = useMemo(() => createCoreApi(), []);
  const [config, setConfig] = useState<ReturnType<typeof normalizeVoiceConfig> | null>(null);
  const [playingId, setPlayingId] = useState<string | null>(null);
  const [error, setError] = useState("");
  const runRef = useRef<Run | null>(null);
  const queueRef = useRef<QueueItem[]>([]);

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

  const hasBrowserSynthesis = typeof window !== "undefined" && Boolean(window.speechSynthesis);
  const useServer = Boolean(config?.effectiveSpeechProvider);
  const useBrowser = !useServer && Boolean(config?.local.enabled) && hasBrowserSynthesis;
  const available = Boolean(config?.enabled && (useServer || useBrowser));

  const stop = useCallback(() => {
    const run = runRef.current;
    if (run) {
      run.cancelled = true;
      run.audio?.pause();
    }
    runRef.current = null;
    queueRef.current = [];
    if (hasBrowserSynthesis) {
      window.speechSynthesis.cancel();
    }
    setPlayingId(null);
  }, [hasBrowserSynthesis]);

  useEffect(() => stop, [stop]);

  const playItem = useCallback(
    async (run: Run, item: QueueItem) => {
      if (!config) {
        return;
      }
      if (useServer) {
        const response = await item.audio;
        if (run.cancelled) {
          return;
        }
        if (!response?.audioBase64) {
          throw new Error("speech_failed");
        }
        const audio = new Audio(`data:${response.mimeType || "audio/mpeg"};base64,${response.audioBase64}`);
        run.audio = audio;
        await new Promise<void>((resolve, reject) => {
          audio.onended = () => resolve();
          audio.onerror = () => reject(new Error("playback_failed"));
          audio.play().catch(reject);
        });
        return;
      }
      await new Promise<void>((resolve, reject) => {
        const utterance = new SpeechSynthesisUtterance(item.text);
        const voiceName = config.local.voiceName;
        if (voiceName) {
          const match = window.speechSynthesis.getVoices().find((voice) => voice.name === voiceName);
          if (match) {
            utterance.voice = match;
          }
        }
        utterance.rate = config.local.rate;
        utterance.pitch = config.local.pitch;
        utterance.onend = () => resolve();
        utterance.onerror = (event) =>
          event.error === "canceled" || event.error === "interrupted" ? resolve() : reject(new Error(event.error));
        window.speechSynthesis.speak(utterance);
      });
    },
    [config, useServer]
  );

  const pump = useCallback(
    async (run: Run) => {
      run.running = true;
      try {
        while (queueRef.current.length > 0 && !run.cancelled) {
          // Keep the current and next sentence synthesizing while the current one plays.
          for (const pending of queueRef.current.slice(0, 2)) {
            if (useServer && !pending.audio) {
              pending.audio = coreApi.synthesizeVoice({ text: pending.text });
            }
          }
          const item = queueRef.current[0];
          await playItem(run, item);
          if (!run.cancelled) {
            queueRef.current.shift();
          }
        }
      } catch (cause: any) {
        if (!run.cancelled) {
          setError(cause?.name === "NotAllowedError" ? "Browser blocked audio playback. Press play again." : "Could not play the voice reply.");
          queueRef.current = [];
        }
      } finally {
        run.running = false;
        if (runRef.current === run && queueRef.current.length === 0) {
          runRef.current = null;
          setPlayingId(null);
        }
      }
    },
    [coreApi, playItem, useServer]
  );

  /** Queues already-clean text for playback; starts playback if idle. */
  const enqueue = useCallback(
    (id: string, text: string) => {
      const clean = String(text || "").trim();
      if (!available || !clean) {
        return;
      }
      let run = runRef.current;
      if (!run || run.cancelled) {
        run = { cancelled: false, audio: null, running: false, id };
        runRef.current = run;
        queueRef.current = [];
        setError("");
      }
      setPlayingId(run.id);
      queueRef.current.push({ text: clean });
      if (!run.running) {
        void pump(run);
      }
    },
    [available, pump]
  );

  /** Replaces current playback with a whole message. */
  const speak = useCallback(
    async (id: string, markdown: string) => {
      stop();
      for (const chunk of splitSpeechChunks(markdownToSpeechText(markdown))) {
        enqueue(id, chunk);
      }
    },
    [enqueue, stop]
  );

  return { available, playingId, error, speak, enqueue, stop };
}
