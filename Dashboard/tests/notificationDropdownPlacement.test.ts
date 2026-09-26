import assert from "node:assert/strict";
import test from "node:test";

import { getNotificationDropdownPlacement } from "../src/features/notifications/notificationDropdownPlacement.ts";

test("notification dropdown opens below a top navigation trigger", () => {
  const placement = getNotificationDropdownPlacement({
    triggerLeft: 52,
    triggerRight: 76,
    triggerTop: 20,
    triggerBottom: 54,
    dropdownWidth: 360,
    dropdownHeight: 420,
    viewportWidth: 1200,
    viewportHeight: 760
  });

  assert.deepEqual(placement, {
    left: 84,
    top: 62
  });
});

test("notification dropdown opens above a bottom sidebar trigger", () => {
  const placement = getNotificationDropdownPlacement({
    triggerLeft: 10,
    triggerRight: 398,
    triggerTop: 928,
    triggerBottom: 962,
    dropdownWidth: 360,
    dropdownHeight: 420,
    viewportWidth: 622,
    viewportHeight: 998
  });

  assert.deepEqual(placement, {
    left: 250,
    top: 500
  });
});
