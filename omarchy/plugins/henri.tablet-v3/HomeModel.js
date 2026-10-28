.pragma library
// Tablet mode's home screen and home gesture (Home.qml): the geometry, no QML. All in logical px
// of the app area (W × H, the overlay's size); a card's x / y are its centre's offset from the
// area's centre, s its scale. cfg = Theme.core.surface.tablet.home.
// Tests: node tests/home_test.js

// how far past a limit a finger gets: less and less, never more than `limit`
function rubber(x, limit) { return limit * (1 - 1 / (x / limit + 1)) }

// The card under a finger that has come `up` px up (negative: pushed down) and `dx` px sideways,
// moving up at `vy` px/s. As SpringBoard does it: the scale falls linearly with the travel
// (1 − up / (shrinkTravel × H)) down to minScale, then only resists; the bottom edge stays under the
// finger; sideways it follows, damped by up to sideDamp the faster it goes up; rubber-banded where
// `blocked` says there is no app.
function follow(up, dx, W, H, cfg, blocked, vy) {
  var p = Math.max(0, up) / (H * cfg.shrinkTravel)
  var lin = 1 - p
  var s = lin >= cfg.minScale ? lin : cfg.minScale - rubber(cfg.minScale - lin, 0.08)
  var y = H / 2 - Math.max(0, up) - s * H / 2 + (up < 0 ? rubber(-up, cfg.pushDown) : 0)
  var damp = 1 - cfg.sideDamp * Math.max(0, Math.min(1, (vy || 0) / cfg.sideDampSpeed))
  var x = dx * damp
  if (blocked && ((dx > 0 && blocked.left) || (dx < 0 && blocked.right))) x = (dx > 0 ? 1 : -1) * rubber(Math.abs(dx), cfg.sideResist)
  return { s: s, x: x, y: y, progress: p, home: Math.min(1, p * cfg.homeReveal) }
}

// Where a released card goes, as SpringBoard decides it from the finger's last speed (re-read on
// release, so a pause shown earlier does not lock it): "back" | "home" | "switcher" | "next" | "prev".
//   travel up px, dx sideways px, vUp / vx px/s, n apps, cur the card's index, W × H the area
function destination(travel, dx, vUp, vx, n, cur, W, H, cfg, tcfg) {
  var side = Math.abs(dx) > cfg.slideCommit * W
          || (Math.abs(vx) > tcfg.slideFlick && Math.abs(vUp) < cfg.homeSteep * Math.abs(vx) && (vx > 0) === (dx > 0) && Math.abs(dx) > tcfg.slop)
  var step = dx < 0 ? 1 : -1
  if (side && travel < H * cfg.homeDistance / 2 && cur + step >= 0 && cur + step < n) return step > 0 ? "next" : "prev"
  if (travel < cfg.minTravel) return "back"
  if (vUp > cfg.homeVelocity) return "home"
  if (vUp > cfg.homeMinVelocity && vUp > cfg.homeSteep * Math.abs(vx)) return "home"
  if (Math.abs(vUp) < cfg.homeMinVelocity && Math.abs(vx) < cfg.homeMinVelocity) return "switcher"
  if (vUp < -cfg.homeMinVelocity) return "back"
  return travel > cfg.homeDistance * H ? "home" : "back"
}

// the cards beside the one under the finger, at its scale: i - cur places to its right
function besideX(i, cur, s, x, W, cfg) { return x + (i - cur) * (s * W + cfg.cardGap) }

