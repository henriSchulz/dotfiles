.pragma library
// The Launchpad's layout: which item sits on which page, folders, hidden apps,
// per-app overrides and settings. One JSON document, written to
// ~/.config/omarchy/launchpad/layout.json (schema: ~/Projects/launchpad/replica/schema.json).
//
// Every function is pure: it takes a layout and returns a NEW one (QML only
// notices a var property change when a new object is assigned). Item ids are
// "app:<desktop id>" and "folder:<id>". An item lives in exactly one place:
// one page slot, one folder, or the hidden list. normalize() restores that
// after every change, so a broken file or a bug cannot duplicate an icon.

var VERSION = 1

var DEFAULT_SETTINGS = {
  columns: 7, rows: 5, iconSize: 88, showTitles: true, searchPosition: "top",
  folderGrid: [4, 4],
  categoriesPage: false,
  wallpaper: { kind: "desktop", path: null, blur: 40, dim: 0.25 },
  newApps: "end"
}

var LIMITS = { columns: [4, 12], rows: [3, 8], iconSize: [64, 128] }

function clone(o) { return JSON.parse(JSON.stringify(o)) }

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

function isApp(id) { return typeof id === "string" && id.indexOf("app:") === 0 && id.length > 4 }
function isFolder(id) { return typeof id === "string" && id.indexOf("folder:") === 0 && id.length > 7 }
function isDir(id) { return typeof id === "string" && id.indexOf("dir:") === 0 && id.length > 4 }
function dirKey(id) { return id.slice(4) }
function folderKey(id) { return id.slice(7) }
function appId(desktopId) { return "app:" + desktopId }

function perPage(l) { return l.settings.columns * l.settings.rows }

function empty() {
  return { version: VERSION, settings: clone(DEFAULT_SETTINGS), pages: [[]], folders: {}, dirs: {}, apps: {}, hidden: [], seen: [] }
}

function mergeSettings(raw) {
  var s = clone(DEFAULT_SETTINGS)
  if (!raw || typeof raw !== "object") return s
  if (typeof raw.columns === "number") s.columns = clamp(Math.round(raw.columns), LIMITS.columns[0], LIMITS.columns[1])
  if (typeof raw.rows === "number") s.rows = clamp(Math.round(raw.rows), LIMITS.rows[0], LIMITS.rows[1])
  if (typeof raw.iconSize === "number") s.iconSize = clamp(Math.round(raw.iconSize), LIMITS.iconSize[0], LIMITS.iconSize[1])
  if (typeof raw.showTitles === "boolean") s.showTitles = raw.showTitles
  if (raw.searchPosition === "top" || raw.searchPosition === "center") s.searchPosition = raw.searchPosition
  if (Array.isArray(raw.folderGrid) && raw.folderGrid.length === 2)
    s.folderGrid = [clamp(Math.round(raw.folderGrid[0]) || 4, 3, 5), clamp(Math.round(raw.folderGrid[1]) || 4, 3, 8)]
  if (raw.wallpaper && typeof raw.wallpaper === "object") {
    var w = raw.wallpaper
    if (w.kind === "desktop" || w.kind === "image" || w.kind === "solid") s.wallpaper.kind = w.kind
    if (typeof w.path === "string" || w.path === null) s.wallpaper.path = w.path
    if (typeof w.blur === "number") s.wallpaper.blur = clamp(Math.round(w.blur), 0, 100)
    if (typeof w.dim === "number") s.wallpaper.dim = clamp(w.dim, 0, 1)
  }
  if (raw.newApps === "end" || raw.newApps === "first-free") s.newApps = raw.newApps
  if (typeof raw.categoriesPage === "boolean") s.categoriesPage = raw.categoriesPage
  return s
}

// --------------------------------------------------------------- invariants

