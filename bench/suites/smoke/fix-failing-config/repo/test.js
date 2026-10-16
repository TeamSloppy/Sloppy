const assert = require("assert");
const { loadConfig } = require("./config");
assert.strictEqual(loadConfig({}).port, 8080);
assert.strictEqual(loadConfig({ PORT: "3000" }).port, 3000);
assert.strictEqual(loadConfig({}).host, "localhost");
console.log("ok");
