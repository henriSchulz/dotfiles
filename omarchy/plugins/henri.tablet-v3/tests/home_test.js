// node tests/home_test.js — the home gesture's geometry (HomeModel.js)
const fs = require("fs"), path = require("path"), assert = require("assert"), vm = require("vm");
const src = fs.readFileSync(path.join(__dirname, "..", "HomeModel.js"), "utf8").replace(/^\.pragma library$/m, "");
const M = {};
vm.runInNewContext(src + "\nout.M = { rubber, follow, besideX, switcherGeo, switcherPos, switcherSnap, switcherClamp, grid, cardRadius, destination, arrange, moveTo, slotAt, edgeOf, isFolder, arrangeLayout, folderOf, fold, unfold, moveInFolder, folderName, miniApps, isWidget, place, pageCount, dropAt };", { out: M });
const H_ = M.M;
const tokens = fs.readFileSync(path.join(__dirname, "..", "..", "..", "qml", "Velum", "Tokens.js"), "utf8");
const tcfg = JSON.parse(tokens.match(/^var core = (.*)$/m)[1]).surface.tablet, cfg = tcfg.home;
const W = 1080, H = 680;
let n = 0;
function test(name, fn) { fn(); n++; console.log("ok   " + name); }
const near = (a, b, e = 0.5) => Math.abs(a - b) <= e;