// One place per id; folders exist, are referenced once and hold apps only;
// pages are not over-full and not empty (one empty page stays when there is
// nothing at all).
function normalize(input) {
  var l = clone(input)
  var taken = {}
  var folders = {}
  var dirs = {}
  var srcDirs = l.dirs && typeof l.dirs === "object" ? l.dirs : {}
  var pages = []
  var hidden = []

  for (var p = 0; p < l.pages.length; p++) {
    var page = []
    var src = Array.isArray(l.pages[p]) ? l.pages[p] : []
    for (var i = 0; i < src.length; i++) {
      var id = src[i]
      if (taken[id]) continue
      if (isApp(id)) { taken[id] = true; page.push(id); continue }
      if (isDir(id)) {
        var dd = srcDirs[dirKey(id)]
        if (!dd || typeof dd.path !== "string" || dd.path.charAt(0) !== "/") continue
        taken[id] = true
        dirs[dirKey(id)] = { path: dd.path, name: typeof dd.name === "string" && dd.name ? dd.name.slice(0, 64) : baseName(dd.path) }
        page.push(id)
        continue
      }
      if (isFolder(id)) {
        var f = l.folders[folderKey(id)]
        if (!f || !Array.isArray(f.items)) continue
        var items = []
        for (var k = 0; k < f.items.length; k++) {
          var a = f.items[k]
          if (isApp(a) && !taken[a]) { taken[a] = true; items.push(a) }
        }
        if (items.length === 0) continue
        taken[id] = true
        folders[folderKey(id)] = {
          name: typeof f.name === "string" && f.name.length > 0 ? f.name.slice(0, 64) : "Folder",
          color: f.color || null, emoji: f.emoji || null, cover: f.cover || null,
          items: items
        }
        page.push(id)
      }
    }
    pages.push(page)
  }

  // Hidden apps lose to a visible placement: an app that is both shown and
  // hidden (a hand edit) stays shown.
  for (var h = 0; h < l.hidden.length; h++) {
    var hid = l.hidden[h]
    if (isApp(hid) && !taken[hid]) { taken[hid] = true; hidden.push(hid) }
  }

  l.pages = reflow(pages, perPage(l))
  l.folders = folders
  l.dirs = dirs
  l.hidden = hidden
  return l
}

// Overflow moves forward page by page; empty pages go, but at least one stays.
function reflow(pages, size) {
  var out = []
  var carry = []
  for (var p = 0; p < pages.length; p++) {
    var page = carry.concat(pages[p])
    carry = page.length > size ? page.slice(size) : []
    page = page.slice(0, size)
    if (page.length > 0) out.push(page)
  }
  while (carry.length > 0) { out.push(carry.slice(0, size)); carry = carry.slice(size) }
  if (out.length === 0) out.push([])
  return out
}

// ---------------------------------------------------------------- load/save

// text: the file's content or "" when there is none. desktopIds: the
// installed applications' desktop ids, in display order (by name).
// Returns { layout, error, backup }: error = the file could not be read
// (then the caller must not write it back); backup = the file had another
// version and should be kept beside the new one.
function load(text, desktopIds) {
  var raw = null
  var error = ""
  var backup = false
  if (text && String(text).trim().length > 0) {
    try { raw = JSON.parse(text) } catch (e) { error = "layout.json is not valid JSON: " + e.message }
  }
  var l = empty()
  if (raw && typeof raw === "object" && !Array.isArray(raw)) {
    if (raw.version === VERSION) {
      l.settings = mergeSettings(raw.settings)
      l.pages = Array.isArray(raw.pages) ? raw.pages.filter(Array.isArray) : [[]]
      l.folders = raw.folders && typeof raw.folders === "object" ? raw.folders : {}
      l.dirs = raw.dirs && typeof raw.dirs === "object" ? raw.dirs : {}
      l.apps = raw.apps && typeof raw.apps === "object" ? cleanOverrides(raw.apps) : {}
      l.hidden = Array.isArray(raw.hidden) ? raw.hidden : []
      l.seen = Array.isArray(raw.seen) ? raw.seen.filter(isApp) : []
    } else {
      backup = true
    }
  } else if (raw !== null) {
    error = "layout.json does not hold a layout object"
  }
  l = normalize(l)
  l = sync(l, desktopIds)
  return { layout: l, error: error, backup: backup }
}

function cleanOverrides(apps) {
  var out = {}
  for (var id in apps) {
    if (!isApp(id) || !apps[id] || typeof apps[id] !== "object") continue
    var o = apps[id]
    var c = {}
    if (typeof o.name === "string" && o.name.length > 0) c.name = o.name.slice(0, 64)
    if (typeof o.icon === "string" && o.icon.length > 0) c.icon = o.icon
    if (o.hideTitle === true) c.hideTitle = true
    if (Object.keys(c).length > 0) out[id] = c
  }
  return out
}

function serialize(l) { return JSON.stringify(l, null, 2) + "\n" }

