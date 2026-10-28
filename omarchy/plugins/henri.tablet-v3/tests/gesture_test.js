// node tests/gesture_test.js — the home-zone gesture (Gesture.js) on recorded finger paths.
const fs = require("fs"), path = require("path"), assert = require("assert"), vm = require("vm");
const src = fs.readFileSync(path.join(__dirname, "..", "Gesture.js"), "utf8").replace(/^\.pragma library$/m, "");
const G = {};
vm.runInNewContext(src + "\nout.create = create;", { out: G });
// the thresholds as built (Theme.core.surface.tablet)
const tokens = fs.readFileSync(path.join(__dirname, "..", "..", "..", "qml", "Velum", "Tokens.js"), "utf8");
const core = JSON.parse(tokens.match(/^var core = (.*)$/m)[1]);
const cfg = core.surface.tablet;

const H = 960, X = 700;                       // a 1440 × 960 logical screen, finger near the middle
// play a path: [[t, x, y] …] plus optional ticks; returns every action, flattened, as plain JSON
function play(pathPts, opts = {}) {
  const g = G.create(cfg), out = [];
  const add = a => out.push(...JSON.parse(JSON.stringify(a)));
  const [t0, x0, y0] = pathPts[0];
  add(g.down(t0, x0, y0));
  for (let i = 1; i < pathPts.length - 1; i++) {
    const [t, x, y] = pathPts[i];
    add(g.move(t, x, y));
    if (opts.tick) add(g.tick(t));
  }
  const [t, x, y] = pathPts[pathPts.length - 1];
  add(opts.cancel ? g.cancel() : g.up(t, x, y));
  return out;
}
// a straight stroke from (x0, y0) by (dx, dy) in ms, sampled every 8 ms
function stroke(x0, y0, dx, dy, ms, t0 = 0) {
  const pts = [], n = Math.max(1, Math.round(ms / 8));
  for (let i = 0; i <= n; i++) pts.push([t0 + (ms * i) / n, x0 + (dx * i) / n, y0 + (dy * i) / n]);
  return pts;
}
// a stroke, then the finger resting at its end for restMs (samples every 16 ms, as a display would)
function strokeThenRest(x0, y0, dx, dy, ms, restMs) {
  const pts = stroke(x0, y0, dx, dy, ms), [t, x, y] = pts[pts.length - 1];
  for (let s = 16; s <= restMs; s += 16) pts.push([t + s, x, y]);
  return pts;
}
const kinds = acts => acts.map(a => a.do + (a.phase ? ":" + a.phase : "") + (a.step ? ":" + a.step : ""));
const last = acts => kinds(acts).slice(-1)[0];
let n = 0;
function test(name, fn) { fn(); n++; console.log("ok   " + name); }

