.pragma library
// The running Claude Code sessions as the bar shows them, and when one is worth a notification.
// Pure (node tests/sessions_test.js). Input: `sessions-backend live` entries
// ({sessionId, pid, status busy|idle, state working|blocked|done, kind, name, cwd, window, job}).

// working: on a turn · attention: waits for Henri (a question, a permission, or its turn is over) · "" not running
function statusOf(l) {
  if (!l) return ""
  if (!l.pid) return l.state === "blocked" ? "attention" : ""
  if (l.state === "blocked") return "attention"
  if (l.status === "busy") return "working"
  return "attention"
}

function statusText(l) {
  var st = statusOf(l)
  if (st === "working") return l.kind === "background" ? "Working in the background" : "Working"
  if (st === "attention") return l.state === "blocked" ? "Waiting for you" : "Your turn"
  return ""
}

function baseName(p) {
  var parts = String(p || "").replace(/\/+$/, "").split("/")
  return parts[parts.length - 1] || "Home"
}

// live entries + titles ({id: {title, folder}}) → rows for the popup, waiting ones first
function rows(live, titles, home) {
  var out = []
  for (var i = 0; i < live.length; i++) {
    var l = live[i], st = statusOf(l)
    if (!st) continue
    var t = titles[l.sessionId] || {}
    out.push({ id: l.sessionId, title: t.title || l.name || "New session",
               folder: t.folder || (l.cwd === home ? "Home" : baseName(l.cwd)),
               status: st, statusText: statusText(l), window: l.window || "", job: l.job || "", pid: l.pid || 0 })
  }
  out.sort(function (a, b) { return (a.status === b.status ? 0 : a.status === "attention" ? -1 : 1) })
  return out
}

// prev: {id: {busy, since, blocked}} from the last snapshot (null on the first: nothing is new then)
// → {next, notices: [{id, kind: "blocked" | "done"}]}. A turn shorter than notifyAfter that ends
// stays quiet; a session whose terminal is the focused window never notifies.
function decide(prev, live, now, notifyAfter, activeWindow) {
  var next = {}, notices = []
  for (var i = 0; i < live.length; i++) {
    var l = live[i], id = l.sessionId
    var blocked = l.state === "blocked"
    var busy = !!l.pid && l.status === "busy"
    var p = prev ? prev[id] : null
    next[id] = { busy: busy, since: busy ? (p && p.busy ? p.since : now) : 0, blocked: blocked }
    if (!p) continue
    var looking = !!l.window && l.window === activeWindow
    if (looking) continue
    if (blocked && !p.blocked) notices.push({ id: id, kind: "blocked" })
    else if (p.busy && !busy && !blocked && l.pid && now - p.since >= notifyAfter) notices.push({ id: id, kind: "done" })
  }
  return { next: next, notices: notices }
}