// Installed apps changed: unseen ones are placed (at the end, in the order
// given), ones that are gone leave the grid. "seen" keeps every id ever
// placed, so an app that comes back after a reinstall is placed again
// exactly once, and an app the user hid stays hidden.
function sync(input, desktopIds) {
  var l = clone(input)
  var installed = {}
  for (var i = 0; i < desktopIds.length; i++) installed[appId(desktopIds[i])] = true

  var keep = function(id) { return !isApp(id) || installed[id] === true }
  for (var p = 0; p < l.pages.length; p++) l.pages[p] = l.pages[p].filter(keep)
  for (var key in l.folders) l.folders[key].items = l.folders[key].items.filter(keep)
  l.hidden = l.hidden.filter(keep)

  var placed = {}
  each(l, function(id) { placed[id] = true })
  var seen = {}
  for (var s = 0; s < l.seen.length; s++) seen[l.seen[s]] = true

  var fresh = []
  for (var d = 0; d < desktopIds.length; d++) {
    var id = appId(desktopIds[d])
    if (placed[id]) { seen[id] = true; continue }
    fresh.push(id)
    seen[id] = true
  }
  if (fresh.length > 0) l = placeNew(l, fresh)
  l.seen = Object.keys(seen).sort()
  return normalize(l)
}

function placeNew(l, ids) {
  var size = perPage(l)
  if (l.settings.newApps === "first-free") {
    for (var p = 0; p < l.pages.length && ids.length > 0; p++)
      while (l.pages[p].length < size && ids.length > 0) l.pages[p].push(ids.shift())
  }
  var last = l.pages[l.pages.length - 1]
  for (var i = 0; i < ids.length; i++) last.push(ids[i])
  return l
}

// Calls fn(id) for every placed id: page items, folder items, hidden.
function each(l, fn) {
  for (var p = 0; p < l.pages.length; p++)
    for (var i = 0; i < l.pages[p].length; i++) {
      var id = l.pages[p][i]
      fn(id)
      if (isFolder(id) && l.folders[folderKey(id)]) {
        var items = l.folders[folderKey(id)].items
        for (var k = 0; k < items.length; k++) fn(items[k])
      }
    }
  for (var h = 0; h < l.hidden.length; h++) fn(l.hidden[h])
}

// -------------------------------------------------------------------- where

function locate(l, id) {
  for (var p = 0; p < l.pages.length; p++) {
    var i = l.pages[p].indexOf(id)
    if (i >= 0) return { where: "page", page: p, index: i }
  }
  for (var key in l.folders) {
    var k = l.folders[key].items.indexOf(id)
    if (k >= 0) return { where: "folder", folder: "folder:" + key, index: k }
  }
  var h = l.hidden.indexOf(id)
  if (h >= 0) return { where: "hidden", index: h }
  return null
}

function folderOf(l, id) {
  var at = locate(l, id)
  return at && at.where === "folder" ? at.folder : ""
}

// Takes an id out of wherever it is; does not clean up (normalize does).
function detach(l, id) {
  for (var p = 0; p < l.pages.length; p++) l.pages[p] = l.pages[p].filter(function(x) { return x !== id })
  for (var key in l.folders) l.folders[key].items = l.folders[key].items.filter(function(x) { return x !== id })
  l.hidden = l.hidden.filter(function(x) { return x !== id })
}

// ------------------------------------------------------------------ changes

// Puts id at (toPage, toIndex) as its final position. toPage == pages.length
// opens a new page. Works for page items and for apps leaving a folder; a
// folder emptied this way is removed.
function move(input, id, toPage, toIndex) {
  var l = clone(input)
  if (!isApp(id) && !isFolder(id) && !isDir(id)) return l
  if (isFolder(id) && !l.folders[folderKey(id)]) return l
  detach(l, id)
  toPage = clamp(Math.floor(toPage), 0, l.pages.length)
  if (toPage === l.pages.length) l.pages.push([])
  var page = l.pages[toPage]
  page.splice(clamp(Math.floor(toIndex), 0, page.length), 0, id)
  return normalize(l)
}

// Dragged item dropped onto another: app on app makes a folder in the
// target's slot (named `name`), app on folder joins it. Folders do not nest,
// so a folder dropped on anything is a no-op. Returns the layout; the new
// folder's id is in result.lastFolder.
function dropOnto(input, dragId, targetId, name) {
  var l = clone(input)
  if (!isApp(dragId) || dragId === targetId) return l
  var target = locate(l, targetId)
  if (!target) return l
  if (isFolder(targetId)) {
    if (!l.folders[folderKey(targetId)]) return l
    detach(l, dragId)
    l.folders[folderKey(targetId)].items.push(dragId)
    l = normalize(l)
    l.lastFolder = targetId
    return l
  }
  if (!isApp(targetId) || target.where !== "page") return l
  var key = newFolderKey(l)
  detach(l, dragId)
  var at = locate(l, targetId)
  l.pages[at.page][at.index] = "folder:" + key
  l.folders[key] = { name: name && String(name).length > 0 ? String(name).slice(0, 64) : "Folder", color: null, emoji: null, cover: null, items: [targetId, dragId] }
  l = normalize(l)
  l.lastFolder = "folder:" + key
  return l
}

