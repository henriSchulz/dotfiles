// node tests/material_test.js — the Material home screen's geometry and pure behaviour (MaterialModel.js),
// checked against the lab's numbers (lab/mui-material/src/Launcher.jsx)
const fs = require("fs"), path = require("path"), assert = require("assert"), vm = require("vm");
const src = fs.readFileSync(path.join(__dirname, "..", "MaterialModel.js"), "utf8").replace(/^\.pragma library$/m, "");
const out = {};
vm.runInNewContext(src + "\nout.M = { geometry, cellX, cellY, hotseatX, hotseatSlot, overHotseat, hotseatRoom, arrangeHotseat, dropTargets, targetAt, moveTo, insertAt, takeOut, fold, folderPanel, folderItem, folderSlot, inRect, placeMenu, speed };", { out });
const M = out.M;
const tokens = fs.readFileSync(path.join(__dirname, "..", "..", "..", "qml", "Velum", "Tokens.js"), "utf8");
const m = JSON.parse(tokens.match(/^var core = (.*)$/m)[1]).surface.material;
let n = 0;
function test(name, fn) { fn(); n++; console.log("ok   " + name); }
const same = (a, b, msg) => assert.strictEqual(JSON.stringify(a), JSON.stringify(b), msg);
const near = (a, b, e = 0.01) => Math.abs(a - b) <= e;

