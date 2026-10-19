.pragma library
// Pure helpers for henri.dock. No QML state lives here: the plugin root owns
// the model, this file only turns inputs into outputs (and is unit-testable
// with plain node).

// ---------------------------------------------------------------- strings

function stripDesktop(id) {
  return String(id == null ? "" : id).trim().replace(/\.desktop$/i, "")
}

function lower(s) { return String(s == null ? "" : s).toLowerCase() }

// Last segment of a reverse-DNS id: org.gnome.Nautilus -> nautilus.
function shortId(id) {
  var s = String(id || "")
  var dot = s.lastIndexOf(".")
  return dot >= 0 && dot < s.length - 1 ? s.slice(dot + 1) : s
}

function titleCase(value) {
  var words = String(value || "").replace(/[-_.]+/g, " ").trim().split(/ +/)
  var out = []
  for (var i = 0; i < words.length; i++)
    if (words[i].length > 0) out.push(words[i].charAt(0).toUpperCase() + words[i].slice(1))
  return out.join(" ")
}

function copyMap(src) {
  var out = {}
  for (var k in src) if (Object.prototype.hasOwnProperty.call(src, k)) out[k] = src[k]
  return out
}

function toArray(list) {
  if (Array.isArray(list)) return list.slice()
  if (!list || typeof list.length !== "number") return []
  var out = []
  for (var i = 0; i < list.length; i++) out.push(list[i])
  return out
}

function expandHome(p, home) {
  var s = String(p || "")
  if (s === "~") return home
  if (s.indexOf("~/") === 0) return home + s.slice(1)
  return s
}

function baseName(p) {
  var s = String(p || "").replace(/\/+$/, "")
  var i = s.lastIndexOf("/")
  return i >= 0 ? s.slice(i + 1) : s
}

function normalizeAddress(raw) {
  var v = String(raw == null ? "" : raw).trim()
  if (!v) return ""
  if (v.slice(0, 2).toLowerCase() === "0x") v = v.slice(2)
  return "0x" + v.toLowerCase()
}

function luaString(value) {
  return String(value == null ? "" : value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')
}

// ---------------------------------------------------------------- pinned / settings

function parsePinned(raw) {
  var text = String(raw || "").trim()
  if (!text) return []
  var parsed = null
  try { parsed = JSON.parse(text) } catch (e) { return [] }
  var list = Array.isArray(parsed) ? parsed : (parsed && Array.isArray(parsed.pinned) ? parsed.pinned : [])
  var out = []
  var seen = {}
  for (var i = 0; i < list.length; i++) {
    var id = stripDesktop(typeof list[i] === "object" && list[i] ? list[i].id : list[i])
    if (!id || seen[id]) continue
    seen[id] = true
    out.push(id)
  }
  return out
}

function serializePinned(ids) {
  return JSON.stringify({ pinned: ids }, null, 2) + "\n"
}

function mergeSettings(defaults, raw) {
  var out = copyMap(defaults)
  var text = String(raw || "").trim()
  if (!text) return out
  var parsed = null
  try { parsed = JSON.parse(text) } catch (e) { return out }
  if (!parsed || typeof parsed !== "object") return out
  for (var k in parsed) if (Object.prototype.hasOwnProperty.call(defaults, k)) out[k] = parsed[k]
  return out
}

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

// ---------------------------------------------------------------- geometry

// Size of every tile for a pointer at `p` along the main axis, measured in
// the UNMAGNIFIED layout (spec §5.2): cosine bell over radiusTiles tiles.
function magnifiedSize(distance, tileSize, magnifiedSize, radiusTiles) {
  var R = tileSize * radiusTiles
  if (distance >= R) return tileSize
  var t = distance / R
  var falloff = (Math.cos(Math.PI * t) + 1) / 2
  return tileSize + (magnifiedSize - tileSize) * falloff
}

function gapFor(tileSize, fraction, min) {
  return Math.max(min, tileSize * fraction)
}

function cornerRadius(tileSize, factor, min, max) {
  return Math.round(clamp(tileSize * factor, min, max))
}

function indicatorSize(tileSize, base, min, max) {
  return clamp(Math.round(base * tileSize / 48), min, max)
}

// Base layout: entries = [{ id, kind, weight }] where weight is 1 for a tile
// (its width is tileSize) and separators carry their fixed width. Returns
// centres in a coordinate system starting at 0 (dock start), plus total.
function baseLayout(entries, tileSize, gap, padMain, separatorWidth) {
  var x = padMain
  var centres = []
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    var w = e.kind === "separator" ? separatorWidth : tileSize * (e.weight === undefined ? 1 : e.weight)
    centres.push(x + w / 2)
    x += w
    if (i < entries.length - 1) x += gap
  }
  return { centres: centres, total: x + padMain }
}

