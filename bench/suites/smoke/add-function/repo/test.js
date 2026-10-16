const assert = require("assert");
const { capitalize, slugify } = require("./strings");
assert.strictEqual(capitalize("abc"), "Abc");
assert.strictEqual(slugify("Hello, World!"), "hello-world");
assert.strictEqual(slugify("  Multiple   spaces  "), "multiple-spaces");
assert.strictEqual(slugify("--A_b--"), "a-b");
console.log("ok");