const W = 1440, H = 900, geo = M.geometry(W, H, m);
test("landscape: 6 × 5, portrait turns it 5 × 6", () => {
  same([geo.cols, geo.rows], [6, 5]);
  const p = M.geometry(900, 1300, m);
  same([p.cols, p.rows], [5, 6]);
});
test("the lab's geometry: top = drop bar, bottom = edge + search + gap + hotseat + dots", () => {
  assert.strictEqual(geo.top, 56);
  assert.strictEqual(geo.side, 24);
  assert.strictEqual(geo.labelH, 20);                     // round(14 × 1.43)
  assert.strictEqual(geo.hotseatH, 92);                   // 60 + spacing(4)
  assert.strictEqual(geo.bottom, 24 + 56 + 16 + 92 + 24);
  assert.ok(near(geo.cellW, (W - 48) / 6));
  assert.ok(near(geo.cellH, (H - 56 - 212) / 5));
  assert.ok(near(geo.iconX, (geo.cellW - 60) / 2));
  assert.ok(near(geo.iconY, (geo.cellH - 60 - 8 - 20) / 2));
  assert.strictEqual(geo.hotseatTop, H - 24 - 56 - 16 - 92);
  assert.strictEqual(geo.hotseatY, geo.hotseatTop + 16);
  same(geo.search, { x: (W - 720) / 2, y: H - 80, w: 720, h: 56 });
});
test("a narrow screen: the search bar takes the width inside the edges", () => {
  const g = M.geometry(600, 900, m);
  assert.strictEqual(g.search.w, 600 - 48);
});
test("a full hotseat lines up with the grid's columns", () => {
  for (let i = 0; i < 6; i++) assert.ok(near(M.hotseatX(i, 6, geo), M.cellX({ page: 0, col: i }, geo) + geo.iconX), "column " + i);
});
test("fewer hotseat icons are centred", () => {
  const l = M.hotseatX(0, 3, geo), r = M.hotseatX(2, 3, geo) + geo.icon;
  assert.ok(near(W / 2 - l, r - W / 2));
});
test("hotseat slot: counted with the held icon in the row, clamped", () => {
  const list = ["a", "b", "c"];
  assert.strictEqual(M.hotseatSlot(list, "x", 0, geo), 0);
  assert.strictEqual(M.hotseatSlot(list, "x", W, geo), 3);
  const mid = M.hotseatX(1, 4, geo) + geo.icon / 2;
  assert.strictEqual(M.hotseatSlot(list, "x", mid, geo), 1);
  assert.strictEqual(M.hotseatSlot(list, "b", W, geo), 2, "one of them already: n stays 3");
});
test("hotseat band and room for six", () => {
  assert.ok(M.overHotseat(geo.hotseatTop + 10, geo, 8));
  assert.ok(M.overHotseat(geo.hotseatTop - 4, geo, 8));
  assert.ok(!M.overHotseat(geo.hotseatTop - 20, geo, 8));
  const six = ["a", "b", "c", "d", "e", "f"];
  assert.ok(!M.hotseatRoom(six, "x", 6));
  assert.ok(M.hotseatRoom(six, "c", 6));
  assert.ok(M.hotseatRoom(six.slice(1), "x", 6));
});
test("the hotseat at the start: saved, else dock.json's pinned; known only, once, at most 6", () => {
  const known = { a: 1, b: 1, c: 1, d: 1, e: 1, f: 1, g: 1 };
  same(M.arrangeHotseat(null, ["a", "zz", "b", "a"], known, 6), ["a", "b"]);
  same(M.arrangeHotseat(["c"], ["a", "b"], known, 6), ["c"]);
  same(M.arrangeHotseat([], ["a"], known, 6), [], "an empty saved hotseat stays empty");
  same(M.arrangeHotseat(null, ["a", "b", "c", "d", "e", "f", "g"], known, 6).length, 6);
});
test("drop targets: apps from grid or hotseat get Uninstall too", () => {
  same(M.dropTargets("app", "grid"), ["remove", "uninstall"]);
  same(M.dropTargets("app", "dock"), ["remove", "uninstall"]);
  same(M.dropTargets("app", "folder"), ["remove"]);
  same(M.dropTargets("folder", "grid"), ["remove"]);
  same(M.dropTargets("widget", "grid"), ["remove"]);
});
test("the target under the finger: only in the bar, left half the first", () => {
  const two = ["remove", "uninstall"];
  assert.strictEqual(M.targetAt(two, 100, 20, geo), "remove");
  assert.strictEqual(M.targetAt(two, W - 100, 20, geo), "uninstall");
  assert.strictEqual(M.targetAt(two, 100, geo.top + 1, geo), "");
  assert.strictEqual(M.targetAt(["remove"], W - 10, 10, geo), "remove");
});
test("moveTo inserts an id that was not there (from the hotseat), insertAt skips hidden ones", () => {
  same(M.moveTo(["a", "b"], "x", 1), ["a", "x", "b"]);
  same(M.moveTo(["a", "b", "c"], "c", 0), ["c", "a", "b"]);
  const shows = (id) => id !== "h";
  same(M.insertAt(["a", "h", "b", "c"], "x", 1, shows), ["a", "h", "x", "b", "c"]);
  same(M.insertAt(["a", "b"], "x", 9, shows), ["a", "b", "x"]);
});
test("takeOut: out of its folder, right after it; a folder of one becomes that app", () => {
  const l = { order: ["a", "folder:f1", "b"], folders: { f1: { name: "F", items: ["x", "y", "z"] } }, hotseat: ["h"] };
  const r = M.takeOut(l, "y");
  same(r.layout.folders.f1.items, ["x", "z"]);
  assert.strictEqual(r.at, 2);
  assert.strictEqual(r.dissolved, "");
  const r2 = M.takeOut(r.layout, "x");
  same(r2.layout.order, ["a", "z", "b"], "the folder of one is its app now");
  same(r2.layout.folders, {});
  assert.strictEqual(r2.dissolved, "z");
  same(r2.layout.hotseat, ["h"]);
  const r3 = M.takeOut({ order: ["folder:f1"], folders: { f1: { name: "F", items: ["q"] } }, hotseat: [] }, "q");
  same([r3.layout.order, r3.at], [[], 0], "an emptied folder goes");
  assert.strictEqual(M.takeOut(l, "nope").layout, l);
});
test("fold: two apps make a folder in the target's place, an app joins a folder, from the hotseat too", () => {
  const l = { order: ["a", "b", "folder:f1"], folders: { f1: { name: "F", items: ["x"] } }, hotseat: ["h"] };
  const a = M.fold(l, "b", "a", "Utilities");
  same(a.order, ["folder:f2", "folder:f1"]);
  same(a.folders.f2, { name: "Utilities", items: ["a", "b"] });
  const b = M.fold(l, "h", "folder:f1");
  same([b.folders.f1.items, b.hotseat], [["x", "h"], []]);
  assert.strictEqual(M.fold(l, "folder:f1", "a"), l, "a folder never goes into a folder");
  assert.strictEqual(M.fold(l, "widget:photos", "a"), l);
});
test("the open folder: up to 4 columns of cells, centred between the bar and the hotseat", () => {
  const p = M.folderPanel(6, geo, m);
  assert.ok(near(p.w, 4 * geo.cellW + 32));
  assert.ok(near(p.h, 56 + 2 * geo.cellH + 16));
  assert.ok(near(p.x, (W - p.w) / 2));
  assert.ok(p.y >= geo.top);
  const one = M.folderPanel(1, geo, m);
  assert.ok(near(one.w, geo.cellW + 32));
  const i5 = M.folderItem(5, p, geo, m);
  assert.ok(near(i5.x, p.x + 16 + geo.cellW + geo.iconX) && near(i5.y, p.y + 56 + geo.cellH + geo.iconY));
  assert.strictEqual(M.folderSlot(i5.x + 10, i5.y + 10, 6, p, geo, m), 5);
  assert.strictEqual(M.folderSlot(p.x + p.w - 1, p.y + p.h, 6, p, geo, m), 5, "clamped to the last");
});
test("a menu sits centred above its icon, else below; at a point its corner is there; kept inside", () => {
  const a = M.placeMenu({ x: 500, y: 400, w: 60, h: 60 }, 240, 200, W, H, 8, 16);
  same([a.x, a.y, a.originX, a.originY], [530 - 120, 192, 120, 200]);
  const b = M.placeMenu({ x: 500, y: 100, w: 60, h: 60 }, 240, 200, W, H, 8, 16);
  same([b.y, b.originY], [168, 0]);
  const c = M.placeMenu({ x: 10, y: 10, w: 60, h: 60 }, 240, 200, W, H, 8, 16);
  assert.strictEqual(c.x, 16);
  const d = M.placeMenu({ x: 1400, y: 880 }, 240, 200, W, H, 8, 16);
  same([d.x, d.y], [W - 16 - 240, H - 16 - 200]);
  same([d.originX, d.originY], [216, 196], "it still grows from the finger");
});
test("speed: 0 after a rest, px/s otherwise", () => {
  assert.strictEqual(M.speed([[0, 0], [100, 50]], 300, 80), 0);
  assert.strictEqual(M.speed([[0, 0], [100, 50]], 120, 80), 500);
  assert.strictEqual(M.speed([[0, 0]], 10, 80), 0);
});
console.log(`${n} tests passed`);