// Several apps into a new folder at the position of the first one.
function groupInto(input, ids, name) {
  var l = clone(input)
  var apps = ids.filter(isApp)
  if (apps.length < 2) return l
  var first = locate(l, apps[0])
  if (!first || first.where !== "page") return l
  var key = newFolderKey(l)
  l.pages[first.page][first.index] = "folder:" + key
  for (var i = 1; i < apps.length; i++) detach(l, apps[i])
  l.folders[key] = { name: name || "Folder", color: null, emoji: null, cover: null, items: apps }
  l = normalize(l)
  l.lastFolder = "folder:" + key
  return l
}

function newFolderKey(l) {
  var n = 1
  while (l.folders["f" + n]) n++
  return "f" + n
}

function baseName(path) {
  var p = String(path || "").replace(/\/+$/, "")
  return p.slice(p.lastIndexOf("/") + 1) || p
}

// A folder tile (Downloads, Documents …) at the end of the last page; one per path.
function addDir(input, path, name) {
  var l = clone(input)
  var p = String(path || "").replace(/\/+$/, "") || "/"
  if (p.charAt(0) !== "/") return l
  for (var k in l.dirs) if (l.dirs[k].path === p) { l.lastDir = "dir:" + k; return l }
  var n = 1
  while (l.dirs["d" + n]) n++
  l.dirs["d" + n] = { path: p, name: name ? String(name).slice(0, 64) : baseName(p) }
  l.pages[l.pages.length - 1].push("dir:d" + n)
  l = normalize(l)
  l.lastDir = "dir:d" + n
  return l
}

function removeDir(input, id) {
  var l = clone(input)
  if (!isDir(id)) return l
  detach(l, id)
  delete l.dirs[dirKey(id)]
  return normalize(l)
}

// Reorders an app inside its folder.
function moveInFolder(input, folderId, id, toIndex) {
  var l = clone(input)
  var f = l.folders[folderKey(folderId)]
  if (!f || f.items.indexOf(id) < 0) return l
  f.items = f.items.filter(function(x) { return x !== id })
  f.items.splice(clamp(Math.floor(toIndex), 0, f.items.length), 0, id)
  return l
}

// The folder's apps take its slot, in order.
function ungroup(input, folderId) {
  var l = clone(input)
  var f = l.folders[folderKey(folderId)]
  var at = locate(l, folderId)
  if (!f || !at || at.where !== "page") return l
  var page = l.pages[at.page]
  Array.prototype.splice.apply(page, [at.index, 1].concat(f.items))
  delete l.folders[folderKey(folderId)]
  return normalize(l)
}

function styleFolder(input, folderId, patch) {
  var l = clone(input)
  var f = l.folders[folderKey(folderId)]
  if (!f) return l
  if (typeof patch.name === "string") {
    var n = patch.name.trim()
    f.name = n.length > 0 ? n.slice(0, 64) : f.name
  }
  if ("color" in patch) f.color = /^#[0-9a-fA-F]{6}$/.test(String(patch.color)) ? patch.color : null
  if ("emoji" in patch) f.emoji = patch.emoji ? String(patch.emoji).slice(0, 8) : null
  return l
}

function hide(input, id) {
  var l = clone(input)
  if (!isApp(id) || !locate(l, id)) return l
  detach(l, id)
  l.hidden.push(id)
  return normalize(l)
}

function unhide(input, id) {
  var l = clone(input)
  if (l.hidden.indexOf(id) < 0) return l
  detach(l, id)
  l.pages[l.pages.length - 1].push(id)
  return normalize(l)
}

function setOverride(input, id, patch) {
  var l = clone(input)
  if (!isApp(id)) return l
  var o = Object.assign({}, l.apps[id] || {}, patch)
  var c = cleanOverrides({ [id]: o })
  if (c[id]) l.apps[id] = c[id]
  else delete l.apps[id]
  return l
}

function setSettings(input, patch) {
  var l = clone(input)
  var merged = Object.assign({}, l.settings, patch)
  if (patch.wallpaper) merged.wallpaper = Object.assign({}, l.settings.wallpaper, patch.wallpaper)
  l.settings = mergeSettings(merged)
  return normalize(l)
}

// Fresh alphabetical layout, keeping settings, hidden apps and overrides.
function reset(input, desktopIds) {
  var l = empty()
  l.settings = clone(input.settings)
  l.apps = clone(input.apps)
  l.hidden = clone(input.hidden)
  l = sync(normalize(l), desktopIds)
  // folder tiles stay, at the end
  l.dirs = clone(input.dirs || {})
  for (var k in l.dirs) l.pages[l.pages.length - 1].push("dir:" + k)
  return normalize(l)
}
