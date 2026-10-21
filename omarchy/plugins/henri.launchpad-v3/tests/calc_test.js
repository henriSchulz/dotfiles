// node tests/calc_test.js — the calculator in the search field.
const fs = require("fs"), path = require("path"), assert = require("assert"), vm = require("vm");
const src = fs.readFileSync(path.join(__dirname, "..", "Calc.js"), "utf8").replace(/^\.pragma library$/m, "");
const C = {}; vm.runInNewContext(src + "\nObject.assign(out, this);", { out: C });
assert.strictEqual(C.evaluate("2+2"), 4);
assert.strictEqual(C.evaluate("2,5 × 4"), 10);
assert.strictEqual(C.evaluate("10 ÷ 4"), 2.5);
assert.strictEqual(C.evaluate("(1+2)*3^2"), 27);
assert.strictEqual(C.evaluate("-3+1"), -2);
assert.strictEqual(C.evaluate("0.1+0.2"), 0.3);
assert.strictEqual(C.evaluate("chrome"), null);
assert.strictEqual(C.evaluate("42"), null);        // a bare number is no calculation
assert.strictEqual(C.evaluate("1/0"), null);       // not finite
assert.strictEqual(C.evaluate("2+"), null);
assert.strictEqual(C.format(2.5), "2,5");
console.log("calc_test: ok");
