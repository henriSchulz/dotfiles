// node tests/layout_model_test.js — every invariant of LayoutModel.js.
const fs = require("fs"), path = require("path"), assert = require("assert"), vm = require("vm");
const src = fs.readFileSync(path.join(__dirname, "..", "LayoutModel.js"), "utf8").replace(/^\.pragma library$/m, "");
const M = {};
vm.runInNewContext(src + "\nObject.assign(out, this);", { out: M });
// results cross the vm realm: copy them so deepStrictEqual compares plain host objects
for (const k of Object.keys(M)) if (typeof M[k] === "function") { const fn = M[k]; M[k] = (...args) => { const r = fn(...args); return r && typeof r === "object" ? JSON.parse(JSON.stringify(r)) : r; }; }

const ids = n => Array.from({ length: n }, (_, i) => "a" + String(i).padStart(2, "0"));
const all = l => { const out = []; M.each(l, id => out.push(id)); return out; };
const noDupes = l => { const a = all(l); assert.strictEqual(new Set(a).size, a.length, "duplicate ids: " + a); };
const small = (n, cols = 3, rows = 2) => {
  let l = M.empty(); l.settings.columns = cols; l.settings.rows = rows;
  return M.sync(l, ids(n));
};

// fresh layout: alphabetical order, paged by columns × rows
let l = small(14);
assert.deepStrictEqual(l.pages.map(p => p.length), [6, 6, 2]);
assert.strictEqual(l.pages[0][0], "app:a00");
assert.strictEqual(l.seen.length, 14);

// load: empty text, broken JSON, other version
let r = M.load("", ["x", "y"]);
assert.strictEqual(r.error, ""); assert.deepStrictEqual(r.layout.pages, [["app:x", "app:y"]]);
r = M.load("{nope", ["x"]);
assert.ok(r.error.length > 0, "broken JSON reports an error");
assert.deepStrictEqual(r.layout.pages, [["app:x"]]);
r = M.load(JSON.stringify({ version: 99 }), ["x"]);
assert.strictEqual(r.backup, true);
r = M.load("[1,2]", ["x"]);
assert.ok(r.error.length > 0);

// round trip keeps everything
r = M.load(M.serialize(l), ids(14));
assert.deepStrictEqual(r.layout.pages, l.pages);

// settings are clamped
r = M.load(JSON.stringify({ version: 1, settings: { columns: 99, rows: 1, iconSize: 3, searchPosition: "left" }, pages: [] }), ["x"]);
assert.deepStrictEqual([r.layout.settings.columns, r.layout.settings.rows, r.layout.settings.iconSize, r.layout.settings.searchPosition], [12, 3, 64, "top"]);

// duplicates in a hand-edited file collapse to the first place
r = M.load(JSON.stringify({ version: 1, settings: {}, pages: [["app:x", "app:x", "folder:f1"]],
  folders: { f1: { name: "F", items: ["app:x", "app:y"] } }, apps: {}, hidden: ["app:y", "app:z"], seen: [] }), ["x", "y", "z"]);
noDupes(r.layout);
assert.deepStrictEqual(r.layout.pages[0], ["app:x", "folder:f1"]);
assert.deepStrictEqual(r.layout.folders.f1.items, ["app:y"]);
assert.deepStrictEqual(r.layout.hidden, ["app:z"]);

// sync: new app goes to the end once, removed app leaves, reinstall places again once
l = small(5);
l = M.sync(l, ids(5).concat(["new"]));
assert.strictEqual(l.pages[l.pages.length - 1].slice(-1)[0], "app:new");
l = M.sync(l, ids(5).concat(["new"]));
assert.strictEqual(all(l).filter(x => x === "app:new").length, 1);
l = M.sync(l, ids(5));
assert.ok(!all(l).includes("app:new")); assert.ok(l.seen.includes("app:new"));
l = M.sync(l, ids(5).concat(["new"]));
assert.strictEqual(all(l).filter(x => x === "app:new").length, 1);

// first-free placement
l = small(7); l.settings.newApps = "first-free";
l = M.move(l, "app:a00", 1, 0);            // page 0 now has a free slot
l = M.sync(l, ids(7).concat(["zz"]));
assert.ok(l.pages[0].includes("app:zz"));

// move: within a page, across pages, to a new page; overflow pushes forward
l = small(12);                              // [6, 6]
let m = M.move(l, "app:a00", 0, 5);
assert.strictEqual(m.pages[0][5], "app:a00"); assert.strictEqual(m.pages[0][0], "app:a01");
m = M.move(l, "app:a00", 1, 0);             // page 1 full -> overflow to page 2
assert.deepStrictEqual(m.pages.map(p => p.length), [5, 6, 1]);
assert.strictEqual(m.pages[1][0], "app:a00");
m = M.move(l, "app:a11", 2, 0);             // new page
assert.deepStrictEqual(m.pages.map(p => p.length), [6, 5, 1]);
m = M.move(small(2), "app:a00", 1, 0);
m = M.move(m, "app:a00", 0, 0);             // emptied page disappears
assert.strictEqual(m.pages.length, 1);
noDupes(m);

