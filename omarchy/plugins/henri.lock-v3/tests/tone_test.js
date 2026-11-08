// node shell/henri.lock-v3/tests/tone_test.js — Tone.js against the lab's colours (Chromium's oklch)
const fs = require("fs"), path = require("path"), vm = require("vm")
const src = fs.readFileSync(path.join(__dirname, "..", "Tone.js"), "utf8").replace(".pragma library", "")
const ctx = { module: { exports: {} }, Math }
vm.runInNewContext(src, ctx)
const T = ctx.module.exports
let fail = 0
const ok = (c, m) => { if (!c) { fail++; console.log("FAIL", m) } }
const rgb = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255)
// round trip
const o = T.toOklch(...rgb("#4777c9"))
ok(Math.abs(T.hex(T.fromOklch(o.l, o.c, o.h)) === "#4777c9" ? 0 : 1) === 0, "round trip #4777c9 → " + T.hex(T.fromOklch(o.l, o.c, o.h)))
ok(Math.abs(o.l - 0.5714) < 0.01, "L of #4777c9 " + o.l)
// seeds: two hue groups, grey ignored
const px = []
for (let i = 0; i < 60; i++) px.push(0x47, 0x77, 0xc9, 255)
for (let i = 0; i < 30; i++) px.push(0x5b, 0x9c, 0xc5, 255)
for (let i = 0; i < 90; i++) px.push(128, 128, 128, 255)
const s = T.seeds(px, { bins: 24, minSaturation: 0.25, minValue: 0.15 })
ok(s && T.hex(s[0]) === "#4777c9" && T.hex(s[1]) === "#5b9cc5", "seeds " + (s && s.map(T.hex)))
ok(T.seeds([128, 128, 128, 255], { bins: 24, minSaturation: 0.25, minValue: 0.15 }) === null, "grey → null")
// a tone stays in gamut and keeps its lightness order
const top = T.tone(rgb("#4777c9"), 0.33, 0.5), bottom = T.tone(rgb("#5b9cc5"), 0.22, 0.5)
ok(T.toOklch(...top).l > T.toOklch(...bottom).l, "top lighter than bottom")
ok(top.concat(bottom).every(v => v >= 0 && v <= 1), "in gamut")
console.log(fail ? fail + " failed" : "tone ok", T.hex(top), T.hex(bottom), T.hex(T.toneAbs(rgb("#4777c9"), 0.96, 0.012)))
process.exit(fail ? 1 : 0)
