// node tests/layout_test.js — the keyboard's layout (Layout.js) without a shell
const fs = require("fs"), path = require("path"), assert = require("assert")
const src = fs.readFileSync(path.join(__dirname, "..", "..", "..", "qml", "Velum", "KeyboardLayout.js"), "utf8").replace(".pragma library", "")
const L = new Function(src + "; return { place, keyAt, text, height, rows, shortcuts, modIcons, keyLabel, comboKey, comboLine, placeDock, dockHeight }")()
const s = { padX: 6, padTop: 8, padBottom: 10, gap: 7, keyHeight: 50 }
let n = 0
for (const [page, sc, dict] of [["letters", false], ["numbers", false], ["symbols", false], ["letters", true], ["numbers", true], ["symbols", true, true], ["letters", true, true]]) {
  const keys = L.place(page, 1080, s, sc, dict)
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
// the shortcuts key sits beside the page key only when asked for
assert(!L.place("letters", 1080, s).some(k => k.act === "shortcuts"))
assert.strictEqual(L.place("letters", 1080, s, true).filter(k => k.act === "shortcuts").length, 1)
// the desktop board: tab first in the top row, letters as wide there as in the next row; the mic only when asked for
const desk = L.place("letters", 1080, s, true, true), row = r => desk.filter(k => k.id.split(":")[1] == r)
assert.strictEqual(row(0)[0].key, "Tab"); assert(!L.place("letters", 1080, s).some(k => k.key === "Tab"), "the lock's board has no tab")
assert(Math.abs(row(0)[1].w - row(1)[0].w) < 0.5, "q as wide as a (to half a px: a row has a gap more)")
assert.strictEqual(row(3).filter(k => k.act === "dictate").length, 1)
assert.strictEqual(row(3)[row(3).findIndex(k => k.act === "dictate") + 1].act, "space", "the mic sits left of the space bar")
assert(!L.place("letters", 1080, s, true).some(k => k.act === "dictate"))
// a terminal copies with Shift and has its own group
const copy = (t) => L.shortcuts(t)[0].items.find(i => i.label === "Copy")
assert.deepStrictEqual(copy(false).mods, ["ctrl"]); assert.deepStrictEqual(copy(true).mods, ["ctrl", "shift"])
assert.deepStrictEqual(L.shortcuts(false).map(g => g.title), ["Edit", "Desktop"])
assert.deepStrictEqual(L.shortcuts(true).map(g => g.title), ["Edit", "Terminal", "Desktop"])
// combos: modifiers in a fixed order, the key lowercase or by name
assert.strictEqual(L.comboLine(["shift", "ctrl"], "c"), "combo ctrl+shift c")
assert.strictEqual(L.comboLine([], "F8"), "combo - F8")
assert.deepStrictEqual(L.modIcons(["super", "shift", "ctrl"]), ["control", "shift", "command"])
assert.strictEqual(L.comboKey(keys.find(k => k.out === "q")), "q")
assert.strictEqual(L.comboKey({ act: "space", out: " " }), "space")
assert.strictEqual(L.comboKey({ key: "BackSpace" }), "BackSpace")
assert.strictEqual(L.keyLabel("c"), "C"); assert.strictEqual(L.keyLabel("space"), "Space")
// as on an iPad: key flicks = the .?123 page's rows, no arrow keys, ".?123" / "ABC"
const flicks = r => keys.filter(k => k.id.split(":")[1] == r && k.alt).map(k => k.alt).join(" ")
const numRow = r => L.place("numbers", 1080, s).filter(k => k.id.split(":")[1] == r && k.out).map(k => k.out).join(" ")
assert.strictEqual(flicks(0), numRow(0), "top row flicks = the digits")
assert.strictEqual(flicks(1), numRow(1), "middle row flicks = the number page's middle row")
assert.strictEqual(flicks(2), "% - + = / ; : ! ?")
assert.strictEqual(L.text(keys.find(k => k.out === "q"), true, true), "1", "a flick ignores shift")
assert.strictEqual(L.text(keys.find(k => k.out === "ä"), false, true), "ä", "no flick character: the letter")
for (const sc of [false, true]) for (const d of [false, true]) for (const pg of ["letters", "numbers", "symbols"])
  assert(!L.place(pg, 1080, s, sc, d).some(k => k.key === "Left" || k.key === "Right"), "no arrow keys")
assert.deepStrictEqual(L.place("letters", 1080, s).filter(k => k.act === "page").map(k => k.label), [".?123", ".?123"])
assert.deepStrictEqual(L.place("numbers", 1080, s).filter(k => k.id.split(":")[1] == 3 && k.act === "page").map(k => k.label), ["ABC", "ABC"])
console.log(`layout: ${n + 35} checks ok`)

// the docked board: one column grid — every letter as wide as every other, on every row and page;
// a key's left edge on the grid; every row ends at the right edge; rows staggered as on hardware
const d = { columns: 14.5, keyHeight: 50, gap: 7, padX: 6, padTop: 6, padBottom: 26 }
for (const page of ["letters", "symbols", "numbers"]) {
  const keys = L.placeDock(page, 1024, d), pitch = (1024 - 2 * d.padX + d.gap) / d.columns
  for (let r = 0; r < 5; r++) {
    const row = keys.filter(k => k.id.split(":")[1] == r), last = row[row.length - 1]
    if (r !== 3 || page === "letters") assert(Math.abs(last.x + last.w - (1024 - d.padX)) < 0.01, `${page} row ${r} ends at the edge`)
    for (const k of row) { assert(Math.abs(((k.x - d.padX) / pitch) * 4 - Math.round(((k.x - d.padX) / pitch) * 4)) < 1e-6, `${page} ${k.label || k.act} on the grid`); n++ }
  }
  for (const k of keys.filter(k => !k.fn && !k.act)) { assert(Math.abs(k.w - (pitch - d.gap)) < 0.01, `${page} ${k.label} one column wide`); n++ }
  for (const k of keys) { assert.strictEqual(L.keyAt(keys, k.x + k.w / 2, k.y + k.h / 2, d).id, k.id); n++ }
}
const dk = L.placeDock("letters", 1024, d), at = l => dk.find(k => k.label === l)
const pitch = (1024 - 2 * d.padX + d.gap) / d.columns
assert(Math.abs(at("a").x - at("q").x - 0.25 * pitch) < 0.01, "a a quarter key right of q (tab 1.5, caps 1.75)")
assert(Math.abs(at("y").x - at("a").x - 0.5 * pitch) < 0.01, "y half a key right of a (< before it)")
assert.strictEqual(dk.filter(k => k.key === "Tab").length, 1)
assert.strictEqual(L.text(at("1"), true), "!", "Shift types the character over the key")
assert.strictEqual(L.text(at("1"), false), "1")
assert.strictEqual(L.text(at("q"), true), "Q")
assert.strictEqual(L.text(at("ß"), true), "?")
assert.strictEqual(L.dockHeight(d), 6 + 5 * 50 + 4 * 7 + 26)
assert(L.placeDock("letters", 1024, d).some(k => k.act === "hide") && !L.placeDock("letters", 1024, d).some(k => k.act === "dictate"), "the mic is in the toolbar")
console.log("dock ok")
