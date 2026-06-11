import assert from "node:assert/strict";
import test from "node:test";

import {
  calculateHoverPlaybackRate,
  chooseHoverSoundUrl,
  HOVER_SOUND_URLS,
  isHoverSoundEnabled,
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

test("hover sound defaults to disabled and respects the UI config toggle", () => {
  assert.equal(isHoverSoundEnabled({}), false);
  assert.equal(isHoverSoundEnabled({ ui: {} }), false);
  assert.equal(isHoverSoundEnabled({ ui: { hoverSoundsEnabled: true } }), true);
  assert.equal(isHoverSoundEnabled({ ui: { hoverSoundsEnabled: false } }), false);
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
