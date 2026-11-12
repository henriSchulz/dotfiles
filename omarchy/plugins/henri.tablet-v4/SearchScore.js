.pragma library
// Search and filtering for the Material search view (SearchView.qml) and the app drawer
// (AppDrawer.qml) — the lab's rules (lab/mui-material/src/SearchView.jsx, AppDrawer.jsx), pure JS so
// tests/search_test.js runs them under node.
//
// An app is { id, name, icon, cats: [string], actions: [{ id, name, command? }], launcherHidden? }.
// `apps` may be an array of those or a map id → app. launcherHidden (or hidden) apps are never found:
// Omarchy's helpers (foot-server …) that the launcher hides.

// how well `q` (lower case, trimmed) matches `text`: the start of the name 3, the start of a word 2,
// anywhere 1, not at all 0
function score(text, q) {
  var t = String(text || "").toLowerCase()
  if (!q) return 0
  if (t.indexOf(q) === 0) return 3
  var words = t.split(/[\s\-_.]+/)
  for (var i = 0; i < words.length; i++) if (words[i].indexOf(q) === 0) return 2
  return t.indexOf(q) >= 0 ? 1 : 0
}

// does one of the app's categories start with q
function catPrefix(app, q) {
  var cats = app.cats || []
  for (var i = 0; i < cats.length; i++) if (String(cats[i]).toLowerCase().indexOf(q) === 0) return true
  return false
}

// the name counts double, a category prefix adds one: "term" finds Terminal (6+0) before an app in the
// category TerminalEmulator whose name does not match (0+1)
function appScore(app, q) {
  return score(app.name, q) * 2 + (catPrefix(app, q) ? 1 : 0)
}

function norm(q) { return String(q || "").trim().toLowerCase() }

// every app the launcher shows, in a stable list
function visible(apps) {
  var list = Array.isArray(apps) ? apps : Object.keys(apps || {}).map(function (k) { return apps[k] })
  return list.filter(function (a) { return a && a.id && !a.launcherHidden && !a.hidden })
}

function byName(a, b) { return String(a.name).localeCompare(String(b.name)) }

// The search view's results for `query`:
//   { query, apps: [app], actions: [{ app, action, score }], first: { kind, app?, action?, text? } | null }
// Empty query: the suggested ids (in their order, unknown ones left out), else the first `limits.apps`
// apps by name — never an empty view. limits = { apps, actions }.
function search(apps, query, suggested, limits) {
  var q = norm(query)
  var all = visible(apps)
  var maxApps = limits && limits.apps > 0 ? limits.apps : all.length
  var maxActions = limits && limits.actions > 0 ? limits.actions : 0
  if (!q) {
    var byId = {}
    for (var i = 0; i < all.length; i++) byId[all[i].id] = all[i]
    var picked = (suggested || []).map(function (id) { return byId[id] }).filter(function (a) { return !!a })
    if (!picked.length) picked = all.slice().sort(byName)
    return { query: "", apps: picked.slice(0, maxApps), actions: [], first: null }
  }
  var found = []
  for (var j = 0; j < all.length; j++) {
    var s = appScore(all[j], q)
    if (s > 0) found.push({ a: all[j], s: s })
  }
  found.sort(function (x, y) { return y.s - x.s || byName(x.a, y.a) })
  var actions = []
  for (var k = 0; k < all.length; k++) {
    var acts = all[k].actions || []
    for (var m = 0; m < acts.length; m++) {
      var as = score(acts[m].name, q)
      if (as > 0) actions.push({ app: all[k], action: acts[m], score: as, order: actions.length })
    }
  }
  // the better match first; equal ones keep the apps' order (stable on every engine)
  actions.sort(function (x, y) { return y.score - x.score || x.order - y.order })
  var outApps = found.slice(0, maxApps).map(function (x) { return x.a })
  var outActions = actions.slice(0, maxActions).map(function (x) { return { app: x.app, action: x.action, score: x.score } })
  var first = outApps.length ? { kind: "app", app: outApps[0] }
    : outActions.length ? { kind: "action", app: outActions[0].app, action: outActions[0].action }
    : { kind: "web", text: String(query).trim() }
  return { query: q, apps: outApps, actions: outActions, first: first }
}

// The drawer's list: every app the launcher shows, A–Z; a query keeps names that contain it and apps
// with a category that starts with it (AppDrawer.jsx)
function drawer(apps, query) {
  var q = norm(query)
  var all = visible(apps).sort(byName)
  if (!q) return all
  return all.filter(function (a) { return String(a.name).toLowerCase().indexOf(q) >= 0 || catPrefix(a, q) })
}

// the release of a finger that carries the drawer: velocity in px/s, upward positive. A fling past
// `flick` decides by its direction, else the drawer stays open past `commit` of its travel (the lab's
// releaseDrawer: L.flick, L.shadeCommit)
function settleOpen(progress, velocity, flick, commit) {
  if (velocity > flick) return true
  if (velocity < -flick) return false
  return progress > commit
}

// a finger's speed over the last `windowMs` of samples [[t ms, y px] …] in px/s, downward positive
function velocity(samples, windowMs) {
  if (!samples || samples.length < 2) return 0
  var last = samples[samples.length - 1]
  var i = samples.length - 2
  while (i > 0 && last[0] - samples[i - 1][0] <= windowMs) i--
  var a = samples[i]
  var dt = last[0] - a[0]
  return dt > 0 ? (last[1] - a[1]) / dt * 1000 : 0
}