// Largest tile size (<= wanted) so that the base layout fits into `available`.
function fittingTileSize(entries, wanted, available, gapFraction, gapMin, padMain, separatorPad, minSize) {
  var tiles = 0, seps = 0
  for (var i = 0; i < entries.length; i++) {
    if (entries[i].kind === "separator") seps++
    else tiles += (entries[i].weight === undefined ? 1 : entries[i].weight)
  }
  var n = entries.length
  var size = wanted
  while (size > minSize) {
    var gap = gapFor(size, gapFraction, gapMin)
    var total = padMain * 2 + tiles * size + seps * (1 + separatorPad * 2) + Math.max(0, n - 1) * gap
    if (total <= available) break
    size -= 1
  }
  return Math.max(minSize, size)
}

// Smoothstep for the genie curve.
function smooth(t) {
  t = clamp(t, 0, 1)
  return t * t * (3 - 2 * t)
}

// Genie geometry (spec §12.2) in a dock-relative frame: u along the main axis,
// v along the cross axis with v = 0 at the dock baseline and growing away from
// the screen edge. win = { u0, u1, vNear, vFar } (vNear = window edge next to
// the dock), tile = { u0, u1, vNear, vFar }. Returns one rect per strip:
// { u, v, w, h } for strip k (k = 0 is the window edge nearest to the dock).
function genieStrips(t, win, tile, N) {
  var W = win.u1 - win.u0, T = tile.u1 - tile.u0
  var cu = (win.u0 + win.u1) / 2, ct = (tile.u0 + tile.u1) / 2
  var H = win.vFar - win.vNear
  var h = H / N
  var neck = Math.max(1, win.vNear - tile.vFar)          // distance window edge -> tile top
  var tileH = tile.vFar - tile.vNear
  var out = []
  var p = smooth(clamp(t / 0.4, 0, 1))                    // phase 1: neck forms
  var q = smooth(clamp((t - 0.4) / 0.6, 0, 1))            // phase 2: everything flows down
  for (var k = 0; k < N; k++) {
    var s = (k + 0.5) / N
    var v0 = win.vNear + s * H                            // strip centre, original
    // phase 1: strips near the dock are pulled toward the tile, the far end stays
    var pull = (1 - s) * (1 - s)
    var v1 = v0 - neck * p * pull
    // phase 2: from there to its slot inside the tile
    var vEnd = tile.vNear + s * tileH
    var v = v1 + (vEnd - v1) * q
    var hh = h + (tileH / N - h) * q
    var width, centre
    if (v >= win.vNear) { width = W; centre = cu }
    else if (v <= tile.vFar) { width = T; centre = ct }
    else {
      var g = smooth((win.vNear - v) / neck)
      width = W + (T - W) * g
      centre = cu + (ct - cu) * g
    }
    out.push({ u: centre - width / 2, v: v - hh / 2, w: width, h: hh })
  }
  return out
}

// ---------------------------------------------------------------- items

// Display name for a running app without a desktop entry.
function fallbackName(appId) { return titleCase(shortId(appId)) }

// Sort folder entries (spec §10.4) — entries from the lister:
// { name, path, icon, mime, modified, created, isDir }
function sortEntries(entries, sortBy) {
  var list = entries.slice()
  var cmpName = function (a, b) { return lower(a.name).localeCompare(lower(b.name)) }
  if (sortBy === "name") list.sort(cmpName)
  else if (sortBy === "dateModified") list.sort(function (a, b) { return (b.modified || 0) - (a.modified || 0) })
  else if (sortBy === "dateCreated") list.sort(function (a, b) { return (b.created || 0) - (a.created || 0) })
  else if (sortBy === "kind") list.sort(function (a, b) { var k = lower(a.mime).localeCompare(lower(b.mime)); return k !== 0 ? k : cmpName(a, b) })
  else list.sort(function (a, b) { return (b.added || b.modified || 0) - (a.added || a.modified || 0) })   // dateAdded
  return list
}

// Which stack view to use for "auto": fan up to fanMax entries, else grid.
function resolveView(viewAs, count, fanMax) {
  if (viewAs === "fan" || viewAs === "grid" || viewAs === "list") return viewAs
  return count <= fanMax ? "fan" : "grid"
}

// Insertion index for a dragged tile: `centres` are the main-axis centres of
// the remaining tiles of the same section (in order), `pointer` the pointer
// position. Returns 0..centres.length.
function insertionIndex(pointer, centres) {
  for (var i = 0; i < centres.length; i++) if (pointer < centres[i]) return i
  return centres.length
}

function moveId(list, id, toIndex) {
  var out = list.slice()
  var from = out.indexOf(id)
  if (from >= 0) out.splice(from, 1)
  out.splice(Math.max(0, Math.min(out.length, toIndex)), 0, id)
  return out
}

function badgeText(b) {
  if (b === null || b === undefined || b === "" || b === 0) return ""
  if (typeof b === "number") return b > 99 ? "99+" : String(b)
  return String(b)
}
