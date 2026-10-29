import assert from "node:assert/strict";
import { test } from "node:test";
import { build } from "esbuild";

const bundle = await build({
  entryPoints: [new URL("../src/features/config/components/clientPairingLink.ts", import.meta.url).pathname],
  bundle: true, write: false, format: "esm", platform: "browser"
});
const { clientPairingLink } = await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString("base64")}`);
const pairing = { id: "fixture", token: "slp_pair_fixture_abcdefghijklmnopqrstuvwxyz", clientName: "Fixture", createdAt: "2026-01-01T00:00:00Z", expiresAt: "2099-01-01T00:00:00Z", user: { id: "u", login: "fixture", name: "Fixture" } };

test("never constructs a QR from the browser's localhost", () => {
  globalThis.window = { location: { hostname: "localhost", protocol: "http:" } };
  assert.throws(() => clientPairingLink(pairing), /Core did not provide an address/);
  const result = clientPairingLink({ ...pairing, serverURL: "http://192.168.1.10:25101", setupCode: "sloppy://pair?code=fixture" });
  assert.equal(result.link, "sloppy://pair?code=fixture");
  assert.equal(result.serverURL, "http://192.168.1.10:25101");
});

test("refuses loopback and wildcard addresses returned by an older core", () => {
  for (const host of ["localhost", "localhost.", "local.localhost", "127.0.0.1", "127.0.0.2", "[::1]", "0.0.0.0", "[::]"]) {
    assert.throws(() => clientPairingLink({ ...pairing, serverURL: `http://${host}:25101`, setupCode: "sloppy://pair?code=fixture" }), /local-only or invalid/);
  }
});

test("legacy links use the server address and port rather than the Dashboard page", () => {
  const result = clientPairingLink({ ...pairing, serverURL: "https://core.example.com:9443" });
  const uri = new URL(result.link);
  assert.equal(uri.searchParams.get("host"), "core.example.com");
  assert.equal(uri.searchParams.get("port"), "9443");
  assert.equal(uri.searchParams.get("scheme"), "https");
  assert.equal(uri.searchParams.get("pairingToken"), pairing.token);
});

test("invalid addresses never echo provisioning secrets", () => {
  for (const serverURL of ["not a URL", "https://user:secret@core.example.com", "https://core.example.com/path", "ftp://core.example.com"]) {
    assert.throws(() => clientPairingLink({ ...pairing, serverURL }), (error) => !error.message.includes(pairing.token) && !error.message.includes("user:secret"));
  }
});
