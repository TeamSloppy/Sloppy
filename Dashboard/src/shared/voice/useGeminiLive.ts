import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createCoreApi } from "../api/coreApi";
import { base64ToPcm16, bytesToBase64, floatToPcm16, resampleTo, WORKLET_SOURCE } from "./audioUtils";
import { normalizeVoiceConfig } from "./voiceModeClient";

export type GeminiLiveState = "idle" | "connecting" | "live" | "error";
export type GeminiLiveLine = { id: number; role: "user" | "model"; text: string };

const INPUT_SAMPLE_RATE = 16000;
const DEFAULT_OUTPUT_SAMPLE_RATE = 24000;
const SEND_FRAME_SAMPLES = 2048;

/** Tells Gemini how to hand real work to the Sloppy agent. Sent only when the host can run `ask_agent`. */
const AGENT_INSTRUCTION = [
  "You are the voice interface of the Sloppy agent.",
  "Answer simple conversational questions yourself, briefly.",
  "For anything that needs files, code, tools, memory, web search or taking action, call the ask_agent tool with a clear, self-contained task, then tell the user in one short sentence that you started.",
  "Messages that begin with [Sloppy agent finished] or [Sloppy agent failed] are system reports from the agent, not from the user: tell the user the outcome in one or two spoken sentences."
].join(" ");

const ASK_AGENT_DECLARATION = {
  name: "ask_agent",
  description:
    "Hand a task to the Sloppy agent, which has the user's files, tools, memory and projects. It runs in the background and its result is reported back to you later.",
  parameters: {
    type: "OBJECT",
    properties: {
      task: { type: "STRING", description: "A clear, self-contained description of what the agent should do." }
    },
    required: ["task"]
  }
};

export type GeminiLiveOptions = {
  /** Runs a task on the agent and resolves with its final answer. Rejects with an Error when it cannot run. */
  onAskAgent?: (task: string) => Promise<string>;
  /** Called when a conversational turn completes, with the text spoken by each side. */
  onTurn?: (turn: { user: string; model: string }) => void;
};



function rateFromMime(mimeType: string): number {
  const match = /rate=(\d+)/.exec(String(mimeType || ""));
  return match ? Number(match[1]) : DEFAULT_OUTPUT_SAMPLE_RATE;
}

/**
 * Browser-direct Gemini Live session (ADR 0007). Core mints a single-use token; this hook streams
 * microphone PCM to the Live API and plays back audio. Conversation state comes from server fields
 * (setupComplete, turnComplete, interrupted), never from transcript text.
 */
