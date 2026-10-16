const assert = require("assert");
const users = require("./users");
const name = Object.keys(users).find((k) => k.endsWith("User"));
assert.ok(name, "users.js must export a *User function");
require("./greeting");
assert.strictEqual(require("./greeting").greet(2), "Hello, user-2!");
assert.strictEqual(require("./report").report([1, 2]), "user-1, user-2");
console.log("ok");
