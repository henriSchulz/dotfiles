// node tests/search_test.js — the search view's scoring and the drawer's list (SearchScore.js)
const fs = require("fs"), path = require("path"), assert = require("assert"), vm = require("vm");
const src = fs.readFileSync(path.join(__dirname, "..", "SearchScore.js"), "utf8").replace(/^\.pragma library$/m, "");
const box = {};
vm.runInNewContext(src + "\nout.S = { score, appScore, search, drawer, settleOpen, velocity, visible };", { out: box });
const S = box.S;
let n = 0;
function test(name, fn) { fn(); n++; console.log("ok   " + name); }

const apps = [
  { id: "foot", name: "Terminal", cats: ["System", "TerminalEmulator"], actions: [{ id: "new", name: "New Terminal" }] },
  { id: "kitty", name: "kitty", cats: ["System", "TerminalEmulator"], actions: [] },
  { id: "chromium", name: "Chromium", cats: ["Network", "WebBrowser"], actions: [{ id: "new-window", name: "New Window" }, { id: "incognito", name: "New Incognito Window" }] },
  { id: "mdview", name: "Markdown Notes", cats: ["Office", "TextEditor"], actions: [{ id: "new-note", name: "New Note" }] },
  { id: "obsidian", name: "Obsidian", cats: ["Office"], actions: [] },
  { id: "files", name: "Files", cats: ["System", "FileManager"], actions: [{ id: "new-window", name: "New Window" }] },
  { id: "foot-server", name: "Foot Server", cats: ["System"], actions: [], launcherHidden: true },
  { id: "papers", name: "Document Viewer", cats: ["Office", "Viewer"], actions: [] },
  { id: "settings", name: "Settings", cats: ["Settings"], actions: [] },
  { id: "store", name: "App Store", cats: ["System"], actions: [] },
];
const lim = { apps: 12, actions: 6 };
const ids = (list) => Array.from(list, (a) => a.id);
// values made in the vm context have its prototypes: compare them as plain data
const plain = (x) => JSON.parse(JSON.stringify(x));