test("a tap on the home zone is a tap (the window bar)", () => {
  assert.deepStrictEqual(play([[0, X, H - 8], [60, X + 2, H - 9]]), [{ do: "tap" }]);
});
test("a small jitter below the slop is still a tap", () => {
  assert.deepStrictEqual(play(stroke(X, H - 8, 4, -cfg.slop + 1, 120)), [{ do: "tap" }]);
});
test("a cancelled touch is no tap", () => {
  assert.deepStrictEqual(play([[0, X, H - 8], [60, X, H - 8]], { cancel: true }), []);
});
test("a short slow pull up lifts and ends there, no dock", () => {
  const a = play(stroke(X, H - 8, 0, -60, 400));
  assert.ok(kinds(a).includes("lift:move"));
  assert.strictEqual(last(a), "lift:end");
  const end = a[a.length - 1];
  assert.ok(Math.abs(end.travel - 60) < 1, "travel " + end.travel);
  assert.ok(end.velocity < cfg.homeFlick);
});
test("lift travel follows the finger", () => {
  const a = play(stroke(X, H - 8, 0, -50, 200)).filter(x => x.do === "lift" && x.phase === "move");
  for (let i = 1; i < a.length; i++) assert.ok(a[i].travel >= a[i - 1].travel);
  assert.ok(Math.abs(a[a.length - 1].travel - 50) < 1);
});
test("a long slow pull past homeTravel goes home", () => {
  const a = play(stroke(X, H - 8, 0, -(cfg.homeTravel + 20), 900));
  assert.deepStrictEqual(kinds(a).slice(-2), ["lift:move", "home"]);
});
test("a short fast flick goes home", () => {
  const a = play(stroke(X, H - 8, 0, -120, 80));
  assert.deepStrictEqual(kinds(a).slice(-2), ["lift:move", "home"]);
});
test("a pause high enough opens the App Switcher", () => {
  const a = play(strokeThenRest(X, H - 8, 0, -(cfg.holdTravel + 40), 250, 400), { tick: true });
  const k = kinds(a);
  assert.ok(k.includes("lift:move") && k.includes("switcher:start"), k.join(" "));
  assert.ok(k.indexOf("lift:move") < k.indexOf("switcher:start"));
  assert.strictEqual(last(a), "switcher:end");
  assert.ok(!k.includes("home"));
  const start = a.find(x => x.do === "switcher" && x.phase === "start");
  assert.ok(start.delta < 0, "start delta is upward");
});
test("a pause too low only lifts", () => {
  const a = play(strokeThenRest(X, H - 8, 0, -(cfg.holdTravel - 30), 250, 400), { tick: true });
  assert.ok(!kinds(a).includes("switcher:start"));
  assert.strictEqual(last(a), "lift:end");
});
test("a pause shorter than holdTime does not open the switcher", () => {
  const pts = strokeThenRest(X, H - 8, 0, -(cfg.holdTravel + 40), 250, 0);
  const [t, x, y] = pts[pts.length - 1];
  pts.push([t + cfg.sampleWindow / 2, x, y - 1], [t + cfg.sampleWindow, x, y - 60]);
  assert.ok(!kinds(play(pts, { tick: true })).includes("switcher:start"));
});
test("in the switcher, moves become deltas (up negative) and the watchdog is fed at rest", () => {
  const pts = strokeThenRest(X, H - 8, 0, -(cfg.holdTravel + 40), 250, 300);
  const [t, x, y] = pts[pts.length - 1];
  pts.push(...stroke(x, y, 0, -50, 100, t + 16).slice(1));
  const a = play(pts, { tick: true }).filter(x => x.do === "switcher" && x.phase === "update");
  assert.ok(a.some(u => u.delta === 0), "a resting update");
  const moved = a.reduce((s, u) => s + u.delta, 0);
  assert.ok(Math.abs(moved + 50) < 2, "deltas sum to the move: " + moved);
});
test("sideways to the left is the next app, to the right the previous", () => {
  assert.strictEqual(last(play(stroke(X, H - 8, -(cfg.slideCommit + 10), 0, 300))), "app:1");
  assert.strictEqual(last(play(stroke(X, H - 8, cfg.slideCommit + 10, 0, 300))), "app:-1");
});
test("a short sideways flick switches too, a short slow one does not", () => {
  assert.strictEqual(last(play(stroke(X, H - 8, -60, 0, 50))), "app:1");
  assert.deepStrictEqual(kinds(play(stroke(X, H - 8, -60, 0, 600))).filter(k => k !== "slide:move"), ["slide:end"]);
});
test("a diagonal stroke that is more up than sideways is a lift", () => {
  assert.ok(kinds(play(stroke(X, H - 8, 20, -60, 400))).includes("lift:move"));
});
test("the indicator follows a sideways finger and lets go at the end", () => {
  const a = play(stroke(X, H - 8, -50, 0, 400)), m = a.filter(x => x.do === "slide" && x.phase === "move");
  assert.ok(m.length > 3 && Math.abs(m[m.length - 1].dx + 50) < 1, JSON.stringify(m.slice(-1)));
  assert.strictEqual(last(a), "slide:end");
  assert.strictEqual(last(play(stroke(X, H - 8, -50, 0, 200), { cancel: true })), "slide:end");
});
test("a finger resting on the indicator is a long press, once, and nothing when it lets go", () => {
  const pts = [[0, X, H - 8]];
  for (let t = 16; t <= cfg.longPress + 200; t += 16) pts.push([t, X + 1, H - 8]);
  assert.deepStrictEqual(kinds(play(pts, { tick: true })), ["longpress"]);
  const short = [[0, X, H - 8], [cfg.longPress - 100, X, H - 8]];
  assert.deepStrictEqual(kinds(play(short, { tick: true })), ["tap"]);
});
test("pushed down on the indicator is the down action, once", () => {
  assert.deepStrictEqual(kinds(play(stroke(X, H - 10, 1, cfg.downSlop + 3, 120))), ["down"]);
});
test("no gesture pulls the dock any more", () => {
  const k = kinds(play(strokeThenRest(X, H - 8, 0, -(cfg.homeTravel + 20), 300, 300), { tick: true }));
  assert.ok(!k.some(x => x.startsWith("dock")), k.join(" "));
});
test("cancel ends the lift and cancels the switcher", () => {
  assert.deepStrictEqual(kinds(play(stroke(X, H - 8, 0, -60, 400), { cancel: true })).slice(-1), ["lift:cancel"]);
  const a = play(strokeThenRest(X, H - 8, 0, -(cfg.holdTravel + 40), 250, 400), { tick: true, cancel: true });
  const end = a[a.length - 1];
  assert.deepStrictEqual([end.do, end.phase, end.cancelled], ["switcher", "end", true]);
});
test("after release nothing more comes out", () => {
  const g = G.create(cfg);
  g.down(0, X, H - 8); g.move(100, X, H - 60); g.up(200, X, H - 60);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(g.move(300, X, H - 300))), []);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(g.tick(900))), []);
});
console.log(n + " tests passed");