// drop app on app -> folder in the target's slot
l = small(6);
let d = M.dropOnto(l, "app:a03", "app:a01", "Tools");
assert.strictEqual(d.pages[0][1], d.lastFolder);
assert.deepStrictEqual(d.folders[d.lastFolder.slice(7)].items, ["app:a01", "app:a03"]);
assert.strictEqual(d.folders.f1.name, "Tools");
assert.strictEqual(d.pages[0].length, 5);
noDupes(d);
// app onto folder joins it; folder onto anything is a no-op; self-drop no-op
d = M.dropOnto(d, "app:a05", "folder:f1");
assert.deepStrictEqual(d.folders.f1.items, ["app:a01", "app:a03", "app:a05"]);
assert.deepStrictEqual(M.dropOnto(d, "folder:f1", "app:a00").pages, d.pages);
assert.deepStrictEqual(M.dropOnto(d, "app:a00", "app:a00").pages, d.pages);
// second folder gets a new key
let d2 = M.dropOnto(d, "app:a02", "app:a00", "");
assert.strictEqual(d2.lastFolder, "folder:f2"); assert.strictEqual(d2.folders.f2.name, "Folder");

// drag out of a folder; the last app out dissolves it
let o = M.move(d, "app:a03", 0, 0);
assert.deepStrictEqual(o.folders.f1.items, ["app:a01", "app:a05"]);
assert.strictEqual(o.pages[0][0], "app:a03");
o = M.move(o, "app:a01", 0, 0); o = M.move(o, "app:a05", 0, 0);
assert.ok(!o.folders.f1); assert.ok(!o.pages.flat().includes("folder:f1"));
noDupes(o);

// a folder with one app stays (macOS keeps it too)
o = M.move(d, "app:a03", 0, 0); o = M.move(o, "app:a05", 0, 0);
assert.deepStrictEqual(o.folders.f1.items, ["app:a01"]);

// reorder in folder, ungroup, group several, rename and style
let f = M.moveInFolder(d, "folder:f1", "app:a05", 0);
assert.deepStrictEqual(f.folders.f1.items, ["app:a05", "app:a01", "app:a03"]);
let u = M.ungroup(d, "folder:f1");
assert.deepStrictEqual(u.pages[0], ["app:a00", "app:a01", "app:a03", "app:a05", "app:a02", "app:a04"]);
assert.ok(!u.folders.f1);
let g = M.groupInto(small(6), ["app:a02", "app:a04", "app:a05"], "G");
assert.strictEqual(g.pages[0][2], "folder:f1"); assert.deepStrictEqual(g.folders.f1.items, ["app:a02", "app:a04", "app:a05"]);
let s = M.styleFolder(d, "folder:f1", { name: "  ", color: "#ff0000", emoji: "🛠" });
assert.strictEqual(s.folders.f1.name, "Tools"); assert.strictEqual(s.folders.f1.color, "#ff0000");
s = M.styleFolder(s, "folder:f1", { name: "Dev", color: "red" });
assert.strictEqual(s.folders.f1.name, "Dev"); assert.strictEqual(s.folders.f1.color, null);

// hide / unhide; hidden app survives sync and does not come back
let h = M.hide(small(6), "app:a02");
assert.ok(!h.pages[0].includes("app:a02")); assert.deepStrictEqual(h.hidden, ["app:a02"]);
h = M.sync(h, ids(6));
assert.deepStrictEqual(h.hidden, ["app:a02"]); assert.ok(!h.pages.flat().includes("app:a02"));
h = M.hide(d, "app:a03");                   // hide from inside a folder
assert.deepStrictEqual(h.folders.f1.items, ["app:a01", "app:a05"]);
h = M.unhide(h, "app:a03");
assert.strictEqual(h.pages[h.pages.length - 1].slice(-1)[0], "app:a03"); assert.deepStrictEqual(h.hidden, []);

// overrides: set, clear
let ov = M.setOverride(small(2), "app:a00", { name: "Web", hideTitle: true });
assert.deepStrictEqual(ov.apps["app:a00"], { name: "Web", hideTitle: true });
ov = M.setOverride(ov, "app:a00", { name: "", hideTitle: false });
assert.ok(!ov.apps["app:a00"]);