test("score: name start > word start > contains > nothing", () => {
  assert.strictEqual(S.score("Markdown Notes", "mark"), 3);
  assert.strictEqual(S.score("Markdown Notes", "not"), 2);
  assert.strictEqual(S.score("Markdown Notes", "down"), 1);
  assert.strictEqual(S.score("Markdown Notes", "xyz"), 0);
  assert.strictEqual(S.score("foot-server", "serv"), 2, "a dash splits words");
  assert.strictEqual(S.score("org.gnome.Nautilus", "naut"), 2, "a dot splits words");
  assert.strictEqual(S.score("Terminal", ""), 0, "an empty query matches nothing");
});
test("a category prefix adds one on top of the doubled name score", () => {
  assert.strictEqual(S.appScore(apps[0], "term"), 7, "name start (6) + TerminalEmulator (1)");
  assert.strictEqual(S.appScore(apps[1], "term"), 1, "kitty only by its category");
  assert.strictEqual(S.appScore(apps[3], "off"), 1);
});
test("results sort by score, then by name", () => {
  const r = S.search(apps, "term", [], lim);
  assert.deepStrictEqual(ids(r.apps), ["foot", "kitty"]);
  const n = S.search(apps, "n", [], lim);
  // Notes by word start (4) comes after no name start; name starts: none begin with n … word start: Markdown Notes, contains: Terminal, Chromium …
  assert.strictEqual(n.apps[0].id, "mdview", JSON.stringify(ids(n.apps)));
});
test("hidden helpers are never found, also not their actions", () => {
  const r = S.search(apps, "foot", [], lim);
  assert.ok(!ids(r.apps).includes("foot-server"), JSON.stringify(ids(r.apps)));
  assert.ok(!S.visible(apps).some((a) => a.id === "foot-server"));
});
test("query is trimmed and case-insensitive", () => {
  assert.deepStrictEqual(ids(S.search(apps, "  CHROM ", [], lim).apps), ["chromium"]);
});
test("actions: by their own name, the better match first, with their app", () => {
  const r = S.search(apps, "new", [], lim);
  assert.deepStrictEqual(plain(r.actions.map((x) => x.app.id + ":" + x.action.id)),
    ["foot:new", "chromium:new-window", "chromium:incognito", "mdview:new-note", "files:new-window"]);
  const w = S.search(apps, "window", [], lim);
  // "New Window" (word start, 2) and "New Incognito Window" (word start, 2) keep the apps' order
  assert.deepStrictEqual(plain(w.actions.map((x) => x.action.id)), ["new-window", "incognito", "new-window"]);
  const inc = S.search(apps, "incog", [], lim);
  assert.deepStrictEqual(plain(inc.actions.map((x) => x.action.id)), ["incognito"]);
});
test("limits: at most 12 apps and 6 actions", () => {
  const many = [];
  for (let i = 0; i < 30; i++) many.push({ id: "a" + i, name: "App " + i, cats: [], actions: [{ id: "x", name: "Act " + i }] });
  const r = S.search(many, "a", [], lim);
  assert.strictEqual(r.apps.length, 12);
  assert.strictEqual(r.actions.length, 6);
});
test("first result: an app, else an action, else the web row", () => {
  assert.deepStrictEqual(plain(S.search(apps, "obs", [], lim).first), plain({ kind: "app", app: apps[4] }));
  const a = S.search(apps, "incog", [], lim).first;
  assert.strictEqual(a.kind, "action"); assert.strictEqual(a.action.id, "incognito"); assert.strictEqual(a.app.id, "chromium");
  assert.deepStrictEqual(plain(S.search(apps, " weather today ", [], lim).first), { kind: "web", text: "weather today" });
});
test("empty query: suggested in order, unknown and hidden ids left out", () => {
  const r = S.search(apps, "", ["mdview", "nope", "foot-server", "foot"], lim);
  assert.deepStrictEqual(ids(r.apps), ["mdview", "foot"]);
  assert.strictEqual(r.first, null);
  assert.strictEqual(r.actions.length, 0);
});
test("empty query without suggestions: the first apps by name", () => {
  const r = S.search(apps, "  ", [], { apps: 3, actions: 6 });
  assert.deepStrictEqual(ids(r.apps), ["store", "chromium", "papers"]);
});
test("a map id → app works as well as an array", () => {
  const map = {}; apps.forEach((a) => { map[a.id] = a });
  assert.deepStrictEqual(ids(S.search(map, "term", [], lim).apps), ["foot", "kitty"]);
});
test("drawer: all visible apps A–Z, filtered by contains or category prefix", () => {
  assert.deepStrictEqual(ids(S.drawer(apps, "")), ["store", "chromium", "papers", "files", "kitty", "mdview", "obsidian", "settings", "foot"], "localeCompare: case does not split the list");
  assert.deepStrictEqual(ids(S.drawer(apps, "off")), ["papers", "mdview", "obsidian"], "Office by category");
  assert.deepStrictEqual(ids(S.drawer(apps, "ium")), ["chromium"], "contains");
  assert.deepStrictEqual(ids(S.drawer(apps, "zzz")), []);
});
test("drawer release: a fling decides by direction, else the commit share", () => {
  assert.strictEqual(S.settleOpen(0.1, 900, 500, 0.35), true);
  assert.strictEqual(S.settleOpen(0.9, -900, 500, 0.35), false);
  assert.strictEqual(S.settleOpen(0.5, 100, 500, 0.35), true);
  assert.strictEqual(S.settleOpen(0.3, -100, 500, 0.35), false);
});
test("velocity over the last window of samples", () => {
  const s = [[0, 0], [100, 50], [150, 100], [180, 160]];
  // window 80 ms: from t=100 to t=180, 110 px → 1375 px/s
  assert.strictEqual(Math.round(S.velocity(s, 80)), 1375);
  assert.strictEqual(S.velocity([[0, 5]], 80), 0);
  assert.strictEqual(Math.round(S.velocity([[0, 100], [50, 50]], 80)), -1000);
});
console.log(`${n} tests passed`);
