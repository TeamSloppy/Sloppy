const assert = require("assert");
const { range } = require("./range");
assert.deepStrictEqual(range(1, 4), [1, 2, 3, 4]);
assert.deepStrictEqual(range(3, 3), [3]);
assert.deepStrictEqual(range(5, 4), []);
console.log("ok");
