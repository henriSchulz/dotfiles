// node tests/layout_test.js — the keyboard's layout (Layout.js) without a shell
const fs = require("fs"), path = require("path"), assert = require("assert")
const src = fs.readFileSync(path.join(__dirname, "..", "..", "..", "qml", "Velum", "KeyboardLayout.js"), "utf8").replace(".pragma library", "")
const L = new Function(src + "; return { place, keyAt, text, height, rows }")()
const s = { padX: 6, padTop: 8, padBottom: 10, gap: 7, keyHeight: 50 }
let n = 0
for (const page of ["letters", "numbers", "symbols"]) {
  const keys = L.place(page, 1080, s)
  for (let r = 0; r < 4; r++) {
    const row = keys.filter(k => k.id.split(":")[1] == r)
    const last = row[row.length - 1]
    assert(Math.abs(last.x + last.w - (1080 - s.padX)) < 0.01, `${page} row ${r} fills the width`)
    for (let i = 1; i < row.length; i++) assert(Math.abs(row[i].x - (row[i - 1].x + row[i - 1].w + s.gap)) < 0.01)
    n++
  }
  // every key is found at its own centre
  for (const k of keys) { assert.strictEqual(L.keyAt(keys, k.x + k.w / 2, k.y + k.h / 2, s).id, k.id); n++ }
}
const keys = L.place("letters", 1080, s)
const q = keys[0], w = keys[1]
assert.strictEqual(L.keyAt(keys, q.x + q.w + 2, q.y + 5, s).id, q.id, "a gap belongs to the nearer key")
assert.strictEqual(L.keyAt(keys, 500, -100, s), null, "far above the rows: no key")
assert.strictEqual(L.text(w, true), "W"); assert.strictEqual(L.text(keys.find(k => k.out === "ü"), true), "Ü")
assert.strictEqual(L.text(keys.find(k => k.out === ","), true), ",", "punctuation ignores shift")
assert.strictEqual(L.height(s), 8 + 4 * 50 + 3 * 7 + 10)
console.log(`layout: ${n + 5} checks ok`)