// smaller grid re-flows; reset keeps hidden + settings
let st = M.setSettings(small(24, 6, 4), { columns: 4, rows: 3 });
assert.deepStrictEqual(st.pages.map(p => p.length), [12, 12]);
let rs = M.reset(M.hide(d, "app:a04"), ids(6));
assert.deepStrictEqual(rs.hidden, ["app:a04"]); assert.deepStrictEqual(rs.folders, {});
assert.strictEqual(rs.pages.flat().length, 5);

// locate / folderOf
assert.deepStrictEqual(M.locate(d, "app:a03"), { where: "folder", folder: "folder:f1", index: 1 });
assert.strictEqual(M.folderOf(d, "app:a00"), "");

// folder tiles (dir:): add once per path, move, survive load, sort and sync, remove
let dl = M.addDir(small(3), "/home/h/Downloads/", "");
assert.strictEqual(dl.lastDir, "dir:d1");
assert.deepStrictEqual(dl.dirs.d1, { path: "/home/h/Downloads", name: "Downloads" });
assert.strictEqual(dl.pages[0].slice(-1)[0], "dir:d1");
assert.strictEqual(M.addDir(dl, "/home/h/Downloads", "x").lastDir, "dir:d1");   // same path: no second tile
assert.deepStrictEqual(Object.keys(M.addDir(dl, "relative/path").dirs), ["d1"]);
dl = M.move(dl, "dir:d1", 0, 0);
assert.strictEqual(dl.pages[0][0], "dir:d1");
dl = M.sync(dl, ids(3));
assert.strictEqual(dl.pages[0][0], "dir:d1");
r = M.load(M.serialize(dl), ids(3));
assert.deepStrictEqual(r.layout.dirs, dl.dirs);
assert.strictEqual(r.layout.pages[0][0], "dir:d1");
assert.ok(M.reset(dl, ids(3)).pages.flat().includes("dir:d1"));
assert.deepStrictEqual(M.dropOnto(dl, "dir:d1", "app:a00").pages, dl.pages);   // no folder tile into a folder
let rd = M.removeDir(dl, "dir:d1");
assert.ok(!rd.pages.flat().includes("dir:d1")); assert.deepStrictEqual(rd.dirs, {});
r = M.load(JSON.stringify({ version: 1, settings: {}, pages: [["dir:zz", "app:x"]], dirs: { zz: { path: "nope" } }, folders: {}, apps: {}, hidden: [], seen: [] }), ["x"]);
assert.deepStrictEqual(r.layout.pages[0], ["app:x"]);                             // a broken tile is dropped
// categories page setting
assert.strictEqual(M.setSettings(small(1), { categoriesPage: true }).settings.categoriesPage, true);

// workflows: a tile after the first app, apps stay on the grid, uninstall shrinks, empty goes
let wf = M.addWorkflow(small(6), ["app:a01", "app:a03", "file:/home/h/notes.md"], "Morning");
assert.strictEqual(wf.lastWorkflow, "workflow:w1");
assert.deepStrictEqual(wf.pages[0].slice(0, 3), ["app:a00", "app:a01", "workflow:w1"]);
assert.deepStrictEqual(wf.workflows.w1, { name: "Morning", items: ["app:a01", "app:a03", "file:/home/h/notes.md"] });
assert.ok(wf.pages.flat().includes("app:a03"));
noDupes(wf);
r = M.load(M.serialize(wf), ids(6));
assert.deepStrictEqual(r.layout.workflows, wf.workflows);
let wf2 = M.sync(wf, ids(6).filter(x => x !== "a01"));
assert.deepStrictEqual(wf2.workflows.w1.items, ["app:a03", "file:/home/h/notes.md"]);
wf2 = M.editWorkflow(wf2, "workflow:w1", { name: " Abend ", items: ["app:a03"] });
assert.deepStrictEqual(wf2.workflows.w1, { name: "Abend", items: ["app:a03"] });
let wf3 = M.sync(wf2, ids(6).filter(x => x !== "a03" && x !== "a01"));
assert.ok(!wf3.workflows.w1 && !wf3.pages.flat().includes("workflow:w1"));        // nothing left to start
assert.ok(M.reset(wf, ids(6)).pages.flat().includes("workflow:w1"));
assert.ok(!M.removeWorkflow(wf, "workflow:w1").pages.flat().includes("workflow:w1"));
assert.deepStrictEqual(M.dropOnto(wf, "app:a00", "workflow:w1").pages, wf.pages);  // apps do not drop into a workflow
// folder cover
let cv = M.styleFolder(d, "folder:f1", { cover: "/home/h/Pictures/a.png" });
assert.strictEqual(cv.folders.f1.cover, "/home/h/Pictures/a.png");
assert.strictEqual(M.styleFolder(cv, "folder:f1", { cover: "rel.png" }).folders.f1.cover, null);

console.log("layout_model_test: ok");
