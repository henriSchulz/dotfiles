.pragma library
// henri.tablet-v4's Material home screen (MaterialHome.qml): its geometry and the pure parts of
// its behaviour, ported from the lab (lab/mui-material/src/Launcher.jsx, src/model.js) — no QML.
// All in logical px of the home screen's window (W × H, below the bar, above the home zone).
// m = Theme.core.surface.material. Tests: node tests/material_test.js
// The grid's own model (pages, page breaks, folders, place/dropAt) stays HomeModel.js.

function clamp(lo, hi, v) { return Math.max(lo, Math.min(hi, v)) }

// Launcher3's DeviceProfile as Launcher.jsx simplifies it: the drop target bar on top, then the
// grid (cols × rows, turned in portrait), the page dots, the hotseat band and the search bar at
// the bottom, the edge margin around it all.
function geometry(W, H, m) {
  var g = m.grid, land = W >= H
  var cols = land ? g.cols : g.rows, rows = land ? g.rows : g.cols
  var labelH = Math.round(m.type.body2 * m.type.body2Line)
  var hotseatH = g.icon + g.hotseatPad
  var top = g.dropBar, side = g.edge
  var bottom = g.edge + m.search.height + g.searchGap + hotseatH + g.dotsBand
  var cellW = (W - 2 * side) / cols
  var cellH = Math.max(1, (H - top - bottom) / rows)
  var hotseatTop = H - g.edge - m.search.height - g.searchGap - hotseatH
  var searchW = Math.max(0, Math.min(W - 2 * side, m.search.maxWidth))
  return {
    W: W, H: H, land: land, cols: cols, rows: rows, perPage: cols * rows,
    icon: g.icon, labelH: labelH, hotseatH: hotseatH,
    top: top, side: side, bottom: bottom, cellW: cellW, cellH: cellH,
    iconX: (cellW - g.icon) / 2, iconY: (cellH - g.icon - g.labelGap - labelH) / 2,
    hotseatTop: hotseatTop, hotseatY: hotseatTop + (hotseatH - g.icon) / 2,
    dotsY: hotseatTop - g.dotsBand,
    search: { x: (W - searchW) / 2, y: H - g.edge - m.search.height, w: searchW, h: m.search.height }
  }
}

// a grid cell's top left corner on the track (all pages side by side)
function cellX(c, geo) { return c.page * geo.W + geo.side + c.col * geo.cellW }
function cellY(c, geo) { return geo.top + c.row * geo.cellH }

// The hotseat: its icons centred, one grid column each — so a full hotseat lines up with the grid.
// x of icon i of n (its left edge)
function hotseatX(i, n, geo) { return geo.W / 2 - n * geo.cellW / 2 + i * geo.cellW + geo.iconX }
// the slot for a held icon at x: counted from where the row would stand with it in it
function hotseatSlot(list, id, x, geo) {
  var n = list.filter(function (d) { return d !== id }).length + 1
  var left = geo.W / 2 - n * geo.cellW / 2
  return clamp(0, n - 1, Math.floor((x - left) / geo.cellW))
}
// a held app over the hotseat band (a little above it counts: `slack`)
function overHotseat(y, geo, slack) { return y > geo.hotseatTop - slack && y < geo.hotseatTop + geo.hotseatH }
// room for one more (or it is one of them already)
function hotseatRoom(list, id, max) { return list.indexOf(id) >= 0 || list.filter(function (x) { return x !== id }).length < max }
// the hotseat at the start: the saved one, else the Dock's pinned apps (dock.json is never written);
// only apps the home screen knows, each once, at most `max`
function arrangeHotseat(saved, pinned, known, max) {
  var src = Array.isArray(saved) ? saved : pinned || [], out = []
  for (var i = 0; i < src.length && out.length < max; i++) {
    var id = String(src[i])
    if (known[id] && out.indexOf(id) < 0) out.push(id)
  }
  return out
}

// ---- drop targets (Launcher3 DropTargetBar): an app from the grid or the hotseat can be removed
// or uninstalled; a folder, a widget and an app out of a folder only removed
function dropTargets(kind, from) { return kind === "app" && from !== "folder" ? ["remove", "uninstall"] : ["remove"] }
// the target under the finger: only in the bar on top; with two, the left half is the first
function targetAt(targets, x, y, geo) {
  if (y > geo.top || !targets.length) return ""
  return targets.length === 1 ? targets[0] : x < geo.W / 2 ? targets[0] : targets[1]
}

// ---- lists
// `list` with `id` taken out (wherever it was, or not there) and put in at index i (clamped)
function moveTo(list, id, i) {
  var out = list.filter(function (x) { return x !== id })
  i = clamp(0, out.length, i)
  out.splice(i, 0, id)
  return out
}
// put `id` in before the idx-th entry that shows (entries that do not show keep their place)
function insertAt(list, id, idx, shows) {
  var rest = list.filter(function (x) { return x !== id })
  var before = rest.filter(shows)[idx]
  return moveTo(list, id, before === undefined ? rest.length : rest.indexOf(before))
}