test("at the start the card covers the area", () => {
  const f = H_.follow(0, 0, W, H, cfg);
  assert.ok(near(f.s, 1, 1e-9) && near(f.x, 0) && near(f.y, 0), JSON.stringify(f));
});
test("its bottom edge stays under the finger", () => {
  for (const up of [40, 150, 300]) {
    const f = H_.follow(up, 0, W, H, cfg);
    assert.ok(near(H / 2 + f.y + f.s * H / 2, H - up), `up ${up}: ${JSON.stringify(f)}`);
  }
});
test("it shrinks linearly to minScale and then only resists", () => {
  let last = 1;
  const end = (1 - cfg.minScale) * cfg.shrinkTravel * H;
  for (let up = 0; up <= end; up += 10) { const s = H_.follow(up, 0, W, H, cfg).s; assert.ok(s <= last + 1e-9); last = s; }
  assert.ok(near(H_.follow(end, 0, W, H, cfg).s, cfg.minScale, 0.001));
  assert.ok(near(H_.follow(end / 2, 0, W, H, cfg).s, (1 + cfg.minScale) / 2, 0.001), "linear");
  assert.ok(H_.follow(H * 2, 0, W, H, cfg).s > cfg.minScale - 0.08);
});
test("x follows 1:1, rubber-banded only where no app is", () => {
  assert.ok(near(H_.follow(50, -200, W, H, cfg).x, -200));
  const b = H_.follow(50, -200, W, H, cfg, { right: true });
  assert.ok(b.x > -cfg.sideResist && b.x < 0, JSON.stringify(b));
});
test("pushed down, the card gives way a little", () => {
  const f = H_.follow(-200, 0, W, H, cfg);
  assert.ok(f.y > 0 && f.y < cfg.pushDown);
});
test("three apps stand in one row that fits, four in two rows", () => {
  const g3 = H_.switcherGeo(3, W, H, cfg), g4 = H_.switcherGeo(4, W, H, cfg);
  assert.strictEqual(g3.rows, 1); assert.strictEqual(g4.rows, 2);
  const xs = [0, 1, 2].map(i => H_.switcherPos(i, 3, g3.lo, g3, cfg).x);
  assert.ok(xs[0] - g3.s * W / 2 >= -W / 2 && xs[2] + g3.s * W / 2 <= W / 2, JSON.stringify(xs));
  assert.ok(near(xs[0] + xs[2], 0), "the row is centred");
});
test("the newest card is top right, the one before it below", () => {
  const g = H_.switcherGeo(7, W, H, cfg);
  const a = H_.switcherPos(6, 7, g.lo, g, cfg), b = H_.switcherPos(5, 7, g.lo, g, cfg), c = H_.switcherPos(4, 7, g.lo, g, cfg);
  assert.ok(near(a.x, b.x) && a.y < b.y && c.x < a.x);
  assert.ok(a.x + g.s * W / 2 <= W / 2, "on screen");
});
test("scrolling snaps to whole columns within the range", () => {
  const g = H_.switcherGeo(9, W, H, cfg);
  assert.strictEqual(H_.switcherSnap(g.lo - 500, 0, g, cfg), g.lo);
  assert.strictEqual(H_.switcherSnap(g.hi + 500, 0, g, cfg), g.hi);
  const s = H_.switcherSnap(g.lo + g.stepX * 0.6, 0, g, cfg);
  assert.ok(near((s - g.lo) / g.stepX, Math.round((s - g.lo) / g.stepX), 1e-6));
  assert.ok(H_.switcherClamp(g.hi + 300, g, 120) < g.hi + 120);
});
test("the home grid fits the area with its dock", () => {
  const g = H_.grid(W, H, cfg);
  assert.ok(g.dockH + g.dockGap < H / 4 && g.icon > 40, JSON.stringify(g));
  assert.strictEqual(g.cols * g.rows, g.perPage);
});
test("a card's corners end as an icon's", () => {
  assert.ok(near(H_.cardRadius(1, 0, H, cfg), 0));
  assert.ok(near(H_.cardRadius(0.5, 1, H, cfg), H * cfg.iconRadius));
});
test("sideways tracking is damped the faster the card goes up", () => {
  assert.ok(near(H_.follow(100, -100, W, H, cfg, null, 0).x, -100));
  assert.ok(near(H_.follow(100, -100, W, H, cfg, null, cfg.sideDampSpeed).x, -100 * (1 - cfg.sideDamp)));
});
const dest = (travel, dx, vUp, vx, n = 3, cur = 2) => H_.destination(travel, dx, vUp, vx, n, cur, W, H, cfg, tcfg);
test("released: SpringBoard's destinations from the last speed", () => {
  assert.strictEqual(dest(cfg.minTravel - 5, 0, 2000, 0), "back", "too short");
  assert.strictEqual(dest(200, 0, cfg.homeVelocity + 1, 900), "home", "fast up");
  assert.strictEqual(dest(200, 0, cfg.homeMinVelocity + 50, 0), "home", "up, steep");
  assert.strictEqual(dest(200, 0, 50, 30), "switcher", "resting");
  assert.strictEqual(dest(200, 0, -400, 0), "back", "moving down");
  assert.strictEqual(dest(H * cfg.homeDistance + 10, 0, 0, 400), "home", "far, sideways drift");
  assert.strictEqual(dest(30, -(cfg.slideCommit * W + 10), 0, -100, 3, 1), "next");
  assert.strictEqual(dest(30, cfg.slideCommit * W + 10, 0, 100, 3, 1), "prev");
  assert.strictEqual(dest(30, -(cfg.slideCommit * W + 10), 0, -100, 3, 2), "back", "no app on that side");
});
test("Home.qml never reaches its springs through `home.` (ids are no properties; it threw and froze the screen)", () => {
  const qml = fs.readFileSync(path.join(__dirname, "..", "Home.qml"), "utf8");
  const ids = [...qml.matchAll(/^\s*Spring \{ id: (\w+)/gm)].map(m => m[1]);
  assert.ok(ids.length >= 5, ids.join(" "));
  const bad = ids.filter(id => new RegExp("\\bhome\\." + id + "\\b").test(qml));
  assert.deepStrictEqual(bad, []);
});
// ---- edit mode
const same = (a, b) => assert.strictEqual(JSON.stringify(a), JSON.stringify(b));   // arrays from the vm are of another realm
test("arrange keeps the saved order and appends new apps", () => {
  same(H_.arrange(["a", "b", "c", "d"], ["c", "x", "a"]), ["c", "a", "b", "d"]);
  same(H_.arrange(["a", "b"], null), ["a", "b"]);
  same(H_.arrange(["a", "b"], ["b", "b", "a"]), ["b", "a"]);
});
test("moveTo moves one app and clamps the index", () => {
  same(H_.moveTo(["a", "b", "c", "d"], "a", 2), ["b", "c", "a", "d"]);
  same(H_.moveTo(["a", "b", "c"], "c", 0), ["c", "a", "b"]);
  same(H_.moveTo(["a", "b", "c"], "a", 99), ["b", "c", "a"]);
  same(H_.moveTo(["a", "b"], "z", 0), ["a", "b"]);
});
test("slotAt finds the cell under the finger, on its page, within the apps", () => {
  const g = H_.grid(W, H, cfg), cw = (W - 2 * g.side) / g.cols, ch = (H - g.top - g.bottom) / g.rows;
  const n = g.perPage * 2;
  assert.strictEqual(H_.slotAt(g.side + cw * 0.5, g.top + ch * 0.5, 0, n, g, cw, ch), 0);
  assert.strictEqual(H_.slotAt(g.side + cw * 1.5, g.top + ch * 1.5, 0, n, g, cw, ch), g.cols + 1);
  assert.strictEqual(H_.slotAt(g.side + cw * 0.5, g.top + ch * 0.5, 1, n, g, cw, ch), g.perPage);
  assert.strictEqual(H_.slotAt(W, H, 0, 3, g, cw, ch), 2, "past the last app: the last slot");
  assert.strictEqual(H_.slotAt(-50, -50, 0, n, g, cw, ch), 0, "outside the grid: clamped");
});
test("edgeOf turns pages only near the sides", () => {
  assert.strictEqual(H_.edgeOf(1, W, cfg), -1);
  assert.strictEqual(H_.edgeOf(W - 1, W, cfg), 1);
  assert.strictEqual(H_.edgeOf(W / 2, W, cfg), 0);
});
test("arrangeLayout: folders keep their apps, an app is in one place, empty folders go, new apps last", () => {
  const ids = ["a", "b", "c", "d", "e"];
  const l = H_.arrangeLayout(ids, ["b", "folder:f1", "a", "folder:f2"], { f1: { name: "Office", items: ["c", "x", "a"] }, f2: { name: "Gone", items: ["x"] } });
  same(l.order, ["b", "folder:f1", "d", "e"]);
  same(l.folders, { f1: { name: "Office", items: ["c", "a"] } });
  const plain = H_.arrangeLayout(ids, ["e", "a"], undefined);
  same(plain.order, ["e", "a", "b", "c", "d"], "an old file with no folders");
});
test("fold: an app on an app makes a folder in the target's place, on a folder it joins", () => {
  let l = { order: ["a", "b", "c"], folders: {} };
  l = H_.fold(l, "c", "a", "Office");
  same(l.order, ["folder:f1", "b"]);
  same(l.folders.f1, { name: "Office", items: ["a", "c"] });
  l = H_.fold(l, "b", "folder:f1", "x");
  same(l.order, ["folder:f1"]);
  same(l.folders.f1.items, ["a", "c", "b"]);
  assert.strictEqual(H_.fold(l, "folder:f1", "a"), l, "a folder never goes into a folder");
});
test("unfold: out of the folder onto the grid; the last app out removes the folder", () => {
  let l = { order: ["x", "folder:f1", "y"], folders: { f1: { name: "O", items: ["a", "b"] } } };
  l = H_.unfold(l, "a", -1);
  same(l.order, ["x", "folder:f1", "a", "y"]);
  l = H_.unfold(l, "b", 0);
  same(l.order, ["b", "x", "a", "y"]);
  same(l.folders, {});
  assert.strictEqual(H_.folderOf({ f2: { items: ["q"] } }, "q"), "folder:f2");
});
test("moveInFolder reorders inside; folderName takes the first shared category", () => {
  const l = H_.moveInFolder({ order: ["folder:f1"], folders: { f1: { name: "O", items: ["a", "b", "c"] } } }, "f1", "c", 0);
  same(l.folders.f1.items, ["c", "a", "b"]);
  const names = [["Office", "Office"], ["Graphics", "Creativity"]];
  assert.strictEqual(H_.folderName([["Office", "Viewer", "Graphics"], ["Office"]], names, "Folder"), "Office");
  assert.strictEqual(H_.folderName([["Graphics"], ["Graphics", "Office"]], names, "Folder"), "Creativity");
  assert.strictEqual(H_.folderName([["Game"], ["Office"]], names, "Folder"), "Folder");
  assert.strictEqual(H_.miniApps([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 3).length, 9);
});
test("place: a 2×2 widget takes its cells, icons flow around it and onto the next page", () => {
  const span = id => H_.isWidget(id) ? [2, 2] : [1, 1];
  const cells = H_.place(["widget:photos", "a", "b", "c", "d", "e"], span, 4, 2);
  same(cells.map(e => [e.page, e.col, e.row]), [[0, 0, 0], [0, 2, 0], [0, 3, 0], [0, 2, 1], [0, 3, 1], [1, 0, 0]]);
  same(cells[0], { page: 0, col: 0, row: 0, w: 2, h: 2 });
  assert.strictEqual(H_.pageCount(cells), 2);
  // a widget that no longer fits in the row starts where it fits; the gap fills with later icons
  const c2 = H_.place(["a", "b", "c", "widget:photos", "d"], span, 4, 3);
  same(c2.map(e => [e.page, e.col, e.row]), [[0, 0, 0], [0, 1, 0], [0, 2, 0], [0, 0, 1], [0, 3, 0]]);
});
test("dropAt: the item under the finger, or after the ones before that cell", () => {
  const span = id => H_.isWidget(id) ? [2, 2] : [1, 1];
  const g = { cols: 4, rows: 3, side: 0, top: 0 }, cw = 100, ch = 100;
  const order = ["widget:photos", "a", "b", "c", "d"];
  assert.strictEqual(H_.dropAt(order, "d", 150, 150, 0, span, g, cw, ch), 0, "on the widget");
  assert.strictEqual(H_.dropAt(order, "a", 350, 50, 0, span, g, cw, ch), 2, "without a, c sits in the last column of row 0");
  assert.strictEqual(H_.dropAt(order, "a", 350, 250, 0, span, g, cw, ch), 4, "an empty cell at the end");
  assert.strictEqual(H_.isWidget("widget:photos") && !H_.isWidget("foot"), true);
});
console.log(n + " tests passed");