// The App Switcher: a few apps in one larger row, more in two rows; the newest column on the
// right, older ones to the left, scrolling sideways. sx = where the newest column's centre sits.
function switcherGeo(n, W, H, cfg) {
  var rows = n > cfg.oneRow ? 2 : 1
  var s = rows === 2 ? cfg.switcherScale
                     : Math.min(cfg.oneRowScale, (W - 2 * cfg.cardGap - cfg.cardGap * (n - 1)) / Math.max(1, n) / W)
  var cw = s * W, ch = s * H
  var stepX = cw + cfg.cardGap, stepY = ch + cfg.rowGap, cols = Math.ceil(n / rows)
  var edge = W / 2 - cfg.edgeInset - cw / 2
  var span = (cols - 1) * stepX
  // all columns on screen: centred; more: the newest at the right edge, scrolling to the oldest
  var fits = span + cw <= W - 2 * cfg.cardGap + 0.5
  var lo = fits ? span / 2 : edge
  var hi = fits ? span / 2 : span - edge
  return { s: s, rows: rows, stepX: stepX, stepY: stepY, lo: lo, hi: hi, cols: cols }
}
// card i of n (0 = oldest, n-1 = newest)
function switcherPos(i, n, sx, g, cfg) {
  var back = n - 1 - i, k = Math.floor(back / g.rows), r = back % g.rows
  return { x: sx - k * g.stepX, y: g.rows === 1 ? cfg.rowShift : (r === 0 ? -g.stepY / 2 : g.stepY / 2) + cfg.rowShift }
}
// where a scroll lands: momentum, then a whole column
function switcherSnap(sx, velocity, g, cfg) {
  var t = sx + velocity * cfg.switcherMomentum
  return Math.max(g.lo, Math.min(g.hi, g.lo + Math.round((t - g.lo) / g.stepX) * g.stepX))
}
// a finger scrolling the switcher past its ends meets a rubber band
function switcherClamp(sx, g, limit) {
  if (sx < g.lo) return g.lo - rubber(g.lo - sx, limit)
  if (sx > g.hi) return g.hi + rubber(sx - g.hi, limit)
  return sx
}

// The home screen's grid and dock for an area of W × H.
function grid(W, H, cfg) {
  var land = W >= H
  var icon = Math.round(Math.min(W, H) * (land ? cfg.iconShare : cfg.iconSharePortrait))
  var dockIcon = Math.round(icon * cfg.dockIcon)
  var dockH = Math.round(dockIcon * cfg.dockHeight)
  var dockGap = Math.round(icon * cfg.dockGap)
  return {
    cols: land ? cfg.cols : cfg.rows, rows: land ? cfg.rows : cfg.cols,
    icon: icon, dockIcon: dockIcon, dockH: dockH, dockGap: dockGap,
    dockPad: Math.round(dockIcon * cfg.dockPad), dockSpace: Math.round(dockIcon * cfg.dockSpace),
    side: Math.round(W * (land ? cfg.sideShare : cfg.sideSharePortrait)),
    top: Math.round(H * cfg.topShare),
    bottom: dockH + dockGap + cfg.dotsAbove * 2 + cfg.dot,
    perPage: cfg.cols * cfg.rows
  }
}

// the corner radius of a card at scale s morphing (m 0 → 1) into an icon of `iconSize` on screen,
// in the card's own px (it is drawn scaled by s)
function cardRadius(s, m, H, cfg) {
  var r = cfg.cardRadius / Math.max(s, 0.05) * Math.min(1, (1 - s) * 6)
  return (1 - m) * r + m * H * cfg.iconRadius
}

// ---- edit mode: the grid's order
// the saved order first (only apps still there), apps the order does not know yet after it in
// their own order — iPadOS puts a new app at the end
function arrange(ids, saved) {
  var have = {}, out = []
  for (var i = 0; i < ids.length; i++) have[ids[i]] = true
  var placed = {}
  for (var j = 0; saved && j < saved.length; j++) {
    var s = saved[j]
    if (have[s] && !placed[s]) { out.push(s); placed[s] = true }
  }
  for (var k = 0; k < ids.length; k++) if (!placed[ids[k]]) { out.push(ids[k]); placed[ids[k]] = true }
  return out
}
// `list` with `id` taken out and put in at index i (clamped)
function moveTo(list, id, i) {
  var out = list.filter(function (x) { return x !== id })
  if (out.length === list.length) return list.slice()
  i = Math.max(0, Math.min(out.length, i))
  out.splice(i, 0, id)
  return out
}
// the slot under (x, y) — screen coordinates — on page p of a grid of n apps
function slotAt(x, y, p, n, g, cellW, cellH) {
  var c = Math.max(0, Math.min(g.cols - 1, Math.floor((x - g.side) / cellW)))
  var r = Math.max(0, Math.min(g.rows - 1, Math.floor((y - g.top) / cellH)))
  return Math.max(0, Math.min(n - 1, p * g.perPage + r * g.cols + c))
}
// a held icon near a side turns the page that way: -1 left, 1 right, 0 none
function edgeOf(x, W, cfg) {
  var z = W * cfg.edit.edgeZone
  return x < z ? -1 : x > W - z ? 1 : 0
}

