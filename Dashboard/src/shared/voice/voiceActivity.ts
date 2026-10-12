/**
 * Energy-based voice activity detection for hands-free input (ADR 0006).
 *
 * Deterministic and dependency-free: an adaptive noise floor, hysteresis, a minimum speech length and a
 * silence hangover. While agent audio is playing the threshold is raised so the assistant's own voice is
 * not mistaken for the user, and speech must be sustained longer before it counts as a barge-in.
 */

export type VadEvent =
  | { type: "speech_start" }
  | { type: "speech_end"; speechMs: number; reason: "silence" | "max_length" }
  | { type: "speech_discarded"; speechMs: number }
  | { type: "barge_in" };

export type VadOptions = {
  /** Absolute floor for the speech threshold (RMS, 0..1). */
  minThreshold: number;
  /** Speech threshold as a multiple of the tracked noise floor. */
  floorMultiplier: number;
  /** The "still speaking" threshold as a fraction of the speech threshold (hysteresis). */
  releaseRatio: number;
  /** Speech shorter than this is discarded as a click or cough. */
  minSpeechMs: number;
  /** Silence needed after speech to end the utterance. */
  hangoverMs: number;
  /** Hard cap for one utterance. */
  maxUtteranceMs: number;
  /** Threshold multiplier while the assistant is speaking. */
  playbackMultiplier: number;
  /** Speech sustained this long during playback counts as a barge-in. */
  bargeInMs: number;
};

export const DEFAULT_VAD_OPTIONS: VadOptions = {
  minThreshold: 0.015,
  floorMultiplier: 3,
  releaseRatio: 0.6,
  minSpeechMs: 300,
  hangoverMs: 800,
  maxUtteranceMs: 30000,
  playbackMultiplier: 2.5,
  bargeInMs: 250
};

export class VoiceActivityDetector {
  private readonly options: VadOptions;
  private noiseFloor = 0.004;
  private speaking = false;
  private speechMs = 0;
  private silenceMs = 0;
  private candidateMs = 0;
  private bargedIn = false;

  constructor(options: Partial<VadOptions> = {}) {
    this.options = { ...DEFAULT_VAD_OPTIONS, ...options };
  }

  get isSpeaking(): boolean {
    return this.speaking;
  }

  get floor(): number {
    return this.noiseFloor;
  }

  reset(): void {
    this.speaking = false;
    this.speechMs = 0;
    this.silenceMs = 0;
    this.candidateMs = 0;
    this.bargedIn = false;
  }

  /** Feeds one frame of audio energy. `playbackActive` is true while the assistant is audible. */
  process(rms: number, frameMs: number, playbackActive = false): VadEvent[] {
    const events: VadEvent[] = [];
    const multiplier = playbackActive ? this.options.playbackMultiplier : 1;
    const startThreshold = Math.max(this.options.minThreshold, this.noiseFloor * this.options.floorMultiplier) * multiplier;
    const releaseThreshold = startThreshold * this.options.releaseRatio;

    if (!this.speaking) {
      if (rms >= startThreshold) {
        this.candidateMs += frameMs;
        // Require a short run above threshold so a single loud frame does not open an utterance.
        if (this.candidateMs >= 60) {
          this.speaking = true;
          this.speechMs = this.candidateMs;
          this.silenceMs = 0;
          this.bargedIn = false;
          events.push({ type: "speech_start" });
        }
      } else {
        this.candidateMs = 0;
        // Track the background level only while nobody is speaking; the floor adapts slowly upwards, quickly downwards.
        const rate = rms < this.noiseFloor ? 0.2 : 0.02;
        this.noiseFloor += (rms - this.noiseFloor) * rate;
      }
      return events;
    }

    if (rms >= releaseThreshold) {
      this.speechMs += frameMs + this.silenceMs;
      this.silenceMs = 0;
    } else {
      this.silenceMs += frameMs;
    }

    if (playbackActive && !this.bargedIn && this.speechMs >= this.options.bargeInMs) {
      this.bargedIn = true;
      events.push({ type: "barge_in" });
    }

    const totalMs = this.speechMs + this.silenceMs;
    const ended = this.silenceMs >= this.options.hangoverMs;
    const capped = totalMs >= this.options.maxUtteranceMs;
    if (ended || capped) {
      const speechMs = this.speechMs;
      this.reset();
      if (speechMs >= this.options.minSpeechMs) {
        events.push({ type: "speech_end", speechMs, reason: ended ? "silence" : "max_length" });
      } else {
        events.push({ type: "speech_discarded", speechMs });
      }
    }
    return events;
  }
}
