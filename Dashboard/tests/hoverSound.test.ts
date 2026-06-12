import assert from "node:assert/strict";
import test from "node:test";

import {
  calculateHoverPlaybackRate,
  chooseHoverSoundUrl,
  HOVER_SOUND_URLS,
  loadHoverSoundPreference,
  persistHoverSoundPreference,
  playHoverSound,
  resolveHoverSoundTarget
} from "../src/shared/ui/hoverSound.ts";

function fakeElement(options: {
  hoverTarget?: unknown;
  disabledTarget?: unknown;
  dataHoverSound?: string | null;
} = {}) {
  const node = {
    getAttribute(name: string) {
      if (name === "data-hover-sound") {
        return options.dataHoverSound ?? null;
      }
      return null;
    },
    closest(selector: string) {
      if (selector.includes("aria-disabled") || selector.includes("[disabled]")) {
        if (options.dataHoverSound === "off" && selector.includes("data-hover-sound")) {
          return options.hoverTarget ?? node;
        }
        return options.disabledTarget ?? null;
      }
      return options.hoverTarget ?? null;
    }
  };
  return node;
}

test("hover sound preference is stored locally instead of in runtime config", () => {
  const values = new Map<string, string>();
  const storage = {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => {
      values.set(key, value);
    }
  };
  const events: Array<{ type: string; enabled: boolean }> = [];
  const target = {
    dispatchEvent: (event: Event) => {
      events.push({
        type: event.type,
        enabled: Boolean((event as CustomEvent<{ enabled?: boolean }>).detail?.enabled)
      });
      return true;
    }
  };

  assert.equal(loadHoverSoundPreference(storage), false);
  persistHoverSoundPreference(true, storage, target);
  assert.equal(loadHoverSoundPreference(storage), true);
  persistHoverSoundPreference(false, storage, target);
  assert.equal(loadHoverSoundPreference(storage), false);
  assert.deepEqual(events, [
    { type: "sloppy:hover-sounds-enabled", enabled: true },
    { type: "sloppy:hover-sounds-enabled", enabled: false }
  ]);
});

test("hover sound resolves eligible interactive targets", () => {
  const hoverTarget = { id: "button" };
  const eventTarget = fakeElement({ hoverTarget });

  assert.equal(resolveHoverSoundTarget(eventTarget), hoverTarget);
});

test("hover sound skips disabled targets and explicit opt-outs", () => {
  const hoverTarget = { id: "button" };

  assert.equal(resolveHoverSoundTarget(fakeElement({ hoverTarget, disabledTarget: hoverTarget })), null);
  assert.equal(resolveHoverSoundTarget(fakeElement({ hoverTarget, dataHoverSound: "off" })), null);
});

test("hover sound pitch randomization stays inside a subtle musical range", () => {
  assert.equal(calculateHoverPlaybackRate(() => 0), 0.82);
  assert.equal(calculateHoverPlaybackRate(() => 1), 1.24);
  assert.equal(calculateHoverPlaybackRate(() => 0.5), 1.03);
});

test("hover sound chooses between bundled sound variants", () => {
  assert.deepEqual(HOVER_SOUND_URLS, [
    "/sounds/lil-pip.wav",
    "/sounds/teeny-tiny-button-press.wav"
  ]);
  assert.equal(chooseHoverSoundUrl(() => 0), "/sounds/lil-pip.wav");
  assert.equal(chooseHoverSoundUrl(() => 0.99), "/sounds/teeny-tiny-button-press.wav");
});

test("hover sound playback uses the selected sound variant", () => {
  const urls: string[] = [];
  const audio = {
    volume: 0,
    playbackRate: 0,
    play: () => Promise.resolve()
  } as HTMLAudioElement;

  const played = playHoverSound({
    random: () => 0.99,
    now: () => 1000,
    audioFactory: (url) => {
      urls.push(url);
      return audio;
    }
  });

  assert.equal(played, true);
  assert.deepEqual(urls, ["/sounds/teeny-tiny-button-press.wav"]);
  assert.equal(audio.playbackRate, 1.24);
});