// ---- folders (iPadOS): an entry "folder:<key>" of the order stands for folders[key] =
// { name, items: [app ids] }; every app is in one place only — the grid or one folder
function isFolder(id) { return typeof id === "string" && id.indexOf("folder:") === 0 && id.length > 7 }
function folderKey(id) { return id.slice(7) }
// The grid from the home screen's apps (`ids`, in their own order) and what was saved: the saved
// order first, a folder keeps the apps still there (the first place an app is named wins) and
// goes when none is left, apps nobody placed yet come last. → { order, folders }
function arrangeLayout(ids, savedOrder, savedFolders) {
  var have = {}, taken = {}, order = [], folders = {}
  for (var i = 0; i < ids.length; i++) have[ids[i]] = true
  var src = savedFolders || {}
  for (var j = 0; savedOrder && j < savedOrder.length; j++) {
    var s = savedOrder[j]
    if (isFolder(s)) {
      var k = folderKey(s), f = src[k]
      if (!f || folders[k] || !Array.isArray(f.items)) continue
      var items = []
      for (var m = 0; m < f.items.length; m++) {
        var a = f.items[m]
        if (have[a] && !taken[a]) { taken[a] = true; items.push(a) }
      }
      if (!items.length) continue
      folders[k] = { name: typeof f.name === "string" && f.name ? f.name : "Folder", items: items }
      order.push(s)
    } else if (have[s] && !taken[s]) { taken[s] = true; order.push(s) }
  }
  for (var n = 0; n < ids.length; n++) if (!taken[ids[n]]) { taken[ids[n]] = true; order.push(ids[n]) }
  return { order: order, folders: folders }
}
// the folder holding app `id`, or ""
function folderOf(folders, id) {
  for (var k in folders) if (folders[k].items.indexOf(id) >= 0) return "folder:" + k
  return ""
}
function copyFolders(folders) {
  var out = {}
  for (var k in folders) out[k] = { name: folders[k].name, items: folders[k].items.slice() }
  return out
}
// app `id` dropped onto `target` (an app: both become a new folder in the target's place, named
// `name`; a folder: it joins at the end) → a new { order, folders }
function fold(layout, id, target, name) {
  if (!id || id === target || isFolder(id)) return layout
  var folders = copyFolders(layout.folders), order = layout.order.filter(function (x) { return x !== id })
  var at = order.indexOf(target)
  if (at < 0) return layout
  if (isFolder(target)) {
    var f = folders[folderKey(target)]
    if (!f) return layout
    if (f.items.indexOf(id) < 0) f.items.push(id)
  } else {
    var n = 1
    while (folders["f" + n]) n++
    folders["f" + n] = { name: name || "Folder", items: [target, id] }
    order[at] = "folder:f" + n
  }
  return { order: order, folders: folders }
}
// app `id` taken out of its folder and put on the grid at index `at` (clamped; -1: right after the
// folder); a folder left empty goes → a new { order, folders }
function unfold(layout, id, at) {
  var fid = folderOf(layout.folders, id)
  if (!fid) return layout
  var folders = copyFolders(layout.folders), k = folderKey(fid), order = layout.order.slice()
  folders[k].items = folders[k].items.filter(function (x) { return x !== id })
  var fi = order.indexOf(fid)
  if (at < 0) at = fi + 1
  if (!folders[k].items.length) { delete folders[k]; order.splice(fi, 1); if (at > fi) at-- }
  at = Math.max(0, Math.min(order.length, at))
  order.splice(at, 0, id)
  return { order: order, folders: folders }
}
// an item moved inside a folder: its apps with `id` at index i
function moveInFolder(layout, key, id, i) {
  var folders = copyFolders(layout.folders)
  if (!folders[key]) return layout
  folders[key].items = moveTo(folders[key].items, id, i)
  return { order: layout.order.slice(), folders: folders }
}
// A new folder's name from its apps' desktop categories, as iPadOS names it by the App Store's:
// the first of `names` (category → name, in order of preference) that all of them share
function folderName(catLists, names, fallback) {
  for (var i = 0; i < names.length; i++) {
    var c = names[i][0], all = catLists.length > 0
    for (var j = 0; j < catLists.length; j++) if ((catLists[j] || []).indexOf(c) < 0) { all = false; break }
    if (all) return names[i][1]
  }
  return fallback
}
// the folder's mini grid on its tile: the first `cols × cols` apps
function miniApps(items, cols) { return items.slice(0, cols * cols) }
