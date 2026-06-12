const HOVER_SOUND_SELECTOR = [
  ".hover-levitate",
  "button",
  "a[href]",
  "input:not([type=\"hidden\"])",
  "textarea",
  "[role=\"button\"]",
  "[role=\"link\"]",
  "[data-hover-sound]"
].join(", ");

const DISABLED_HOVER_SOUND_SELECTOR = [
  "[disabled]",
  "[aria-disabled=\"true\"]",
  ".disabled",
  "[data-hover-sound=\"off\"]",
  "[data-hover-sound=\"false\"]"
].join(", ");

export const HOVER_SOUND_URLS = [
  "/sounds/lil-pip.wav",
  "/sounds/teeny-tiny-button-press.wav"
];
export const HOVER_SOUND_URL = HOVER_SOUND_URLS[0];
export const HOVER_SOUND_THROTTLE_MS = 45;
export const HOVER_SOUND_PREFERENCE_EVENT = "sloppy:hover-sounds-enabled";
export const HOVER_SOUND_STORAGE_KEY = "sloppy_hover_sounds_enabled";

export function loadHoverSoundPreference(storage: Pick<Storage, "getItem"> | null | undefined = globalThis.localStorage): boolean {
  try {
    return storage?.getItem(HOVER_SOUND_STORAGE_KEY) === "true";
  } catch {
    return false;
  }
}

export function resolveHoverSoundTarget(target: unknown): unknown | null {
  if (!target || typeof (target as any).closest !== "function") {
    return null;
  }

  if ((target as any).closest(DISABLED_HOVER_SOUND_SELECTOR)) {
    return null;
  }

  const hoverTarget = (target as any).closest(HOVER_SOUND_SELECTOR);
  if (!hoverTarget) {
    return null;
  }

  if (typeof hoverTarget.getAttribute === "function") {
    const mode = String(hoverTarget.getAttribute("data-hover-sound") || "").trim().toLowerCase();
    if (mode === "off" || mode === "false") {
      return null;
    }
  }

  return hoverTarget;
}

export function calculateHoverPlaybackRate(random: () => number = Math.random): number {
  return Number((0.82 + random() * 0.42).toFixed(2));
}

export function chooseHoverSoundUrl(random: () => number = Math.random): string {
  const index = Math.min(HOVER_SOUND_URLS.length - 1, Math.floor(random() * HOVER_SOUND_URLS.length));
  return HOVER_SOUND_URLS[index];
}

export function emitHoverSoundPreferenceChanged(enabled: boolean, target: EventTarget | null | undefined = globalThis.window) {
  target?.dispatchEvent(new CustomEvent(HOVER_SOUND_PREFERENCE_EVENT, { detail: { enabled } }));
}

export function persistHoverSoundPreference(
  enabled: boolean,
  storage: Pick<Storage, "setItem"> | null | undefined = globalThis.localStorage,
  target: EventTarget | null | undefined = globalThis.window
) {
  try {
    storage?.setItem(HOVER_SOUND_STORAGE_KEY, enabled ? "true" : "false");
  } catch {
    // Local storage can be unavailable in private or embedded contexts.
  }
  emitHoverSoundPreferenceChanged(enabled, target);
}

export function playHoverSound(options: {
  audioFactory?: (url: string) => HTMLAudioElement;
  random?: () => number;
  now?: () => number;
  lastPlayedAtRef?: { current: number };
} = {}): boolean {
  const {
    audioFactory = (url) => new Audio(url),
    random = Math.random,
    now = () => performance.now(),
    lastPlayedAtRef
  } = options;
  const currentTime = now();

  if (lastPlayedAtRef) {
    if (currentTime - lastPlayedAtRef.current < HOVER_SOUND_THROTTLE_MS) {
      return false;
    }
    lastPlayedAtRef.current = currentTime;
  }

  const audio = audioFactory(chooseHoverSoundUrl(random));
  audio.volume = 0.18;
  audio.playbackRate = calculateHoverPlaybackRate(random);
  void audio.play().catch(() => {
    // Browsers may block audio until the first trusted interaction.
  });
  return true;
}