export function useGeminiLive(options: GeminiLiveOptions = {}) {
  const optionsRef = useRef(options);
  optionsRef.current = options;
  const userTurnTextRef = useRef("");
  const modelTurnTextRef = useRef("");
  const coreApi = useMemo(() => createCoreApi(), []);
  const [config, setConfig] = useState<ReturnType<typeof normalizeVoiceConfig> | null>(null);
  const [state, setState] = useState<GeminiLiveState>("idle");
  const [error, setError] = useState("");
  const [lines, setLines] = useState<GeminiLiveLine[]>([]);
  const [speaking, setSpeaking] = useState(false);

  const socketRef = useRef<WebSocket | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const captureContextRef = useRef<AudioContext | null>(null);
  const playbackContextRef = useRef<AudioContext | null>(null);
  const sourcesRef = useRef<Set<AudioBufferSourceNode>>(new Set());
  const nextStartRef = useRef(0);
  const readyRef = useRef(false);
  const lineIdRef = useRef(0);
  const lastRoleRef = useRef<"user" | "model" | null>(null);
  const timeoutRef = useRef<number | null>(null);

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
    Boolean(window.AudioContext && (window as any).AudioWorklet !== undefined && navigator.mediaDevices?.getUserMedia && window.WebSocket);
  const available = Boolean(config?.enabled && config.effectiveRealtimeProvider && hasAudio);
  let unavailableReason = "";
  if (!config?.enabled) {
    unavailableReason = "Voice mode is off. Enable it in Settings → Voice Mode.";
  } else if (!config.effectiveRealtimeProvider) {
    unavailableReason = "Enable Live conversation with a Gemini key in Settings → Voice Mode.";
  } else if (!hasAudio) {
    unavailableReason = "This browser does not support live audio.";
  }

  const stopPlayback = useCallback(() => {
    sourcesRef.current.forEach((source) => {
      try {
        source.stop();
      } catch {
        // Already stopped.
      }
    });
    sourcesRef.current.clear();
    nextStartRef.current = 0;
    setSpeaking(false);
  }, []);

  const teardown = useCallback(() => {
    readyRef.current = false;
    if (timeoutRef.current != null) {
      window.clearTimeout(timeoutRef.current);
      timeoutRef.current = null;
    }
    const socket = socketRef.current;
    socketRef.current = null;
    if (socket) {
      socket.onmessage = null;
      socket.onclose = null;
      socket.onerror = null;
      try {
        socket.close();
      } catch {
        // Already closed.
      }
    }
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
    captureContextRef.current?.close().catch(() => {});
    captureContextRef.current = null;
    stopPlayback();
    playbackContextRef.current?.close().catch(() => {});
    playbackContextRef.current = null;
    lastRoleRef.current = null;
  }, [stopPlayback]);

  useEffect(() => teardown, [teardown]);

  const appendTranscript = useCallback((role: "user" | "model", text: string) => {
    if (!text) {
      return;
    }
    if (role === "user") {
      userTurnTextRef.current += text;
    } else {
      modelTurnTextRef.current += text;
    }
    setLines((previous) => {
      const last = previous[previous.length - 1];
      if (last && lastRoleRef.current === role && last.role === role) {
        return [...previous.slice(0, -1), { ...last, text: last.text + text }];
      }
      lineIdRef.current += 1;
      return [...previous.slice(-19), { id: lineIdRef.current, role, text }];
    });
    lastRoleRef.current = role;
  }, []);

  const playChunk = useCallback((base64: string, mimeType: string) => {
    const context = playbackContextRef.current;
    if (!context) {
      return;
    }
    const pcm = base64ToPcm16(base64);
    if (pcm.length === 0) {
      return;
    }
    const buffer = context.createBuffer(1, pcm.length, rateFromMime(mimeType));
    const channel = buffer.getChannelData(0);
    for (let i = 0; i < pcm.length; i += 1) {
      channel[i] = pcm[i] / 0x8000;
    }
    const source = context.createBufferSource();
    source.buffer = buffer;
    source.connect(context.destination);
    const startAt = Math.max(context.currentTime + 0.02, nextStartRef.current);
    source.start(startAt);
    nextStartRef.current = startAt + buffer.duration;
    sourcesRef.current.add(source);
    setSpeaking(true);
    source.onended = () => {
      sourcesRef.current.delete(source);
      if (sourcesRef.current.size === 0) {
        setSpeaking(false);
      }
    };
  }, []);

  const sendJson = useCallback((payload: unknown) => {
    const socket = socketRef.current;
    if (socket && socket.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify(payload));
    }
  }, []);

  /**
   * ask_agent returns to Gemini immediately so the conversation never blocks on long agent work
   * (async function calling is not available on every Live model). The agent's result is injected
   * later as a text input, and the model narrates it.
   */
  const handleToolCall = useCallback(
    (call: any) => {
      const onAskAgent = optionsRef.current.onAskAgent;
      if (call?.name !== "ask_agent" || !onAskAgent) {
        sendJson({
          toolResponse: { functionResponses: [{ id: call?.id, name: call?.name, response: { error: "unknown_tool" } }] }
        });
        return;
      }
      const task = String(call.args?.task || "").trim();
      if (!task) {
        sendJson({
          toolResponse: { functionResponses: [{ id: call.id, name: call.name, response: { error: "empty_task" } }] }
        });
        return;
      }
      sendJson({
        toolResponse: {
          functionResponses: [
            { id: call.id, name: call.name, response: { status: "started", note: "The agent is working in the background. Its result will be reported to you." } }
          ]
        }
      });
      onAskAgent(task)
        .then((result) => {
          sendJson({ realtimeInput: { text: `[Sloppy agent finished]\n${String(result || "The agent finished without a text answer.")}` } });
        })
        .catch((cause: any) => {
          const reason = String(cause?.message || "unknown_error");
          sendJson({ realtimeInput: { text: `[Sloppy agent failed]\n${reason}` } });
        });
    },
    [sendJson]
  );

  const handleServerMessage = useCallback(
    (message: any) => {
      if (message?.setupComplete) {
        readyRef.current = true;
        setState("live");
        return;
      }
      for (const call of message?.toolCall?.functionCalls || []) {
        handleToolCall(call);
      }
      const content = message?.serverContent;
      if (!content) {
        return;
      }
      if (content.interrupted) {
        stopPlayback();
      }
      for (const part of content.modelTurn?.parts || []) {
        if (part?.inlineData?.data) {
          playChunk(part.inlineData.data, part.inlineData.mimeType);
        }
      }
      if (content.inputTranscription?.text) {
        appendTranscript("user", content.inputTranscription.text);
      }
      if (content.outputTranscription?.text) {
        appendTranscript("model", content.outputTranscription.text);
      }
      if (content.turnComplete) {
        lastRoleRef.current = null;
        const user = userTurnTextRef.current.trim();
        const model = modelTurnTextRef.current.trim();
        userTurnTextRef.current = "";
        modelTurnTextRef.current = "";
        if (user || model) {
          optionsRef.current.onTurn?.({ user, model });
        }
      }
    },
    [appendTranscript, handleToolCall, playChunk, stopPlayback]
  );

  const fail = useCallback(
    (message: string) => {
      teardown();
      setError(message);
      setState("error");
    },
    [teardown]
  );

  const stop = useCallback(() => {
    teardown();
    setState("idle");
  }, [teardown]);

  const start = useCallback(async () => {
    if (!available || state === "connecting" || state === "live") {
      return;
    }
    setError("");
    setLines([]);
    userTurnTextRef.current = "";
    modelTurnTextRef.current = "";
    setState("connecting");
    try {
      const session: any = await coreApi.createRealtimeVoiceSession();
      if (!session?.token) {
        fail("Could not start the live session. Check the Gemini settings.");
        return;
      }

      const stream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true }
      });
      streamRef.current = stream;

      playbackContextRef.current = new AudioContext({ sampleRate: DEFAULT_OUTPUT_SAMPLE_RATE });
      const capture = new AudioContext({ sampleRate: INPUT_SAMPLE_RATE });
      captureContextRef.current = capture;
      const workletUrl = URL.createObjectURL(new Blob([WORKLET_SOURCE], { type: "application/javascript" }));
      try {
        await capture.audioWorklet.addModule(workletUrl);
      } finally {
        URL.revokeObjectURL(workletUrl);
      }

      const socket = new WebSocket(`${session.websocketUrl}?access_token=${encodeURIComponent(session.token)}`);
      socketRef.current = socket;

      const modelName = String(session.model).startsWith("models/") ? session.model : `models/${session.model}`;
      socket.onopen = () => {
        const setup: Record<string, any> = {
          model: modelName,
          generationConfig: {
            responseModalities: ["AUDIO"],
            speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: session.voice } } }
          },
          inputAudioTranscription: {},
          outputAudioTranscription: {}
        };
        const canAskAgent = Boolean(optionsRef.current.onAskAgent);
        const instruction = [String(session.systemInstruction || "").trim(), canAskAgent ? AGENT_INSTRUCTION : ""]
          .filter(Boolean)
          .join("\n\n");
        if (instruction) {
          setup.systemInstruction = { parts: [{ text: instruction }] };
        }
        if (canAskAgent) {
          setup.tools = [{ functionDeclarations: [ASK_AGENT_DECLARATION] }];
        }
        socket.send(JSON.stringify({ setup }));
      };
      socket.onmessage = async (event) => {
        try {
          const raw = typeof event.data === "string" ? event.data : await (event.data as Blob).text();
          handleServerMessage(JSON.parse(raw));
        } catch {
          // Ignore malformed frames.
        }
      };
      socket.onerror = () => fail("Live connection failed.");
      socket.onclose = () => {
        if (socketRef.current === socket) {
          teardown();
          setState("idle");
        }
      };

      const source = capture.createMediaStreamSource(stream);
      const node = new AudioWorkletNode(capture, "sloppy-pcm-capture");
      let pending: Float32Array[] = [];
      let pendingLength = 0;
      node.port.onmessage = (event: MessageEvent<Float32Array>) => {
        if (!readyRef.current || socket.readyState !== WebSocket.OPEN) {
          return;
        }
        pending.push(event.data);
        pendingLength += event.data.length;
        if (pendingLength < SEND_FRAME_SAMPLES) {
          return;
        }
        const merged = new Float32Array(pendingLength);
        let offset = 0;
        for (const chunk of pending) {
          merged.set(chunk, offset);
          offset += chunk.length;
        }
        pending = [];
        pendingLength = 0;
        const pcm = floatToPcm16(resampleTo(merged, capture.sampleRate, INPUT_SAMPLE_RATE));
        socket.send(
          JSON.stringify({
            realtimeInput: {
              audio: { data: bytesToBase64(new Uint8Array(pcm.buffer)), mimeType: `audio/pcm;rate=${INPUT_SAMPLE_RATE}` }
            }
          })
        );
      };
      source.connect(node);

      const expiresAtMs = Date.parse(session.expiresAt);
      if (Number.isFinite(expiresAtMs)) {
        timeoutRef.current = window.setTimeout(() => {
          stop();
        }, Math.max(1000, expiresAtMs - Date.now()));
      }
    } catch (cause: any) {
      fail(cause?.name === "NotAllowedError" ? "Microphone permission was denied." : "Could not start the live session.");
    }
  }, [available, coreApi, fail, handleServerMessage, state, stop, teardown]);

  const toggle = useCallback(() => {
    if (state === "live" || state === "connecting") {
      stop();
    } else {
      void start();
    }
  }, [start, state, stop]);

  return { state, error, lines, speaking, available, unavailableReason, start, stop, toggle };
}
