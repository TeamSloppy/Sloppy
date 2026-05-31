import assert from "node:assert/strict";
import test from "node:test";

import { getNotificationDropdownPlacement } from "../src/features/notifications/notificationDropdownPlacement.ts";

test("notification dropdown opens beside the trigger when there is room", () => {
  const placement = getNotificationDropdownPlacement({
    triggerLeft: 52,
    triggerRight: 76,
    triggerBottom: 700,
    dropdownWidth: 360,
    viewportWidth: 1200,
    viewportHeight: 760
  });

  assert.deepEqual(placement, {
    left: 84,
    bottom: 60
  });
});

test("notification dropdown clamps inside a mobile viewport", () => {
  const placement = getNotificationDropdownPlacement({
    triggerLeft: 10,
    triggerRight: 398,
    triggerBottom: 962,
    dropdownWidth: 360,
    viewportWidth: 622,
    viewportHeight: 998
  });

  assert.deepEqual(placement, {
    left: 250,
    bottom: 36
  });
});
