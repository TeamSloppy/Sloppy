import assert from "node:assert/strict";

const base = process.argv[2];
assert(base, "Pass the test server API URL.");
const socket = new WebSocket(`${base.replace(/^http/, "ws")}/v1/dashboard/terminal/ws`);
let output = "";
let ready = false;

await new Promise((resolve, reject) => {
  const deadline = setTimeout(() => reject(new Error("Dashboard terminal WebSocket timed out.")), 15_000);
  const finish = (error) => {
    clearTimeout(deadline);
    socket.close();
    if (error) reject(error); else resolve();
  };
  const send = (message) => socket.send(JSON.stringify(message));
  socket.addEventListener("open", () => send({ type: "auth", token: "" }));
  socket.addEventListener("error", () => finish(new Error("Dashboard terminal WebSocket failed.")));
  socket.addEventListener("message", ({ data }) => {
    try {
      const message = JSON.parse(data);
      switch (message.type) {
        case "authenticated":
          send({ type: "start", cols: 80, rows: 24 });
          break;
        case "ready":
          ready = true;
          assert(message.sessionId);
          send({ type: "resize", cols: 100, rows: 32 });
          send({ type: "input", data: "@echo off\recho WINDOWS_WEBSOCKET_OK\rexit\r" });
          break;
        case "output":
          output += message.data ?? "";
          break;
        case "exit":
          assert(ready, "Terminal did not become ready.");
          assert.equal(message.exitCode, 0);
          assert(output.includes("WINDOWS_WEBSOCKET_OK"), "Terminal output did not reach the dashboard.");
          finish();
          break;
        case "error":
          throw new Error(`${message.code}: ${message.message}`);
      }
    } catch (error) { finish(error); }
  });
});
console.log("Windows dashboard terminal WebSocket: input, output, resize and exit passed.");
