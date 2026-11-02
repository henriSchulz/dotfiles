// node tests/sessions_test.js — the bar's status and notification rules
const fs = require("fs"), path = require("path")
const src = fs.readFileSync(path.join(__dirname, "..", "Sessions.js"), "utf8").replace(".pragma library", "")
const S = new Function(src + "; return { statusOf, statusText, rows, decide }")()
let fails = 0
function ok(c, what) { if (!c) { fails++; console.log("FAIL " + what) } else console.log("ok   " + what) }
const A = (o) => Object.assign({ sessionId: "a", pid: 10, status: "busy", state: "", kind: "interactive", cwd: "/home/h/p", window: "0x1" }, o)

ok(S.statusOf(A()) === "working", "busy = working")
ok(S.statusOf(A({ status: "idle" })) === "attention", "idle = your turn")
ok(S.statusOf(A({ state: "blocked" })) === "attention", "blocked wins over busy")
ok(S.statusOf(A({ pid: 0, state: "done" })) === "", "done job without process = not running")
ok(S.statusText(A({ status: "idle" })) === "Your turn", "idle text")
ok(S.statusText(A({ state: "blocked" })) === "Waiting for you", "blocked text")

let r = S.decide(null, [A()], 0, 30000, "")
ok(r.notices.length === 0, "first snapshot never notifies")
r = S.decide(r.next, [A()], 20000, 30000, "")
ok(r.next.a.since === 0, "busy since stays at the turn's start")
r = S.decide(r.next, [A({ status: "idle" })], 40000, 30000, "")
ok(r.notices.length === 1 && r.notices[0].kind === "done", "a 40 s turn that ends notifies")
let q = S.decide(S.decide(null, [A()], 0, 30000, "").next, [A({ status: "idle" })], 10000, 30000, "")
ok(q.notices.length === 0, "a 10 s turn stays quiet")
q = S.decide(S.decide(null, [A()], 0, 30000, "").next, [A({ state: "blocked" })], 1000, 30000, "")
ok(q.notices.length === 1 && q.notices[0].kind === "blocked", "turning blocked notifies at once")
q = S.decide(q.next, [A({ state: "blocked" })], 2000, 30000, "")
ok(q.notices.length === 0, "staying blocked notifies once")
q = S.decide(S.decide(null, [A()], 0, 30000, "").next, [A({ state: "blocked" })], 1000, 30000, "0x1")
ok(q.notices.length === 0, "no notice for the focused terminal")
q = S.decide(S.decide(null, [A({ kind: "background", window: "" })], 0, 30000, "0x1").next, [A({ kind: "background", window: "", status: "idle" })], 60000, 30000, "0x1")
ok(q.notices.length === 1, "background session without window notifies")

const rows = S.rows([A({ sessionId: "w" }), A({ sessionId: "x", status: "idle" }), A({ sessionId: "d", pid: 0, state: "done" })],
                    { x: { title: "Fix", folder: "mdview" } }, "/home/h")
ok(rows.length === 2 && rows[0].id === "x" && rows[0].title === "Fix" && rows[1].folder === "p", "rows: waiting first, titles, done jobs left out")
process.exit(fails ? 1 : 0)
