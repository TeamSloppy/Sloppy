const assert = require("assert");
const { areaRect, areaSquare, areaTriangle } = require("./shapes");
assert.strictEqual(areaRect(2, 3), 6);
assert.strictEqual(areaSquare(4), 16);
assert.strictEqual(areaTriangle(4, 3), 6);
console.log("ok");