// ---- folders: layout = { order, folders: { key: { name, items } }, hotseat }
function copyFolders(folders) {
  var out = {}
  for (var k in folders) out[k] = { name: folders[k].name, items: folders[k].items.slice() }
  return out
}
function folderOf(folders, id) {
  for (var k in folders) if (folders[k].items.indexOf(id) >= 0) return "folder:" + k
  return ""
}
// app `id` taken out of its folder → { layout, at, dissolved }: the layout without it anywhere and
// the grid index right after where the folder stood. A folder left empty goes; a folder left with
// one app becomes that app (Launcher3 replaces a folder of one by its app)
function takeOut(layout, id) {
  var fid = folderOf(layout.folders, id)
  if (!fid) return { layout: layout, at: layout.order.length, dissolved: "" }
  var folders = copyFolders(layout.folders), k = fid.slice(7), order = layout.order.slice()
  folders[k].items = folders[k].items.filter(function (x) { return x !== id })
  var fi = order.indexOf(fid), at = fi + 1, dissolved = ""
  if (!folders[k].items.length) { delete folders[k]; if (fi >= 0) { order.splice(fi, 1); at-- } }
  else if (folders[k].items.length === 1) {
    dissolved = folders[k].items[0]
    delete folders[k]
    if (fi >= 0) order[fi] = dissolved
  }
  return { layout: { order: order, folders: folders, hotseat: (layout.hotseat || []).slice() }, at: Math.max(0, at), dissolved: dissolved }
}
// an app dropped on an app (a new folder in the target's place, named `name`) or on a folder (it
// joins at the end); from the grid or the hotseat
function fold(layout, id, target, name) {
  if (!id || id === target || id.indexOf("folder:") === 0 || id.indexOf("widget:") === 0) return layout
  var folders = copyFolders(layout.folders)
  var order = layout.order.filter(function (x) { return x !== id })
  var hotseat = (layout.hotseat || []).filter(function (x) { return x !== id })
  var at = order.indexOf(target)
  if (at < 0) return layout
  if (target.indexOf("folder:") === 0) {
    var f = folders[target.slice(7)]
    if (!f) return layout
    if (f.items.indexOf(id) < 0) f.items.push(id)
  } else {
    var n = 1
    while (folders["f" + n]) n++
    folders["f" + n] = { name: name || "Folder", items: [target, id] }
    order[at] = "folder:f" + n
  }
  return { order: order, folders: folders, hotseat: hotseat }
}

// ---- the open folder: a panel of up to `cols` columns of grid cells, under its name's band,
// centred between the drop bar and the hotseat (Launcher.jsx)
function folderPanel(n, geo, m) {
  var f = m.folder, cols = clamp(1, f.cols, n), rows = Math.max(1, Math.ceil(n / f.cols))
  var w = cols * geo.cellW + 2 * f.pad, h = f.titleH + rows * geo.cellH + f.pad
  var x = (geo.W - w) / 2, y = Math.max(geo.top, (geo.H - geo.bottom - h) / 2 + geo.top / 2)
  return { x: x, y: y, w: w, h: h, cols: f.cols }
}
// item i's icon in the panel (screen coordinates)
function folderItem(i, p, geo, m) {
  return { x: p.x + m.folder.pad + (i % p.cols) * geo.cellW + geo.iconX, y: p.y + m.folder.titleH + Math.floor(i / p.cols) * geo.cellH + geo.iconY }
}
// the index a held app takes in a folder of n at (x, y)
function folderSlot(x, y, n, p, geo, m) {
  var col = clamp(0, p.cols - 1, Math.floor((x - p.x - m.folder.pad) / geo.cellW))
  var row = Math.max(0, Math.floor((y - p.y - m.folder.titleH) / geo.cellH))
  return clamp(0, Math.max(0, n - 1), row * p.cols + col)
}
function inRect(r, x, y) { return x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h }

// ---- a menu (ActionMenu.jsx on MUI's Popover): out of a rect, centred above it when it fits,
// else below; or at a point (its top left there). Kept `margin` inside W × H.
// → { x, y, originX, originY } (origin in the menu's own coordinates, where it grows from)
function placeMenu(anchor, w, h, W, H, gap, margin) {
  var x, y, oy
  if (anchor.w !== undefined) {
    x = anchor.x + anchor.w / 2 - w / 2
    if (anchor.y - gap - h >= margin) { y = anchor.y - gap - h; oy = h }
    else { y = anchor.y + anchor.h + gap; oy = 0 }
  } else { x = anchor.x; y = anchor.y; oy = 0 }
  var cx = clamp(margin, Math.max(margin, W - margin - w), x)
  var cy = clamp(margin, Math.max(margin, H - margin - h), y)
  var ox = anchor.w !== undefined ? anchor.x + anchor.w / 2 - cx : anchor.x - cx
  return { x: cx, y: cy, originX: clamp(0, w, ox), originY: anchor.w !== undefined ? oy : clamp(0, h, anchor.y - cy) }
}

// the finger's speed over its last samples [[ms, v]]: 0 when it rested before the lift
function speed(samples, now, window) {
  if (samples.length < 2) return 0
  var a = samples[0], b = samples[samples.length - 1]
  if (now - b[0] > window || b[0] <= a[0]) return 0
  return (b[1] - a[1]) * 1000 / (b[0] - a[0])
}
// the same over samples [t, x, y]: the vertical speed (px/s, down positive)
function speedY(samples, now, window) {
  if (samples.length < 2) return 0
  var a = samples[0], b = samples[samples.length - 1]
  if (now - b[0] > window || b[0] <= a[0] || b.length < 3 || a.length < 3) return 0
  return (b[2] - a[2]) * 1000 / (b[0] - a[0])
}
