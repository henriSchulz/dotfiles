// node tests/home_test.js — the home gesture's geometry (HomeModel.js)
const fs = require("fs"), path = require("path"), assert = require("assert"), vm = require("vm");
const src = fs.readFileSync(path.join(__dirname, "..", "HomeModel.js"), "utf8").replace(/^\.pragma library$/m, "");
const M = {};
vm.runInNewContext(src + "\nout.M = { rubber, follow, besideX, switcherGeo, switcherPos, switcherSnap, switcherClamp, grid, cardRadius, destination };", { out: M });
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
console.log(n + " tests passed");
