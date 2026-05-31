import assert from "node:assert/strict";
import test from "node:test";

import { formatSecureSessionStatus } from "../src/app/sessionStatus.ts";

test("secure session status displays the real process PID", () => {
  assert.equal(formatSecureSessionStatus(12345), "[>_ SECURE_SESSION_ACTIVE // PID: 12345]");
});

test("secure session status shows a loading placeholder without a PID", () => {
  assert.equal(formatSecureSessionStatus(null), "[>_ SECURE_SESSION_ACTIVE // PID: ...]");
});
