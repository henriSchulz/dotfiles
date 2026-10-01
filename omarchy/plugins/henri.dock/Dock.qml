// henri.dock — the macOS Dock for the Omarchy shell (Quickshell / Hyprland).
//
// Spec: docs/dock-spec.md (Aufbau, Verhalten, Animationen). Look from apple-ui
// (Apple.dock, dock palettes), motion from henri-ui (Motion.dock springs and
// durations, HUi components). Two layer surfaces on the dock's screen:
//
//   bgWindow   — the glass background only (blurred by a Hyprland layer_rule on
//                namespace "henri-dock"); as thin as the dock, click-through.
//   overlay    — full-screen, unblurred, input-masked to the dock zone and
//                open popups: tiles (they grow above the background), hover
//                label, context menus, stacks, settings, the genie/scale
//                minimize animation and the drag ghost.
//
// Hyprland has no minimize: a window is parked on the special workspace
// "special:minimized" (same convention as omadock and henri.app-switcher) and
// its tile shows a snapshot taken right before the move.
//
// Keys arrive as Hyprland custom events (bindings.lua → hl.dsp.event("dock …"))
// and as IPC (`omarchy-shell dock <fn>`).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi
import "file:///home/henri/.local/share/apple-ui/Apple.js" as Apple
import "file:///home/henri/.local/share/apple-ui" as AUi
import "DockModel.js" as DockModel
import "components"

Item {
  id: root

  property var shell: null
  property var manifest: null
  // Test rigs on a headless output: HyprlandFocusGrab clears at once there, so
  // Reveal would close every popup on open. Set via IPC probeNoGrab.
  property bool testNoGrab: false
  readonly property string home: Quickshell.env("HOME")
  readonly property string minimizedWorkspace: "special:minimized"

  // ======================================================== settings (§19)
  readonly property var defaults: ({
    tileSize: Apple.dock.tileSize,
    magnification: true,
    magnifiedSize: Apple.dock.magnifiedSize,
    magnificationRadius: Apple.dock.magnificationRadius,
    position: "bottom",
    minimizeEffect: "genie",
    minimizeToAppIcon: false,
    animateOpeningApps: true,
    autoHide: false,
    autoHideDelay: Motion.dock.autoHideDelay,
    autoHideDuration: Motion.dock.autoHideDuration,
    showIndicators: true,
    showRecentApps: true,
    theme: "system",
    accentColor: Apple.dock.accent,
    reduceMotion: "system",
    fileManager: "de.henri.Finder",
    screen: "",
    folders: [{ path: "~/Downloads", name: "Downloads", displayAs: "stack", viewContentAs: "auto", sortBy: "dateAdded" }],
    files: [],
    loginApps: [],
    // app key (lower-case desktop id) → icon name or absolute path, e.g. a MacTahoe SVG
    iconOverrides: {},
    // Only apps with a visible desktop entry get a tile (pinned ones always). Windows of
    // helpers without an entry or with NoDisplay (portal dialogs, agents, nested
    // compositors) stay out; they remain reachable via the app switcher.
    showUnknownApps: false,
    // window classes that never appear in the dock (portal dialogs and other helpers)
    ignoredApps: ["xdg-desktop-portal-gtk", "xdg-desktop-portal-gnome", "xdg-desktop-portal-kde", "xdg-desktop-portal-hyprland", "polkit-gnome-authentication-agent-1"]
  })
  property var settings: defaults
  property bool settingsLoaded: false

  function setSetting(key, value) {
    var next = DockModel.copyMap(settings)
    next[key] = value
    if (key === "tileSize") next.magnifiedSize = Math.max(next.magnifiedSize, value)
    if (key === "magnifiedSize") next.magnifiedSize = Math.max(next.tileSize, value)
    settings = next
    saveTimer.restart()
  }
  Timer {
    id: saveTimer
    interval: 300
    onTriggered: settingsFile.setText(JSON.stringify(root.settings, null, 2) + "\n")
  }
  FileView {
    id: settingsFile
    path: root.home + "/.config/omarchy/henri.dock.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: { root.settings = DockModel.mergeSettings(root.defaults, text()); root.settingsLoaded = true }
    onFileChanged: reload()
  }

  readonly property bool autoHide: settings.autoHide === true
  readonly property bool magnificationOn: settings.magnification === true
  readonly property bool showIndicators: settings.showIndicators !== false
  readonly property bool animateOpeningApps: settings.animateOpeningApps !== false
  // System Settings › Reduce motion always wins (Motion.reduceMotion); the
  // dock's own "Reduced" can only add to it. A stored "off" (the old "Full"
  // override) now means "system", because the shared tokens are reduced anyway.
  readonly property bool reduceMotion: settings.reduceMotion === "on" || settings.reduceMotion === true
      || Motion.reduceMotion
  readonly property color accent: settings.accentColor || Apple.dock.accent

  // ======================================================== pinned apps (~/.config/omarchy/dock.json)
  property var pinnedIds: []
  FileView {
    id: pinnedFile
    path: root.home + "/.config/omarchy/dock.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: { root.pinnedIds = DockModel.parsePinned(text()); root.scheduleRebuild() }
    onFileChanged: reload()
  }
  function savePinned(ids) {
    var out = []
    var fm = DockModel.stripDesktop(settings.fileManager)
    if (fm) out.push(fm)
    for (var i = 0; i < ids.length; i++) if (out.indexOf(ids[i]) < 0) out.push(ids[i])
    pinnedIds = out
    pinnedFile.setText(DockModel.serializePinned(out))
    scheduleRebuild()
  }

  // ======================================================== screen, material, palette
  readonly property var screen: {
    var list = Quickshell.screens
    var want = String(settings.screen || "")
    for (var i = 0; i < list.length; i++) if (want && list[i].name === want) return list[i]
    for (var j = 0; j < list.length; j++) if (String(list[j].name).indexOf("HEADLESS") !== 0) return list[j]
    return list.length > 0 ? list[0] : null
  }
  AUi.Backdrop {
    id: backdrop
    gravity: root.position === "bottom" ? "South" : root.position === "left" ? "West" : "East"
    region: root.position === "bottom" ? "70%x15%+0+0" : "15%x70%+0+0"
  }
  readonly property bool dark: settings.theme === "dark" ? true : settings.theme === "light" ? false : backdrop.dark
  readonly property var palette: Apple.dockPalette(dark)

  // ======================================================== geometry / axis abstraction (§15)
  // Everything is computed along the main axis (m) and the cross axis (c,
  // distance from the screen edge) and mapped to x/y once, in rectFor().
  property string position: "bottom"
  readonly property bool horizontal: position === "bottom"
  readonly property real planeWidth: plane.width
  readonly property real planeHeight: plane.height
  readonly property real mainLength: horizontal ? planeWidth : planeHeight
  readonly property real edgeGap: Style.space(Apple.dock.edgeGap)
  readonly property real padCross: Style.space(Apple.dock.padCross)
  readonly property real padMain: Style.space(Apple.dock.padMain)
  readonly property real separatorWidth: 1 + Style.space(Apple.dock.separatorPad) * 2
  readonly property real dockBaseline: edgeGap + padCross
  readonly property int tileSize: DockModel.fittingTileSize(entryList, Number(settings.tileSize) || Apple.dock.tileSize,
      mainLength - Style.space(16), Apple.dock.gapFraction, Style.space(Apple.dock.gapMin), padMain,
      Style.space(Apple.dock.separatorPad), Apple.dock.tileMin)
  readonly property int magnifiedSize: Math.max(tileSize, Number(settings.magnifiedSize) || Apple.dock.magnifiedSize)
  readonly property real gap: DockModel.gapFor(tileSize, Apple.dock.gapFraction, Style.space(Apple.dock.gapMin))
  readonly property real bgThickness: edgeGap + padCross * 2 + tileSize
  readonly property real cornerRadius: DockModel.cornerRadius(tileSize, Apple.dock.radiusFactor, Style.space(Apple.dock.radiusMin), Style.space(Apple.dock.radiusMax))
  readonly property real indicatorSize: DockModel.indicatorSize(tileSize, Style.space(Apple.dock.indicator), Style.space(Apple.dock.indicatorMin), Style.space(Apple.dock.indicatorMax))
  readonly property real iconBase: 128
  readonly property var insideWindows: [bgWindow]

  function rectFor(m, c, mainSize, crossSize, W, H) {
    var w = W === undefined ? planeWidth : W
    var h = H === undefined ? planeHeight : H
    if (position === "bottom") return { x: m - mainSize / 2, y: h - c - crossSize, w: mainSize, h: crossSize }
    if (position === "left") return { x: c, y: m - mainSize / 2, w: crossSize, h: mainSize }
    return { x: w - c - crossSize, y: m - mainSize / 2, w: crossSize, h: mainSize }
  }
  function hopX(h) { return position === "left" ? h : position === "right" ? -h : 0 }
  function hopY(h) { return position === "bottom" ? -h : 0 }
  // Pointer (plane coordinates) → main / cross
  function mainOf(x, y) { return horizontal ? x : y }
  function crossOf(x, y) { return position === "bottom" ? planeHeight - y : position === "left" ? x : planeWidth - x }
  // Window rect (plane coordinates) → dock frame for the minimize effect
  function uvOf(x, y, w, h) {
    if (position === "bottom") return { u0: x, u1: x + w, vNear: planeHeight - (y + h), vFar: planeHeight - y }
    if (position === "left") return { u0: y, u1: y + h, vNear: x, vFar: x + w }
    return { u0: y, u1: y + h, vNear: planeWidth - (x + w), vFar: planeWidth - x }
  }
  // Current icon body of a tile in the dock frame (target of the genie).
  function tileUV(itemId) {
    var t = tileFor(itemId)
    if (!t) {
      var trash = tileFor("trash")
      var m = trash ? trash.main - (tileSize + gap) : mainLength / 2
      var ins = tileSize * (1 - Apple.dock.iconBody) / 2
      return { u0: m - tileSize / 2 + ins, u1: m + tileSize / 2 - ins, vNear: dockBaseline + ins, vFar: dockBaseline + tileSize - ins }
    }
    var s = Math.max(4, t.visSize)
    var inset = s * (1 - Apple.dock.iconBody) / 2
    return { u0: t.main - s / 2 + inset, u1: t.main + s / 2 - inset, vNear: dockBaseline + inset, vFar: dockBaseline + s - inset }
  }

  // ======================================================== model
  // items: id → data; the ListModel only carries ids in dock order, so tiles
  // keep their identity (and their springs) across every rebuild.
  property var items: ({})
  property var entryList: []
  property bool ready: false
  property var runningOrder: []           // unpinned running app keys, first seen first
  property var recents: []                // { key, entryId } most recent first
  property var launchPending: ({})        // key → started (ms)
  property var attentionMap: ({})         // key → true
  property var attentionRepeatsMap: ({})  // key → repeats
  property var badges: ({})               // item id or key → badge
  property var mru: ({})                  // address → counter
  property int mruCounter: 0
  property var minimizedRects: ({})       // address → uv rect at minimize time
  property var snapshots: ({})            // address → ScreencopyView in the vault
  property int trashCount: 0
  property var folderWatchers: ({})       // path → FolderWatcher

  ListModel { id: tiles }

  Timer { id: rebuildTimer; interval: 40; onTriggered: root.rebuild() }
  function scheduleRebuild() { rebuildTimer.restart() }

  function lookupEntry(id) {
    if (!id || typeof DesktopEntries === "undefined") return null
    var s = DockModel.stripDesktop(id)
    try {
      return DesktopEntries.byId(s) || DesktopEntries.heuristicLookup(s) || DesktopEntries.heuristicLookup(DockModel.shortId(s)) || null
    } catch (e) { return null }
  }
  function keyFor(entry, appId) {
    return entry && entry.id ? DockModel.lower(DockModel.stripDesktop(entry.id)) : DockModel.lower(DockModel.stripDesktop(appId))
  }
  function iconFor(names) {
    var list = Array.isArray(names) ? names : [names]
    for (var i = 0; i < list.length; i++) {
      var n = String(list[i] || "")
      if (!n) continue
      if (n.indexOf("file://") === 0 || n.indexOf("image://") === 0) return n
      if (n.charAt(0) === "/") return "file://" + n
      var p = ""
      try { p = Quickshell.iconPath(n, true) } catch (e) {}
      if (p) return p
    }
    var fb = ""
    try { fb = Quickshell.iconPath("application-x-executable", true) } catch (e2) {}
    return fb
  }
  function appIcon(entry, appId) {
    var tries = []
    if (entry && entry.icon) tries.push(entry.icon)
    var id = String(appId || "")
    if (id) { tries.push(id); tries.push(id.toLowerCase()); tries.push(DockModel.shortId(id).toLowerCase()) }
    return iconFor(tries)
  }
  function isIgnoredApp(appId, key) {
    var list = Array.isArray(settings.ignoredApps) ? settings.ignoredApps : []
    var a = DockModel.lower(appId)
    for (var i = 0; i < list.length; i++) { var x = DockModel.lower(list[i]); if (x === a || x === key) return true }
    return false
  }
  function iconOverride(key) {
    var o = settings.iconOverrides
    if (!o || typeof o !== "object") return ""
    var v = o[key] || o[DockModel.shortId(key)]
    return v ? iconFor([DockModel.expandHome(String(v), home)]) : ""
  }
  function folderIcon(path) {
    var b = DockModel.baseName(path).toLowerCase()
    var special = { downloads: "folder-download", documents: "folder-documents", pictures: "folder-pictures", music: "folder-music", videos: "folder-videos", desktop: "user-desktop", projects: "folder-development" }
    return iconFor([special[b] || "folder", "folder"])
  }
  function badgeText(b) { return DockModel.badgeText(b) }
  function accessibleName(item) {
    if (!item) return ""
    var s = String(item.name || "")
    if (item.kind === "app") {
      if (item.running) s += ", running"
      var b = badgeText(item.badge)
      if (b) s += ", " + b + " notifications"
    }
    return s
  }

  function windowsOf(list) { return list }

  function rebuild() {
    var old = items
    var map = {}
    var order = []
    var fmId = DockModel.stripDesktop(settings.fileManager)
    var fmEntry = lookupEntry(fmId)
    var fmKey = keyFor(fmEntry, fmId)

    var pinnedKeySet = {}
    pinnedKeySet[fmKey] = true
    for (var pp = 0; pp < pinnedIds.length; pp++) pinnedKeySet[keyFor(lookupEntry(pinnedIds[pp]), pinnedIds[pp])] = true

    // -- running windows grouped by app
    var groups = {}
    var tls = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var runningKeys = []
    for (var i = 0; i < tls.length; i++) {
      var t = tls[i]
      if (!t) continue
      var wl = t.wayland
      var ipc = t.lastIpcObject || {}
      var appId = String((wl && wl.appId) || ipc["class"] || ipc.initialClass || "").trim()
      if (!appId) continue
      var entry = lookupEntry(appId)
      var key = keyFor(entry, appId)
      if (isIgnoredApp(appId, key)) continue
      if (settings.showUnknownApps !== true && (!entry || entry.noDisplay) && !pinnedKeySet[key]) continue
      var ws = t.workspace
      var wsName = ws ? String(ws.name || "") : String(ipc.workspace && ipc.workspace.name || "")
      var g = groups[key]
      if (!g) {
        g = { key: key, appId: appId, entry: entry, windows: [] }
        groups[key] = g
        runningKeys.push(key)
      }
      g.windows.push({
        address: DockModel.normalizeAddress(t.address), title: String(t.title || (wl && wl.title) || ""),
        hypr: t, wayland: wl, minimized: wsName === minimizedWorkspace,
        activated: !!t.activated, rank: mru[DockModel.normalizeAddress(t.address)] || 0
      })
    }
    // launch feedback ends once a window of that app exists
    var lp = DockModel.copyMap(launchPending)
    var lpChanged = false
    for (var k in lp) if (groups[k]) { delete lp[k]; lpChanged = true }
    if (lpChanged) launchPending = lp

    // first-seen order for unpinned running apps; recents collect the ones that quit
    var ro = runningOrder.slice()
    for (var r = ro.length - 1; r >= 0; r--) {
      if (!groups[ro[r]]) {
        var goneKey = ro[r]
        ro.splice(r, 1)
        // helpers with NoDisplay desktop entries (portal dialogs …) never become recents
        var goneItem = old["app:" + goneKey]
        if (goneItem && !goneItem.pinned && !(goneItem.entry && goneItem.entry.noDisplay)) {
          var rec = recents.filter(function (x) { return x.key !== goneKey })
          rec.unshift({ key: goneKey, entryId: old["app:" + goneKey].entryId || "", appId: old["app:" + goneKey].appId || "" })
          recents = rec.slice(0, 3)
        }
      }
    }
    var pinnedKeys = {}
    var pinnedList = []
    for (var p = 0; p < pinnedIds.length; p++) {
      var pid = DockModel.stripDesktop(pinnedIds[p])
      var pe = lookupEntry(pid)
      var pk = keyFor(pe, pid)
      if (pk === fmKey || pinnedKeys[pk]) continue
      pinnedKeys[pk] = true
      pinnedList.push({ key: pk, entry: pe, id: pid })
    }
    for (var q = 0; q < runningKeys.length; q++)
      if (!pinnedKeys[runningKeys[q]] && runningKeys[q] !== fmKey && ro.indexOf(runningKeys[q]) < 0) ro.push(runningKeys[q])
    runningOrder = ro

    function appItem(key, entry, appId, pinned, recent) {
      var g = groups[key]
      var wins = g ? g.windows.slice() : []
      wins.sort(function (a, b) { return b.rank - a.rank })
      var name = entry && entry.name ? String(entry.name) : DockModel.fallbackName(appId || key)
      var id = "app:" + key
      var prev = old[id]
      return {
        id: id, kind: "app", key: key, entryId: entry ? DockModel.stripDesktop(entry.id) : (appId || key), appId: appId || (g ? g.appId : key),
        entry: entry, name: name, icon: iconOverride(key) || appIcon(entry, appId || (g ? g.appId : key)),
        pinned: pinned, recent: recent === true, running: !!g, windows: wins,
        launching: !!launchPending[key], attention: !!attentionMap[key],
        badge: badges[id] !== undefined ? badges[id] : badges[key],
        locked: key === fmKey, gone: false, snapshot: null
      }
    }

    // -- app area
    var fm = appItem(fmKey, fmEntry, fmId, true, false)
    map[fm.id] = fm; order.push(fm.id)
    for (var a = 0; a < pinnedList.length; a++) {
      var it = appItem(pinnedList[a].key, pinnedList[a].entry, pinnedList[a].id, true, false)
      map[it.id] = it; order.push(it.id)
    }
    for (var b = 0; b < ro.length; b++) {
      var gk = ro[b]
      if (!groups[gk] || pinnedKeys[gk]) continue
      var ri = appItem(gk, groups[gk].entry, groups[gk].appId, false, false)
      map[ri.id] = ri; order.push(ri.id)
    }
    map["sep:apps"] = { id: "sep:apps", kind: "separator", name: "", gone: false }
    order.push("sep:apps")

    // -- recents (§3.1, optional)
    if (settings.showRecentApps !== false) {
      var shown = 0
      for (var c = 0; c < recents.length && shown < 3; c++) {
        var rk = recents[c].key
        if (groups[rk] || pinnedKeys[rk] || rk === fmKey) continue
        var re = lookupEntry(recents[c].entryId || recents[c].appId || rk)
        var rit = appItem(rk, re, recents[c].appId || recents[c].entryId || rk, false, true)
        map[rit.id] = rit; order.push(rit.id); shown++
      }
      if (shown > 0) { map["sep:recent"] = { id: "sep:recent", kind: "separator", name: "", gone: false }; order.push("sep:recent") }
    }

    // -- document area: folders, files, minimized windows, trash
    var folders = Array.isArray(settings.folders) ? settings.folders : []
    var watchers = DockModel.copyMap(folderWatchers)
    var wanted = {}
    for (var f = 0; f < folders.length; f++) {
      var fo = folders[f] || {}
      var path = DockModel.expandHome(fo.path, home)
      if (!path) continue
      wanted[path] = true
      if (!watchers[path]) watchers[path] = watcherComp.createObject(root, { path: path })
      var w = watchers[path]
      var entries = DockModel.sortEntries(w.entries || [], fo.sortBy || "dateAdded")
      var peek = []
      for (var pe2 = 0; pe2 < entries.length && pe2 < Apple.dock.stackPeek; pe2++) peek.push(iconFor(entries[pe2].icon))
      var fid = "folder:" + path
      map[fid] = { id: fid, kind: "folder", name: fo.name || DockModel.baseName(path), path: path, icon: folderIcon(path),
        displayAs: fo.displayAs || "stack", viewContentAs: fo.viewContentAs || "auto", sortBy: fo.sortBy || "dateAdded",
        entries: entries, peek: peek, gone: false, badge: null, snapshot: null }
      order.push(fid)
    }
    for (var wp in watchers) if (!wanted[wp]) { watchers[wp].destroy(); delete watchers[wp] }
    folderWatchers = watchers
    var files = Array.isArray(settings.files) ? settings.files : []
    for (var fl = 0; fl < files.length; fl++) {
      var fe = files[fl] || {}
      var fpath = DockModel.expandHome(fe.path, home)
      if (!fpath) continue
      var flid = "file:" + fpath
      map[flid] = { id: flid, kind: "file", name: fe.name || DockModel.baseName(fpath), path: fpath, icon: iconFor(fe.icon || ["text-x-generic"]), gone: false, badge: null, snapshot: null }
      order.push(flid)
    }
    if (settings.minimizeToAppIcon !== true) {
      var mins = []
      for (var mk in groups) {
        var gw = groups[mk].windows
        for (var mw = 0; mw < gw.length; mw++) if (gw[mw].minimized) mins.push({ win: gw[mw], group: groups[mk] })
      }
      mins.sort(function (a, b) { return (parkedAt[a.win.address] || 0) - (parkedAt[b.win.address] || 0) })
      for (var mi = 0; mi < mins.length; mi++) {
        var mwin = mins[mi].win, mg = mins[mi].group
        var mid = "win:" + mwin.address
        map[mid] = { id: mid, kind: "minimizedWindow", name: mwin.title || (mg.entry ? mg.entry.name : DockModel.fallbackName(mg.appId)),
          address: mwin.address, key: mg.key, window: mwin, appIcon: appIcon(mg.entry, mg.appId), icon: appIcon(mg.entry, mg.appId),
          snapshot: snapshots[mwin.address] || null, gone: false, badge: null }
        order.push(mid)
      }
    }
    map["trash"] = { id: "trash", kind: "trash", name: "Trash", full: trashCount > 0, icon: String(Qt.resolvedUrl(trashCount > 0 ? "assets/trash-full.png" : "assets/trash-empty.png")), locked: true, gone: false, badge: null, snapshot: null }
    order.push("trash")

    // -- keep exiting tiles until their spring has closed
    for (var oid in old) if (!map[oid] && tileRow(oid) >= 0) { var gone = DockModel.copyMap(old[oid]); gone.gone = true; map[oid] = gone }
    items = map
    syncModel(order)
    pruneSnapshots(groups)
    if (!ready) { ready = true }
    layoutDirty()
  }

  function tileRow(id) { for (var i = 0; i < tiles.count; i++) if (tiles.get(i).itemId === id) return i; return -1 }
  function tileFor(id) { var r = tileRow(id); return r >= 0 ? rep.itemAt(r) : null }

  function syncModel(order) {
    var pos = 0
    for (var i = 0; i < order.length; i++) {
      var id = order[i]
      while (pos < tiles.count) {
        var cur = tiles.get(pos).itemId
        var ci = items[cur]
        if (ci && ci.gone && order.indexOf(cur) < 0) pos++
        else break
      }
      var r = -1
      for (var j = pos; j < tiles.count; j++) if (tiles.get(j).itemId === id) { r = j; break }
      if (r < 0) tiles.insert(pos, { itemId: id, kind: items[id].kind })
      else if (r > pos) tiles.move(r, pos, 1)
      pos++
    }
    for (var k = pos; k < tiles.count; k++) {
      var tid = tiles.get(k).itemId
      if (items[tid] && !items[tid].gone) { var g = DockModel.copyMap(items[tid]); g.gone = true; var m = DockModel.copyMap(items); m[tid] = g; items = m }
    }
    var list = []
    for (var e = 0; e < tiles.count; e++) list.push({ id: tiles.get(e).itemId, kind: tiles.get(e).kind })
    entryList = list
  }
  function finalizeRemove(id) {
    var r = tileRow(id)
    if (r >= 0) tiles.remove(r, 1)
    var m = DockModel.copyMap(items); delete m[id]; items = m
    var list = []
    for (var e = 0; e < tiles.count; e++) list.push({ id: tiles.get(e).itemId, kind: tiles.get(e).kind })
    entryList = list
    layoutDirty()
  }

  // ======================================================== layout pass (§5, §22)
  // Runs once per frame while anything moves (pointer, springs, drag, hide),
  // otherwise only on demand. Magnification targets are computed against the
  // unmagnified layout so nothing feeds back on itself.
  property var centres: []
  property real bgStart: 0
  property real bgLength: 0
  property real maxVis: 48
  property real gapMain: 0
  property int activeSprings: 0
  property bool hovering: false
  property real pointerMain: 0
  property real pointerCross: 0
  property int hoverIndex: -1
  property bool hoverSeparator: false
  property bool invertMagnification: false
  readonly property bool layoutActive: hovering || dragging || landing || resizing || activeSprings > 0 || hideAnim.running || swapAnim.running || fx.running || kbMode || externalDrag
  readonly property bool magnifyNow: (magnificationOn !== invertMagnification) && (hovering || dragging || kbMode) && !resizing && !menuFrozen && !hiddenNow

  function springRunning(on) { activeSprings = Math.max(0, activeSprings + (on ? 1 : -1)) }
  function layoutDirty() { Qt.callLater(relayout) }
  FrameAnimation { running: root.layoutActive; onTriggered: root.relayout() }

  function relayout() {
    var n = tiles.count
    var g = gap
    var entries = []
    var list = []
    for (var i = 0; i < n; i++) {
      var t = rep.itemAt(i)
      list.push(t)
      entries.push(t ? { kind: t.kind, weight: t.isSeparator ? 1 : t.enter } : { kind: tiles.get(i).kind, weight: 1 })
    }
    var base = DockModel.baseLayout(entries, tileSize, g, padMain, separatorWidth)
    var baseStart = (mainLength - base.total) / 2
    var pm = kbMode && !hovering && kbIndex >= 0 && kbIndex < base.centres.length ? baseStart + base.centres[kbIndex] : pointerMain
    var pBase = pm - baseStart
    var frozen = menuFrozen
    var total = padMain
    var centresOut = []
    var maxV = tileSize
    var gm = -1
    var hi = -1, hsep = false, bestD = 1e9
    for (var j = 0; j < n; j++) {
      var tile = list[j]
      if (!tile) { centresOut.push(total); continue }
      if (!frozen && !tile.isSeparator)
        tile.targetSize = magnifyNow ? DockModel.magnifiedSize(Math.abs(pBase - base.centres[j]), tileSize, magnifiedSize, Number(settings.magnificationRadius) || 3) : tileSize
      // gaps opening for a dragged tile before row j
      var gapHere = gapWidthBefore(j)
      if (gapHere > 0) { gm = total + gapHere / 2; total += gapHere + g * Math.min(1, gapHere / tileSize) }
      var w = tile.dragged ? 0 : tile.mainExtent
      centresOut.push(total + w / 2)
      total += w
      if (w > 0 && j < n - 1) total += g * (tile.isSeparator ? 1 : Math.min(1, tile.enter))
      if (!tile.isSeparator && !tile.dragged) maxV = Math.max(maxV, tile.visSize)
    }
    var tail = gapWidthBefore(n)
    if (tail > 0) { gm = total + tail / 2; total += tail }
    total += padMain
    var start = (mainLength - total) / 2
    for (var c = 0; c < centresOut.length; c++) centresOut[c] += start
    // which tile is under the pointer (main axis only; the zone limits the cross axis)
    if (hovering || dragging || externalDrag) {
      for (var h = 0; h < n; h++) {
        var th = list[h]
        if (!th || th.dragged) continue
        var half = (th.isSeparator ? separatorWidth : th.visSize) / 2 + g / 2
        var d = Math.abs(pm - centresOut[h])
        if (d <= half && d < bestD) { bestD = d; hi = h; hsep = th.isSeparator }
      }
    }
    centres = centresOut
    bgStart = start
    bgLength = total
    maxVis = maxV
    gapMain = gm >= 0 ? gm + start : -1
    hoverIndex = hi
    hoverSeparator = hsep
  }

  // ======================================================== drag & drop (§9)
  property bool dragging: false
  property bool landing: false
  property int dragIndex: -1
  property string dragId: ""
  property real dragMain: 0
  property real dragCross: 0
  property real dragOffMain: 0
  property real dragOffCross: 0
  property bool removeMode: false
  property int gapIndex: -1
  property bool externalDrag: false
  property int dropIndex: -1
  property var pressPoint: ({ m: 0, c: 0 })
  property int pressedIndex: -1
  property bool pressMoved: false

  // Two gap springs: the one closing where the tile came from, the one opening
  // where it would land. Retargeting keeps velocity (spec 300/28 feel).
  HUi.SpringValue { id: gapA; property int at: -1; to: 0; preset: Motion.dock.gap; reduced: root.reduceMotion; epsilon: 0.3; onRunningChanged: root.springRunning(running) }
  HUi.SpringValue { id: gapB; property int at: -1; to: 0; preset: Motion.dock.gap; reduced: root.reduceMotion; epsilon: 0.3; onRunningChanged: root.springRunning(running) }
  function gapWidthBefore(row) {
    var w = 0
    if (gapA.at === row) w += gapA.value
    if (gapB.at === row) w += gapB.value
    return w
  }
  function setGap(row, width) {
    // move the open gap: the current one closes, a fresh one opens at `row`
    var open = gapA.to > 0 ? gapA : (gapB.to > 0 ? gapB : null)
    if (open && open.at === row) { open.to = width; return }
    var other = open === gapA ? gapB : gapA
    if (open) open.to = 0
    other.at = row
    other.to = width
    if (other.value < 0.5 && width > 0 && open === null) other.snap(0)
  }
  function closeGaps() { gapA.to = 0; gapB.to = 0 }
  function snapGapsClosed() { gapA.to = 0; gapB.to = 0; gapA.snap(0); gapB.snap(0); gapA.at = -1; gapB.at = -1 }

  HUi.SpringValue { id: landMain; to: 0; preset: Motion.dock.land; reduced: root.reduceMotion; epsilon: 0.3; onRunningChanged: { root.springRunning(running); root.checkLanded() } }
  HUi.SpringValue { id: landCross; to: 0; preset: Motion.dock.land; reduced: root.reduceMotion; epsilon: 0.3; onRunningChanged: { root.springRunning(running); root.checkLanded() } }
  readonly property real ghostMain: landing ? landMain.value : dragMain
  readonly property real ghostCross: landing ? landCross.value : dragCross

  function draggable(item) { return item && !item.locked && (item.kind === "app" && item.pinned || item.kind === "folder" || item.kind === "file") }
  // Rows a dragged item may land in: pinned apps between the file manager and
  // the first separator, folders/files in the document area.
  function sectionRows(kind) {
    var rows = []
    var sep = tileRow("sep:apps")
    if (kind === "app") { for (var i = 1; i < sep; i++) { var it = items[tiles.get(i).itemId]; if (it && it.kind === "app" && it.pinned && !it.locked && !it.gone) rows.push(i) } }
    else { for (var j = sep + 1; j < tiles.count; j++) { var jt = items[tiles.get(j).itemId]; if (jt && (jt.kind === "folder" || jt.kind === "file") && !jt.gone) rows.push(j) } }
    return rows
  }
  function insertionRow(kind, m, excludeRow) {
    var rows = sectionRows(kind)
    var cs = [], rs = []
    for (var i = 0; i < rows.length; i++) if (rows[i] !== excludeRow) { rs.push(rows[i]); cs.push(centres[rows[i]]) }
    var idx = DockModel.insertionIndex(m, cs)
    if (rs.length === 0) {
      // empty section: right after the separator (apps) or before the trash / minimized (docs)
      if (kind === "app") return tileRow("sep:apps")
      var first = tiles.count - 1
      for (var j = tileRow("sep:apps") + 1; j < tiles.count; j++) { var k = items[tiles.get(j).itemId]; if (k && (k.kind === "minimizedWindow" || k.kind === "trash")) { first = j; break } }
      return first
    }
    return idx < rs.length ? rs[idx] : rs[rs.length - 1] + 1
  }

  function beginDrag(row) {
    var id = tiles.get(row).itemId
    var t = rep.itemAt(row)
    if (!t) return
    dragId = id
    dragIndex = row
    dragOffMain = pointerMain - t.main
    dragOffCross = pointerCross - dockBaseline
    dragMain = t.main
    dragCross = dockBaseline
    dragging = true
    removeMode = false
    hideTimer.stop()
    // its own slot stays open at exactly its width, so nothing jumps
    gapA.at = row; gapA.snap(t.mainExtent); gapA.to = t.mainExtent
    gapB.at = -1; gapB.to = 0; gapB.snap(0)
    gapIndex = row
  }
  function updateDrag() {
    dragMain = pointerMain - dragOffMain
    dragCross = pointerCross - dragOffCross
    var item = items[dragId]
    if (!item) return
    var outside = pointerCross > bgThickness + tileSize * Motion.dock.removeDistance
        || pointerMain < bgStart - tileSize * Motion.dock.removeDistance
        || pointerMain > bgStart + bgLength + tileSize * Motion.dock.removeDistance
    if (outside) { if (!removeMode && !removeTimer.running) removeTimer.restart() }
    else { removeTimer.stop(); if (removeMode) { removeMode = false; setGap(gapIndex, tileSize) } }
    if (!removeMode) {
      var row = insertionRow(item.kind, dragMain, dragIndex)
      if (row !== gapIndex) { gapIndex = row; setGap(row, tileSize) }
    }
  }
  Timer { id: removeTimer; interval: Motion.dock.removeHold; onTriggered: { root.removeMode = true; root.closeGaps() } }
  function endDrag() {
    removeTimer.stop()
    if (removeMode) { removeDragged(); return }
    // glide into the gap
    landing = true
    landMain.snap(dragMain); landCross.snap(dragCross)
    landMain.to = gapMain >= 0 ? gapMain : dragMain
    landCross.to = dockBaseline
    Qt.callLater(checkLanded)
  }
  function checkLanded() {
    if (!landing) return
    if (landMain.running || landCross.running) return
    applyDrop()
  }
  function applyDrop() {
    var item = items[dragId]
    var fromRow = dragIndex
    var toRow = gapIndex
    landing = false
    dragging = false
    if (item) {
      if (toRow > fromRow) toRow -= 1
      if (toRow !== fromRow) {
        tiles.move(fromRow, toRow, 1)
        // persist the new order
        if (item.kind === "app") {
          var ids = []
          var rows = sectionRows("app")
          for (var i = 0; i < rows.length; i++) { var it = items[tiles.get(rows[i]).itemId]; if (it) ids.push(it.entryId) }
          savePinned(ids)
        } else {
          var folders = [], files = []
          var drows = sectionRows("folder")
          for (var j = 0; j < drows.length; j++) {
            var jt = items[tiles.get(drows[j]).itemId]
            if (!jt) continue
            if (jt.kind === "folder") folders.push(folderSetting(jt))
            else files.push({ path: jt.path, name: jt.name })
          }
          var next = DockModel.copyMap(settings); next.folders = folders; next.files = files; settings = next; saveTimer.restart()
        }
      }
    }
    dragIndex = -1
    dragId = ""
    snapGapsClosed()
    var list = []
    for (var e = 0; e < tiles.count; e++) list.push({ id: tiles.get(e).itemId, kind: tiles.get(e).kind })
    entryList = list
    layoutDirty()
  }
  function folderSetting(it) { return { path: it.path.indexOf(home) === 0 ? "~" + it.path.slice(home.length) : it.path, name: it.name, displayAs: it.displayAs, viewContentAs: it.viewContentAs, sortBy: it.sortBy } }
  function removeDragged() {
    var item = items[dragId]
    ghostFade.start()
    if (item) {
      if (item.kind === "app") { var ids = []; for (var i = 0; i < pinnedIds.length; i++) { var pe = lookupEntry(pinnedIds[i]); if (keyFor(pe, pinnedIds[i]) !== item.key) ids.push(DockModel.stripDesktop(pinnedIds[i])) } savePinned(ids) }
      else removeDocItem(item)
    }
  }
  function removeDocItem(item) {
    var next = DockModel.copyMap(settings)
    if (item.kind === "folder") next.folders = (settings.folders || []).filter(function (f) { return DockModel.expandHome(f.path, home) !== item.path })
    else next.files = (settings.files || []).filter(function (f) { return DockModel.expandHome(f.path, home) !== item.path })
    settings = next; saveTimer.restart(); scheduleRebuild()
  }
  property real ghostOpacity: 1
  property real ghostScale: 1
  SequentialAnimation {
    id: ghostFade
    ParallelAnimation {
      NumberAnimation { target: root; property: "ghostOpacity"; to: 0; duration: Motion.dock.removeFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeExit }
      NumberAnimation { target: root; property: "ghostScale"; to: root.reduceMotion ? 1 : Motion.dock.removeScale; duration: Motion.dock.removeFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeExit }
    }
    ScriptAction { script: { root.dragging = false; root.removeMode = false; root.dragIndex = -1; root.dragId = ""; root.snapGapsClosed(); root.ghostOpacity = 1; root.ghostScale = 1; root.layoutDirty() } }
  }

  // External objects (§9.3)
  property var externalUrls: []
  function externalMove(x, y, hasUrls) {
    if (!hasUrls) return
    externalDrag = true
    pointerMain = mainOf(x, y); pointerCross = crossOf(x, y)
    dockHidden = false
    relayout()
    var hi = hoverIndex
    var target = hi >= 0 ? items[tiles.get(hi).itemId] : null
    dropIndex = target && (target.kind === "app" || target.kind === "folder" || target.kind === "trash") ? hi : -1
    // a gap in the document area only (apps never part for foreign files)
    var sep = tileRow("sep:apps")
    var inDocs = hi < 0 && pointerMain > centres[sep] && pointerCross < bgThickness + tileSize
    if (inDocs) { var row = insertionRow("folder", pointerMain, -1); if (row !== gapIndex) { gapIndex = row; setGap(row, tileSize) } }
    else if (gapIndex >= 0) { gapIndex = -1; closeGaps() }
  }
  function externalLeave() { externalDrag = false; dropIndex = -1; gapIndex = -1; closeGaps(); armAutoHide() }
  function externalDrop(urls) {
    var paths = []
    for (var i = 0; i < urls.length; i++) { var u = String(urls[i]); if (u.indexOf("file://") === 0) paths.push(decodeURIComponent(u.slice(7))) }
    var target = dropIndex >= 0 ? items[tiles.get(dropIndex).itemId] : null
    if (target && paths.length) {
      if (target.kind === "app") openWith(target, paths)
      else if (target.kind === "folder") Quickshell.execDetached(["gio", "move"].concat(paths).concat([target.path]))
      else if (target.kind === "trash") { Quickshell.execDetached(["gio", "trash"].concat(paths)); trashRecount.restart() }
    } else if (gapIndex >= 0 && paths.length) {
      describe.pending = paths
      describe.running = true
    }
    externalLeave()
  }
  // Describes dropped paths (dir? icon names?) so they can join the document area.
  Process {
    id: describe
    property var pending: []
    command: ["python3", "-c",
      "import sys, os, json\nimport gi\ngi.require_version('Gio', '2.0')\nfrom gi.repository import Gio\nout = []\nfor p in sys.argv[1:]:\n    try:\n        f = Gio.File.new_for_path(p)\n        i = f.query_info('standard::display-name,standard::icon,standard::type', 0, None)\n        ic = i.get_icon()\n        out.append({'path': p, 'name': i.get_display_name(), 'icon': list(ic.get_names()) if ic is not None and hasattr(ic, 'get_names') else [], 'isDir': i.get_file_type() == Gio.FileType.DIRECTORY})\n    except Exception:\n        pass\nprint(json.dumps(out))\n"].concat(pending)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var list = []
        try { list = JSON.parse(String(text || "[]")) } catch (e) {}
        var next = DockModel.copyMap(root.settings)
        var folders = (next.folders || []).slice(), files = (next.files || []).slice()
        for (var i = 0; i < list.length; i++) {
          var d = list[i]
          var rel = d.path.indexOf(root.home) === 0 ? "~" + d.path.slice(root.home.length) : d.path
          if (d.isDir) { if (!folders.some(function (f) { return DockModel.expandHome(f.path, root.home) === d.path })) folders.push({ path: rel, name: d.name, displayAs: "stack", viewContentAs: "auto", sortBy: "dateAdded" }) }
          else if (!files.some(function (f) { return DockModel.expandHome(f.path, root.home) === d.path })) files.push({ path: rel, name: d.name, icon: d.icon })
        }
        next.folders = folders; next.files = files
        root.settings = next; saveTimer.restart(); root.scheduleRebuild()
      }
    }
  }
  function desktopFileCandidates(entryId) {
    var id = DockModel.stripDesktop(entryId)
    return [home + "/.local/share/applications/" + id + ".desktop", "/usr/share/applications/" + id + ".desktop",
            "/usr/local/share/applications/" + id + ".desktop", "/var/lib/flatpak/exports/share/applications/" + id + ".desktop",
            home + "/.local/share/flatpak/exports/share/applications/" + id + ".desktop"]
  }
  // Folders and trash:/// go straight to the file manager: xdg-open has no
  // handler for the trash scheme here and falls back to the browser.
  function openInFileManager(target) {
    var cands = desktopFileCandidates(settings.fileManager)
    Quickshell.execDetached(["sh", "-c", 'for c in "$@"; do [ -f "$c" ] && exec gio launch "$c" "$0"; done; exec xdg-open "$0"', target].concat(cands))
  }
  function openWith(item, paths) {
    var script = 'for f in "$@"; do shift; [ -f "$f" ] && { exec gio launch "$f" "$@"; }; done'
    // the candidate list comes first, paths after a marker handled by the shell loop above
    var cands = desktopFileCandidates(item.entryId)
    var cmd = ["sh", "-c", 'i=0; for c in ' + cands.map(function (c) { return "'" + c.replace(/'/g, "'\\''") + "'" }).join(" ") + '; do [ -f "$c" ] && exec gio launch "$c" "$@"; done; exec xdg-open "$1"', "dock"].concat(paths)
    Quickshell.execDetached(cmd)
  }

  // ======================================================== pressing, clicking, menus (§7, §10)
  property bool menuOpen: false
  property bool menuFrozen: menuOpen
  property bool stackOpen: false
  property bool settingsOpen: false
  readonly property bool popupOpen: menuOpen || stackOpen || settingsOpen
  property bool altHeld: false
  property string menuItemId: ""
  property var menuModel: []
  property bool resizing: false
  property int resizeStart: 48
  property real resizeCross: 0

  function pressAt(mouseX, mouseY, button, mods) {
    var m = mainOf(mouseX, mouseY), c = crossOf(mouseX, mouseY)
    pointerMain = m; pointerCross = c
    altHeld = (mods & Qt.AltModifier) !== 0
    relayout()
    pressPoint = { m: m, c: c }
    pressMoved = false
    if (popupOpen) {
      // An open stack closes on any dock click; on its own tile the click is
      // only that (toggle), elsewhere it goes on as a normal press.
      if (stackOpen && !menuOpen && !settingsOpen) {
        var same = hoverIndex >= 0 && tiles.get(hoverIndex).itemId === stackItemId
        closeStack()
        if (same) return
      } else return
    }
    if (hoverIndex < 0) return
    if (button === Qt.RightButton || (mods & Qt.ControlModifier)) { openMenuFor(hoverIndex); return }
    if (hoverSeparator) { resizing = true; resizeStart = tileSize; resizeCross = c; return }
    pressedIndex = hoverIndex
  }
  function moveTo(mouseX, mouseY, pressed, mods) {
    var m = mainOf(mouseX, mouseY), c = crossOf(mouseX, mouseY)
    pointerMain = m; pointerCross = c
    invertMagnification = (mods & Qt.ControlModifier) !== 0 && (mods & Qt.ShiftModifier) !== 0
    if (!pressed) return
    if (resizing) {
      var next = Math.round(resizeStart + (c - resizeCross))
      if (mods & Qt.AltModifier) { var steps = [16, 32, 48, 64, 128]; var best = steps[0]; for (var i = 0; i < steps.length; i++) if (Math.abs(steps[i] - next) < Math.abs(best - next)) best = steps[i]; next = best }
      next = DockModel.clamp(next, Apple.dock.tileMin, Apple.dock.tileMax)
      if (next !== settings.tileSize) setSetting("tileSize", next)
      if (mods & Qt.ShiftModifier) {
        // Shift: drag the separator to another screen edge to move the dock there
        var edge = Style.space(60)
        if (horizontal) { if (mouseX < edge) setSetting("position", "left"); else if (mouseX > planeWidth - edge) setSetting("position", "right") }
        else if (mouseY > planeHeight - edge) setSetting("position", "bottom")
      }
      return
    }
    if (dragging) { updateDrag(); return }
    if (pressedIndex >= 0) {
      var dist = Math.hypot(m - pressPoint.m, c - pressPoint.c)
      if (dist > Motion.dock.dragThreshold) {
        pressMoved = true
        var it = items[tiles.get(pressedIndex).itemId]
        if (draggable(it)) { var row = pressedIndex; pressedIndex = -1; beginDrag(row) }
      }
    }
  }
  function releaseAt(mouseX, mouseY, button) {
    if (resizing) { resizing = false; return }
    if (dragging) { endDrag(); return }
    var idx = pressedIndex
    pressedIndex = -1
    if (idx < 0 || pressMoved || popupOpen) return
    if (button === Qt.LeftButton && hoverIndex === idx) activate(idx)
  }
  function longPress() {
    if (pressedIndex >= 0 && !dragging && !pressMoved) { var i = pressedIndex; pressedIndex = -1; openMenuFor(i) }
  }

  function activate(row) {
    var id = tiles.get(row).itemId
    var item = items[id]
    if (!item || item.gone) return
    if (item.kind === "app") activateApp(item)
    else if (item.kind === "folder") toggleStack(id)
    else if (item.kind === "file") Quickshell.execDetached(["xdg-open", item.path])
    else if (item.kind === "minimizedWindow") restoreWindow(item.address, false)
    else if (item.kind === "trash") openInFileManager("trash:///")
  }
  function activateApp(item) {
    clearAttention(item.id)
    if (!item.running) { launchItem(item); return }
    var wins = item.windows || []
    var visible = wins.filter(function (w) { return !w.minimized })
    if (visible.length === 0 && wins.length > 0) { restoreWindow(wins[0].address, false); return }
    if (visible.length > 0) focusWindow(visible[0].address)
  }
  function launchItem(item) {
    if (!item.entry) return
    var lp = DockModel.copyMap(launchPending); lp[item.key] = Date.now(); launchPending = lp
    launchPrune.restart()
    scheduleRebuild()
    try { item.entry.execute() } catch (e) { console.warn("henri.dock: launch failed", item.entryId, e) }
  }
  Timer {
    id: launchPrune
    interval: 10000
    onTriggered: { var lp = DockModel.copyMap(root.launchPending); var now = Date.now(); var ch = false; for (var k in lp) if (now - lp[k] > 9500) { delete lp[k]; ch = true }; if (ch) { root.launchPending = lp; root.scheduleRebuild() } }
  }

  function dispatch(lua, legacy) { Hyprland.dispatch(Hyprland.usingLua ? lua : legacy) }
  function focusWindow(address) {
    if (!address) return
    dispatch('hl.dsp.focus({ window = "address:' + address + '" })', "focuswindow address:" + address)
  }
  function workspaceTarget(ws) { if (!ws) return ""; var n = String(ws.name || ""); return n !== "" ? n : String(ws.id) }
  function hyprToplevelFor(address) {
    var tls = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < tls.length; i++) if (tls[i] && DockModel.normalizeAddress(tls[i].address) === address) return tls[i]
    return null
  }

  // ---- menus
  function openMenuFor(row) {
    var id = tiles.get(row).itemId
    var item = items[id]
    if (!item) return
    menuItemId = id
    menuModel = buildMenu(item)
    var t = rep.itemAt(row)
    menu.anchorMain = t ? t.main : mainLength / 2
    menu.anchorCross = dockBaseline + (t ? t.visSize : tileSize) + Style.space(Apple.dock.labelGap) / 2
    hideTimer.stop()
    menuOpen = true
  }
  function closeMenu() { menuOpen = false; armAutoHide() }
  onAltHeldChanged: if (menuOpen && menuItemId) menuModel = buildMenu(items[menuItemId] || {})
  function buildMenu(item) {
    var m = []
    var s = settings
    if (item.kind === "app") {
      if (item.running) {
        var wins = item.windows || []
        for (var i = 0; i < wins.length; i++) m.push({ text: wins[i].title || item.name, checked: wins[i].activated === true, action: "focus", arg: wins[i].address })
        if (wins.length) m.push({ separator: true })
      }
      m.push({ text: "Options", submenu: [
        { text: "Keep in Dock", checked: item.pinned === true && !item.locked, enabled: !item.locked, action: "togglePin" },
        { text: "Open at Login", checked: (s.loginApps || []).indexOf(item.entryId) >= 0, action: "toggleLogin" },
        { text: "Show in File Manager", action: "showInFiles" }
      ] })
      if (item.running) {
        m.push({ separator: true })
        m.push({ text: "Show All Windows", action: "showAll" })
        m.push({ text: "Hide", action: "hideApp" })
        m.push({ text: altHeld ? "Force Quit" : "Quit", action: altHeld ? "forceQuit" : "quit" })
      } else {
        m.push({ text: "Open", action: "open" })
        if (item.recent) m.push({ text: "Remove from Recents", action: "removeRecent" })
      }
    } else if (item.kind === "folder") {
      var sb = item.sortBy, da = item.displayAs, va = item.viewContentAs
      m.push({ text: "Sort by", submenu: [
        { text: "Name", checked: sb === "name", action: "sortBy", arg: "name" },
        { text: "Date Added", checked: sb === "dateAdded", action: "sortBy", arg: "dateAdded" },
        { text: "Date Modified", checked: sb === "dateModified", action: "sortBy", arg: "dateModified" },
        { text: "Date Created", checked: sb === "dateCreated", action: "sortBy", arg: "dateCreated" },
        { text: "Kind", checked: sb === "kind", action: "sortBy", arg: "kind" } ] })
      m.push({ text: "Display as", submenu: [
        { text: "Folder", checked: da === "folder", action: "displayAs", arg: "folder" },
        { text: "Stack", checked: da === "stack", action: "displayAs", arg: "stack" } ] })
      m.push({ text: "View content as", submenu: [
        { text: "Fan", checked: va === "fan", action: "viewAs", arg: "fan" },
        { text: "Grid", checked: va === "grid", action: "viewAs", arg: "grid" },
        { text: "List", checked: va === "list", action: "viewAs", arg: "list" },
        { text: "Automatic", checked: va === "auto", action: "viewAs", arg: "auto" } ] })
      m.push({ separator: true })
      m.push({ text: "Remove from Dock", action: "removeDoc" })
      m.push({ text: "Open in File Manager", action: "openFolder" })
    } else if (item.kind === "file") {
      m.push({ text: "Open", action: "openFile" })
      m.push({ text: "Show in File Manager", action: "showFile" })
      m.push({ separator: true })
      m.push({ text: "Remove from Dock", action: "removeDoc" })
    } else if (item.kind === "separator") {
      m.push({ text: magnificationOn ? "Turn Magnification Off" : "Turn Magnification On", action: "toggleMag" })
      m.push({ text: "Position on Screen", submenu: [
        { text: "Left", checked: s.position === "left", action: "position", arg: "left" },
        { text: "Bottom", checked: s.position === "bottom", action: "position", arg: "bottom" },
        { text: "Right", checked: s.position === "right", action: "position", arg: "right" } ] })
      m.push({ text: "Minimize Using", submenu: [
        { text: "Genie Effect", checked: s.minimizeEffect === "genie", action: "effect", arg: "genie" },
        { text: "Scale Effect", checked: s.minimizeEffect === "scale", action: "effect", arg: "scale" } ] })
      m.push({ text: autoHide ? "Turn Hiding Off" : "Turn Hiding On", action: "toggleHide" })
      m.push({ separator: true })
      m.push({ text: "Dock Settings…", action: "settings" })
    } else if (item.kind === "trash") {
      m.push({ text: "Open", action: "openTrash" })
      m.push({ text: "Empty Trash", enabled: item.full === true, danger: true, action: "emptyTrash" })
    } else if (item.kind === "minimizedWindow") {
      m.push({ text: "Restore", action: "restore" })
      m.push({ text: "Close", action: "closeWindow" })
    }
    return m
  }
  function runMenuAction(entry) {
    var item = items[menuItemId] || {}
    var a = entry.action
    if (a === "focus") focusWindow(entry.arg)
    else if (a === "open") launchItem(item)
    else if (a === "togglePin") togglePin(item)
    else if (a === "removeRecent") { recents = recents.filter(function (r) { return r.key !== item.key }); scheduleRebuild() }
    else if (a === "toggleLogin") { var la = (settings.loginApps || []).slice(); var ix = la.indexOf(item.entryId); if (ix >= 0) la.splice(ix, 1); else la.push(item.entryId); setSetting("loginApps", la) }
    else if (a === "showInFiles") Quickshell.execDetached(["sh", "-c", 'for c in "$@"; do [ -f "$c" ] && exec finder --select "$c"; done; exec finder /usr/share/applications', "dock"].concat(desktopFileCandidates(item.entryId)))
    else if (a === "showAll") { var w = (item.windows || []).filter(function (x) { return !x.minimized }); if (w.length) focusWindow(w[0].address); missionControl.restart() }
    else if (a === "hideApp") { var ws = (item.windows || []).filter(function (x) { return !x.minimized }); for (var i = 0; i < ws.length; i++) minimizeWindow(ws[i].address, false, i === 0) }
    else if (a === "quit") { var q = item.windows || []; for (var j = 0; j < q.length; j++) if (q[j].wayland) q[j].wayland.close() }
    else if (a === "forceQuit") { var pids = {}; var fq = item.windows || []; for (var k = 0; k < fq.length; k++) { var o = fq[k].hypr ? fq[k].hypr.lastIpcObject : null; if (o && o.pid) pids[o.pid] = true } var cmd = ["kill", "-9"]; for (var pk in pids) cmd.push(String(pk)); if (cmd.length > 2) Quickshell.execDetached(cmd) }
    else if (a === "sortBy" || a === "displayAs" || a === "viewAs") updateFolder(item, a === "sortBy" ? "sortBy" : a === "displayAs" ? "displayAs" : "viewContentAs", entry.arg)
    else if (a === "removeDoc") removeDocItem(item)
    else if (a === "openFolder") openInFileManager(item.path)
    else if (a === "openFile") Quickshell.execDetached(["xdg-open", item.path])
    else if (a === "showFile") Quickshell.execDetached(["finder", "--select", item.path])
    else if (a === "toggleMag") setSetting("magnification", !magnificationOn)
    else if (a === "position") setSetting("position", entry.arg)
    else if (a === "effect") setSetting("minimizeEffect", entry.arg)
    else if (a === "toggleHide") setSetting("autoHide", !autoHide)
    else if (a === "settings") { settingsOpen = true }
    else if (a === "openTrash") openInFileManager("trash:///")
    else if (a === "emptyTrash") { Quickshell.execDetached(["gio", "trash", "--empty"]); trashRecount.restart() }
    else if (a === "restore") restoreWindow(item.address, false)
    else if (a === "closeWindow") { if (item.window && item.window.wayland) item.window.wayland.close() }
  }
  Timer { id: missionControl; interval: 120; onTriggered: root.dispatch('hl.dsp.event("mission-control toggle app")', "event mission-control toggle app") }
  function togglePin(item) {
    if (item.locked) return
    if (item.pinned) { var ids = []; for (var i = 0; i < pinnedIds.length; i++) { var pe = lookupEntry(pinnedIds[i]); if (keyFor(pe, pinnedIds[i]) !== item.key) ids.push(DockModel.stripDesktop(pinnedIds[i])) } savePinned(ids) }
    else { var add = pinnedIds.slice(); add.push(item.entryId); savePinned(add) }
  }
  function updateFolder(item, field, value) {
    var folders = (settings.folders || []).map(function (f) {
      if (DockModel.expandHome(f.path, home) !== item.path) return f
      var n = DockModel.copyMap(f); n[field] = value; return n
    })
    setSetting("folders", folders)
    scheduleRebuild()
  }

  // ---- stacks (§11)
  property string stackItemId: ""
  function toggleStack(id) {
    if (stackOpen && stackItemId === id) { closeStack(); return }
    var item = items[id]
    if (!item) return
    stackItemId = id
    var t = tileFor(id)
    stack.folder = item
    stack.entries = item.entries || []
    var view = DockModel.resolveView(item.viewContentAs, stack.entries.length, Apple.dock.fanMax)
    if (!horizontal && view === "fan") view = "grid"
    stack.view = view
    stack.anchorMain = t ? t.main : mainLength / 2
    stack.anchorCross = dockBaseline + (t ? t.visSize : tileSize)
    hideTimer.stop()
    stackOpen = true
  }
  function closeStack() { stackOpen = false; armAutoHide() }

  // ======================================================== minimize / restore (§12)
  property var parkedAt: ({})
  property var pendingMinimize: null
  property string effectTargetId: ""
  readonly property bool effectRunning: fx.running
  property var lastRestoreAddress: ""

  Component {
    id: snapComp
    ScreencopyView {
      live: false
      paintCursor: false
      visible: true
      property int attempts: 0
    }
  }
  Component { id: watcherComp; FolderWatcher {} }

  function windowPlaneRect(t) {
    var o = t.lastIpcObject || {}
    var mon = Hyprland.monitorFor(screen)
    var at = o.at || [0, 0], size = o.size || [400, 300]
    var mx = mon ? mon.x : 0, my = mon ? mon.y : 0
    return { x: at[0] - mx, y: at[1] - my, w: size[0], h: size[1] }
  }
  function minimizeActiveWindow(slow) {
    var t = Hyprland.activeToplevel
    if (!t) return "no active window"
    return minimizeWindow(DockModel.normalizeAddress(t.address), slow, true) ? "ok" : "failed"
  }
  function minimizeWindow(address, slow, animate) {
    var t = hyprToplevelFor(address)
    if (!t) return false
    if (t.workspace && String(t.workspace.name) === minimizedWorkspace) return false
    var origin = workspaceTarget(t.workspace) || workspaceTarget(Hyprland.focusedWorkspace)
    var pa = DockModel.copyMap(parkedAt); pa[address] = Date.now(); parkedAt = pa
    var rect = windowPlaneRect(t)
    var uv = uvOf(rect.x, rect.y, rect.w, rect.h)
    var mr = DockModel.copyMap(minimizedRects); mr[address] = uv; minimizedRects = mr
    var snap = snapshots[address]
    if (!snap && t.wayland) {
      snap = snapComp.createObject(vault, { captureSource: t.wayland, width: rect.w, height: rect.h })
      var sn = DockModel.copyMap(snapshots); sn[address] = snap; snapshots = sn
    }
    dockHidden = false
    if (animate && snap && !snap.hasContent) {
      pendingMinimize = { address: address, slow: slow, origin: origin, tries: 0 }
      captureTimer.restart()
      snap.captureFrame()
      return true
    }
    parkWindow(address, slow, animate)
    return true
  }
  Timer {
    id: captureTimer
    interval: 45
    repeat: true
    onTriggered: {
      var p = root.pendingMinimize
      if (!p) { stop(); return }
      var snap = root.snapshots[p.address]
      if (snap && snap.hasContent) { stop(); root.pendingMinimize = null; root.parkWindow(p.address, p.slow, true); return }
      p.tries += 1
      if (p.tries > 14) { stop(); root.pendingMinimize = null; root.parkWindow(p.address, p.slow, false); return }
      if (snap) snap.captureFrame()
    }
  }
  function parkWindow(address, slow, animate) {
    dispatch('hl.dsp.window.move({ window = "address:' + address + '", workspace = "' + DockModel.luaString(minimizedWorkspace) + '", follow = false })',
             "movetoworkspacesilent " + minimizedWorkspace + ",address:" + address)
    Hyprland.refreshToplevels()
    rebuild()
    var snap = snapshots[address]
    var targetId = settings.minimizeToAppIcon === true ? appIdForAddress(address) : "win:" + address
    if (animate && snap && snap.hasContent) {
      effectTargetId = targetId
      fx.targetId = targetId
      fx.play(snap, minimizedRects[address], tileUV(targetId), settings.minimizeEffect === "scale" ? "scale" : "genie", false, slow === true)
    }
    scheduleRebuild()
  }
  function appIdForAddress(address) {
    for (var id in items) { var it = items[id]; if (it.kind === "app" && it.windows) for (var i = 0; i < it.windows.length; i++) if (it.windows[i].address === address) return id }
    return ""
  }
  function restoreWindow(address, slow) {
    var t = hyprToplevelFor(address)
    if (!t) return false
    var target = workspaceTarget(Hyprland.focusedWorkspace)
    if (!target) return false
    var snap = snapshots[address]
    var uv = minimizedRects[address]
    var srcId = settings.minimizeToAppIcon === true ? appIdForAddress(address) : "win:" + address
    if (snap && snap.hasContent && uv && !reduceMotion) {
      effectTargetId = srcId
      fx.targetId = srcId
      fx.restoreAddress = address
      fx.restoreTarget = target
      fx.play(snap, uv, tileUV(srcId), settings.minimizeEffect === "scale" ? "scale" : "genie", true, slow === true)
    } else {
      unparkWindow(address, target)
    }
    return true
  }
  function unparkWindow(address, target) {
    dispatch('hl.dsp.window.move({ window = "address:' + address + '", workspace = "' + DockModel.luaString(target) + '", follow = false })',
             "movetoworkspacesilent " + target + ",address:" + address)
    dispatch('hl.dsp.focus({ workspace = "' + DockModel.luaString(target) + '" })', "workspace " + target)
    focusWindow(address)
    var pa = DockModel.copyMap(parkedAt); delete pa[address]; parkedAt = pa
    Hyprland.refreshToplevels()
    scheduleRebuild()
  }
  function restoreLast() {
    var best = "", bt = -1
    for (var a in parkedAt) if (parkedAt[a] > bt && hyprToplevelFor(a)) { bt = parkedAt[a]; best = a }
    if (!best) { for (var id in items) if (items[id].kind === "minimizedWindow") { best = items[id].address; break } }
    return best ? (restoreWindow(best, false) ? "ok" : "failed") : "nothing minimized"
  }
  function pruneSnapshots(groups) {
    var keep = {}
    var alive = {}
    for (var k in groups) for (var i = 0; i < groups[k].windows.length; i++) { alive[groups[k].windows[i].address] = true; if (groups[k].windows[i].minimized) keep[groups[k].windows[i].address] = true }
    // parked a moment ago: Hyprland reports the workspace change slightly later
    for (var pa in parkedAt) if (alive[pa]) keep[pa] = true
    if (pendingMinimize) keep[pendingMinimize.address] = true
    if (fx.running && fx.restoreAddress) keep[fx.restoreAddress] = true
    var changed = false
    var sn = DockModel.copyMap(snapshots)
    for (var a in sn) if (!keep[a] && !(fx.running && effectTargetId === "win:" + a)) { sn[a].destroy(); delete sn[a]; changed = true }
    if (changed) snapshots = sn
  }

  // ======================================================== attention & badges (§7.4, §8.2)
  function requestAttention(key, repeats) {
    var m = DockModel.copyMap(attentionMap); m[key] = true; attentionMap = m
    var r = DockModel.copyMap(attentionRepeatsMap); r[key] = repeats > 0 ? repeats : Motion.dock.attentionRepeats; attentionRepeatsMap = r
    if (autoHide) dockHidden = false
    scheduleRebuild()
  }
  function attentionRepeats(itemId) { var it = items[itemId]; return it && attentionRepeatsMap[it.key] ? attentionRepeatsMap[it.key] : Motion.dock.attentionRepeats }
  function clearAttention(itemId) {
    var it = items[itemId]
    var key = it ? it.key : itemId.replace(/^app:/, "")
    if (!attentionMap[key]) return
    var m = DockModel.copyMap(attentionMap); delete m[key]; attentionMap = m
    scheduleRebuild()
    armAutoHide()
  }
  function setBadge(id, badge) {
    var b = DockModel.copyMap(badges)
    var k = String(id)
    if (badge === null || badge === undefined || badge === "" || badge === "null") delete b[k]; else b[k] = badge
    badges = b
    scheduleRebuild()
  }

  // ======================================================== auto-hide (§13) and position swap (§15)
  property bool dockHidden: false
  // Hidden by hand (Super+D / `dock toggle`): slides out, gives the space back
  // and stays out until toggled again — no edge trigger.
  property bool manualHidden: false
  readonly property bool hiddenNow: manualHidden || (autoHide && dockHidden)
  property real hideOffset: 0
  readonly property real hiddenDistance: bgThickness + Style.space(2)
  readonly property real hideDX: reduceMotion ? 0 : (position === "left" ? -hideOffset * hiddenDistance : position === "right" ? hideOffset * hiddenDistance : 0)
  readonly property real hideDY: reduceMotion ? 0 : (position === "bottom" ? hideOffset * hiddenDistance : 0)
  readonly property real hideOpacity: reduceMotion ? 1 - hideOffset : 1

  onAutoHideChanged: { if (autoHide) armAutoHide(); else dockHidden = false }
  // A space without windows has nothing the dock could be in the way of: it
  // stays out there and only starts hiding once a window is on the space.
  // Minimized windows live on their own special workspace and do not count.
  readonly property var dockWorkspace: { var m = Hyprland.monitorFor(root.screen); return m ? m.activeWorkspace : null }
  readonly property bool emptySpace: dockWorkspace && dockWorkspace.toplevels ? dockWorkspace.toplevels.values.length === 0 : false
  onEmptySpaceChanged: { if (!autoHide) return; if (emptySpace) { hideTimer.stop(); dockHidden = false } else armAutoHide() }
  onHiddenNowChanged: if (!swapAnim.running) hideAnim.go(hiddenNow ? 1 : 0)
  // Fullscreen: Hyprland draws "top" layers under a fullscreen window, so the
  // dock vanishes with it. Super+D then lifts both surfaces to the overlay
  // layer (visible above the window); Super+D again drops them back. When the
  // fullscreen ends the dock returns to its normal layer by itself.
  // `hasFullscreen` is also true for a maximized window (Super+Alt+F), which
  // stays under the top layer — only a real fullscreen (mode 2) covers the dock.
  readonly property bool fullscreenActive: {
    var ws = Hyprland.focusedWorkspace
    if (!ws || ws.hasFullscreen !== true) return false
    var all = Hyprland.toplevels.values
    for (var i = 0; i < all.length; i++) { var o = all[i].lastIpcObject; if (o && o.fullscreen === 2 && o.workspace && o.workspace.id === ws.id) return true }
    return false
  }
  property bool overFullscreen: false
  onFullscreenActiveChanged: if (!fullscreenActive) overFullscreen = false
  function toggleDock() {
    if (fullscreenActive && !manualHidden) { overFullscreen = !overFullscreen; return overFullscreen ? "shown over fullscreen" : "under fullscreen" }
    manualHidden = !manualHidden
    if (!manualHidden) dockHidden = false
    return manualHidden ? "hidden" : "shown"
  }
  NumberAnimation {
    id: hideAnim
    target: root
    property: "hideOffset"
    duration: Number(root.settings.autoHideDuration) || Motion.dock.autoHideDuration
    easing.type: Easing.BezierSpline
    easing.bezierCurve: root.hiddenNow ? Motion.easeExit : Motion.easeOut
    function go(v) { stop(); to = v; start() }
  }
  Timer { id: revealTimer; interval: Number(root.settings.autoHideDelay) || Motion.dock.autoHideDelay; onTriggered: root.dockHidden = false }
  Timer { id: hideTimer; interval: Motion.dock.autoHideLeave; onTriggered: if (root.autoHide && !root.hovering && !root.popupOpen && !root.dragging && !root.externalDrag && !fx.running && !root.kbMode && !root.emptySpace) root.dockHidden = true }
  function armAutoHide() { if (autoHide) hideTimer.restart() }

  property string pendingPosition: ""
  Connections {
    target: root
    function onSettingsChanged() {
      var want = String(root.settings.position || "bottom")
      if (want !== root.position && !swapAnim.running) { root.pendingPosition = want; swapAnim.start() }
    }
  }
  SequentialAnimation {
    id: swapAnim
    NumberAnimation { target: root; property: "hideOffset"; to: 1; duration: Motion.dock.positionSwap; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeExit }
    ScriptAction { script: { root.position = root.pendingPosition; root.layoutDirty() } }
    PauseAnimation { duration: 30 }
    NumberAnimation { target: root; property: "hideOffset"; to: root.hiddenNow ? 1 : 0; duration: Motion.dock.positionSwap; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
  }

  // ======================================================== keyboard (§17)
  property bool kbMode: false
  property int kbIndex: 0
  function focusDock() {
    dockHidden = false
    manualHidden = false
    kbMode = true
    kbIndex = 0
    hovering = false
    keys.forceActiveFocus()
    layoutDirty()
    return "ok"
  }
  function kbMove(step) {
    var n = tiles.count
    if (n === 0) return
    var i = kbIndex
    for (var k = 0; k < n; k++) { i = (i + step + n) % n; var it = items[tiles.get(i).itemId]; if (it && it.kind !== "separator" && !it.gone) { kbIndex = i; break } }
    layoutDirty()
  }
  function leaveKeyboard() { kbMode = false; armAutoHide() }

  // ======================================================== trash (§16)
  Process {
    id: trashProc
    command: ["sh", "-c", "ls -A \"$HOME/.local/share/Trash/files\" 2>/dev/null | wc -l"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { var n = parseInt(String(text).trim()); if (isFinite(n) && n !== root.trashCount) { root.trashCount = n; root.scheduleRebuild() } } }
  }
  Process {
    id: trashWatch
    command: ["sh", "-c", "mkdir -p \"$HOME/.local/share/Trash/files\"; exec inotifywait -m -q -e create,delete,moved_to,moved_from \"$HOME/.local/share/Trash/files\""]
    stdout: SplitParser { onRead: function (line) { trashRecount.restart() } }
  }
  Timer { id: trashRecount; interval: 250; onTriggered: trashProc.running = true }

  // ======================================================== Hyprland events, IPC, startup
  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { root.scheduleRebuild() }
  }
  Connections {
    target: Hyprland
    function onActiveToplevelChanged() {
      var t = Hyprland.activeToplevel
      if (!t) return
      var a = DockModel.normalizeAddress(t.address)
      var m = DockModel.copyMap(root.mru); m[a] = ++root.mruCounter; root.mru = m
      root.scheduleRebuild()
    }
    function onRawEvent(ev) {
      var n = String(ev.name || "")
      if (n === "custom") {
        var d = String(ev.data || "")
        if (d === "dock minimize") root.minimizeActiveWindow(false)
        else if (d === "dock minimize-slow") root.minimizeActiveWindow(true)
        else if (d === "dock restore-last") root.restoreLast()
        else if (d === "dock toggle-autohide") root.setSetting("autoHide", !root.autoHide)
        else if (d === "dock focus") root.focusDock()
        else if (d === "dock toggle") root.toggleDock()
        else if (d === "dock settings") root.settingsOpen = true
        return
      }
      if (n === "urgent") {
        var addr = DockModel.normalizeAddress(String(ev.data || "").split(",")[0])
        var active = Hyprland.activeToplevel ? DockModel.normalizeAddress(Hyprland.activeToplevel.address) : ""
        if (addr && addr !== active) {
          for (var id in root.items) { var it = root.items[id]; if (it.kind === "app" && it.windows) for (var i = 0; i < it.windows.length; i++) if (it.windows[i].address === addr && !root.launchPending[it.key]) root.requestAttention(it.key, 0) }
        }
      }
      if (n === "activewindowv2") {
        var aa = DockModel.normalizeAddress(String(ev.data || "").split(",")[0])
        for (var jd in root.items) { var jt = root.items[jd]; if (jt.kind === "app" && jt.windows) for (var j = 0; j < jt.windows.length; j++) if (jt.windows[j].address === aa) root.clearAttention(jd) }
      }
      if (n === "openwindow" || n === "closewindow" || n === "movewindow" || n === "movewindowv2" || n === "windowtitle" || n === "windowtitlev2"
          || n === "workspace" || n === "workspacev2" || n === "activewindow" || n === "activewindowv2" || n === "configreloaded") root.scheduleRebuild()
      if (n === "fullscreen" || n === "workspace" || n === "workspacev2" || n === "closewindow") Hyprland.refreshWorkspaces()
      if (n === "fullscreen") Hyprland.refreshToplevels()
    }
  }
  Connections {
    target: typeof DesktopEntries !== "undefined" ? DesktopEntries : null
    function onApplicationsChanged() { root.scheduleRebuild() }
  }
  Connections { target: root; function onTrashCountChanged() { root.scheduleRebuild() } }
  Connections { target: root; function onSettingsChanged() { root.scheduleRebuild() } }

  IpcHandler {
    target: "dock"
    function minimizeActive(): string { return root.minimizeActiveWindow(false) }
    function minimizeActiveSlow(): string { return root.minimizeActiveWindow(true) }
    function minimize(address: string): string { return root.minimizeWindow(DockModel.normalizeAddress(address), false, true) ? "ok" : "failed" }
    function restoreLast(): string { return root.restoreLast() }
    function restore(address: string): string { return root.restoreWindow(DockModel.normalizeAddress(address), false) ? "ok" : "failed" }
    function toggleAutoHide(): string { root.setSetting("autoHide", !root.autoHide); return root.autoHide ? "hidden" : "shown" }
    function focus(): string { return root.focusDock() }
    function toggle(): string { return root.toggleDock() }
    function probeOverlayLayer(on: string): string { root.overFullscreen = on === "true"; return String(root.overFullscreen) }
    function requestAttention(appId: string, repeat: int): string {
      var e = root.lookupEntry(appId); var key = root.keyFor(e, appId)
      root.requestAttention(key, repeat); return key
    }
    function setBadge(id: string, badge: string): string { root.setBadge(id, badge); return "ok" }
    function setPosition(pos: string): string { if (["left", "bottom", "right"].indexOf(pos) < 0) return "left|bottom|right"; root.setSetting("position", pos); return pos }
    function set(key: string, value: string): string {
      if (!(key in root.defaults)) return "unknown key"
      var v = value === "true" ? true : value === "false" ? false : (isFinite(Number(value)) && value !== "" ? Number(value) : value)
      try { if (typeof value === "string" && (value.charAt(0) === "[" || value.charAt(0) === "{")) v = JSON.parse(value) } catch (e) {}
      root.setSetting(key, v); return JSON.stringify(root.settings[key])
    }
    function openSettings(): string { root.settingsOpen = true; return "ok" }
    function rebuild(): string { root.rebuild(); return String(tiles.count) }
    function probeNoGrab(): string { root.testNoGrab = true; return "ok" }
    function probeFx(): string { var s = fx.snap; return JSON.stringify({ running: fx.running, progress: fx.progress, mode: fx.mode, strips: fx.stripCount, snap: s ? [s.width, s.height, s.hasContent] : null, win: fx.win, tile: fx.tile, target: fx.targetId, pending: root.pendingMinimize }) }
    function probeMenuState(): string { return JSON.stringify({ open: root.menuOpen, model: root.menuModel.length, x: menu.x, y: menu.y, w: menu.width, h: menu.height, visible: menu.visible, shown: menu.shown, opacity: menu.opacity, cardW: menu.cardW, cardH: menu.cardH, anchor: [menu.anchorMain, menu.anchorCross], settings: [settingsPanel.visible, settingsPanel.width, settingsPanel.height, settingsPanel.x, settingsPanel.y] }) }
    function state(): string {
      var rows = []
      for (var i = 0; i < tiles.count; i++) { var t = rep.itemAt(i); var it = root.items[tiles.get(i).itemId]; rows.push(tiles.get(i).itemId + (it && it.running ? "*" : "") + (it && it.gone ? "~" : "") + "@" + (t ? Math.round(t.main) + "/" + Math.round(t.visSize) : "?")) }
      return JSON.stringify({ position: root.position, tileSize: root.tileSize, bg: [Math.round(root.bgStart), Math.round(root.bgLength)], hidden: root.dockHidden, emptySpace: root.emptySpace, manualHidden: root.manualHidden, fullscreen: root.fullscreenActive, overFullscreen: root.overFullscreen, dark: root.dark, hover: root.hoverIndex, menu: root.menuOpen, stack: root.stackOpen, drag: root.dragging, rows: rows })
    }
    // Test hooks: drive the pointer without a real mouse.
    function probeHover(x: string, y: string): string { root.hovering = true; root.moveTo(Number(x), Number(y), false, 0); root.relayout(); return root.state ? "ok" : "ok" }
    function probeLeave(): string { root.hovering = false; root.relayout(); return "ok" }
    function probePress(x: string, y: string, button: string): string { root.pressAt(Number(x), Number(y), button === "right" ? Qt.RightButton : Qt.LeftButton, 0); return "ok" }
    function probeMove(x: string, y: string): string { root.moveTo(Number(x), Number(y), true, 0); return "ok" }
    function probeRelease(x: string, y: string): string { root.releaseAt(Number(x), Number(y), Qt.LeftButton); return "ok" }
    function probeMenu(index: int): string { root.openMenuFor(index); return "ok" }
    function probeStack(index: int): string { root.toggleStack(tiles.get(index).itemId); return "ok" }
    function probeLaunching(index: int): string { var it = root.items[tiles.get(index).itemId]; var lp = DockModel.copyMap(root.launchPending); lp[it.key] = Date.now(); root.launchPending = lp; root.rebuild(); return "ok" }
    function probeClose(): string { root.menuOpen = false; root.stackOpen = false; root.settingsOpen = false; root.kbMode = false; return "ok" }
    function probeReveal(): string { revealTimer.restart(); return "ok" }
    function probeKey(key: string): string { root.kbMode = true; if (key === "next") root.kbMove(1); else if (key === "prev") root.kbMove(-1); else if (key === "activate") root.activate(root.kbIndex); else if (key === "menu") root.openMenuFor(root.kbIndex); return String(root.kbIndex) }
  }

  // Login items (Options → Open at Login): once per login session.
  Process {
    id: loginCheck
    command: ["sh", "-c", "f=\"${XDG_RUNTIME_DIR:-/tmp}/henri-dock-login\"; if [ -e \"$f\" ]; then echo again; else touch \"$f\"; echo first; fi"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (String(text).trim() === "first") loginLaunch.restart() }
  }
  Timer {
    id: loginLaunch
    interval: 1500
    onTriggered: { var la = root.settings.loginApps || []; for (var i = 0; i < la.length; i++) { var e = root.lookupEntry(la[i]); if (e) try { e.execute() } catch (err) {} } }
  }
  Timer { id: startup; interval: 400; onTriggered: { Hyprland.refreshToplevels(); root.rebuild(); trashProc.running = true; trashWatch.running = true; loginCheck.running = true } }
  Component.onCompleted: { if (autoHide && !emptySpace) { hideOffset = 1; dockHidden = true }; startup.start() }
  onSettingsLoadedChanged: if (settingsLoaded) { position = String(settings.position || "bottom"); if (autoHide && !emptySpace) { hideOffset = 1; dockHidden = true } }

  // ======================================================== windows
  PanelWindow {
    id: overlay
    screen: root.screen
    color: "transparent"
    WlrLayershell.namespace: "henri-dock-overlay"
    WlrLayershell.layer: root.overFullscreen ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: root.kbMode ? WlrKeyboardFocus.Exclusive : (root.popupOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }

    readonly property bool captureAll: root.popupOpen || root.dragging || root.landing || root.resizing
    readonly property var zoneRect: {
      var visibleDock = !root.manualHidden && !(root.autoHide && root.dockHidden && !root.hovering)
      if (!visibleDock || root.bgLength <= 0) return { x: 0, y: 0, w: 0, h: 0 }
      var pad = root.gap + Style.space(4)
      return root.rectFor(root.bgStart + root.bgLength / 2, 0, root.bgLength + pad * 2, root.dockBaseline + root.maxVis + root.padCross)
    }
    readonly property var triggerRect: root.autoHide && root.dockHidden && !root.manualHidden
      ? root.rectFor(root.bgStart + root.bgLength / 2, 0, Math.max(root.bgLength, 200), Style.space(Apple.dock.triggerZone)) : { x: 0, y: 0, w: 0, h: 0 }

    mask: Region {
      x: overlay.captureAll ? 0 : overlay.zoneRect.x
      y: overlay.captureAll ? 0 : overlay.zoneRect.y
      width: overlay.captureAll ? plane.width : overlay.zoneRect.w
      height: overlay.captureAll ? plane.height : overlay.zoneRect.h
      regions: [
        Region { x: overlay.triggerRect.x; y: overlay.triggerRect.y; width: overlay.triggerRect.w; height: overlay.triggerRect.h }
      ]
    }

    FocusScope {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function (e) {
        if (e.key === Qt.Key_Alt) { root.altHeld = true; return }
        if (!root.kbMode) return
        var fwd = root.horizontal ? Qt.Key_Right : Qt.Key_Down
        var back = root.horizontal ? Qt.Key_Left : Qt.Key_Up
        var up = root.position === "bottom" ? Qt.Key_Up : root.position === "left" ? Qt.Key_Right : Qt.Key_Left
        if (root.popupOpen) { if (e.key === Qt.Key_Escape) { root.menuOpen = false; root.stackOpen = false; root.settingsOpen = false; e.accepted = true } return }
        if (e.key === fwd) { root.kbMove(1); e.accepted = true }
        else if (e.key === back) { root.kbMove(-1); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { root.activate(root.kbIndex); e.accepted = true }
        else if (e.key === up) { root.openMenuFor(root.kbIndex); e.accepted = true }
        else if (e.key === Qt.Key_Escape) { root.leaveKeyboard(); e.accepted = true }
      }
      Keys.onReleased: function (e) { if (e.key === Qt.Key_Alt) root.altHeld = false }

      Item {
        id: plane
        anchors.fill: parent
        Accessible.role: Accessible.ToolBar
        Accessible.name: "Dock"

        // A click anywhere else on the screen closes an open stack (its fan
        // has no surface of its own for HUi.Reveal's outside-click catcher).
        MouseArea {
          anchors.fill: parent
          z: -1
          enabled: root.stackOpen && !root.menuOpen && !root.settingsOpen
          acceptedButtons: Qt.AllButtons
          onPressed: root.closeStack()
        }

        // The strip along the screen edge that brings a hidden dock back: the
        // pointer has to rest on it for `autoHideDelay`.
        MouseArea {
          x: overlay.triggerRect.x; y: overlay.triggerRect.y
          width: overlay.triggerRect.w; height: overlay.triggerRect.h
          enabled: width > 0
          hoverEnabled: true
          acceptedButtons: Qt.NoButton
          onEntered: revealTimer.restart()
          onExited: revealTimer.stop()
        }

        // Off-screen vault for window snapshots (ShaderEffectSource reads them
        // as textures; the clip keeps them invisible).
        Item { id: vault; x: -10; y: -10; width: 1; height: 1; clip: true; visible: true }

        // Everything that slides away with auto-hide
        Item {
          id: dockLayer
          anchors.fill: parent
          transform: Translate { x: root.hideDX; y: root.hideDY }
          opacity: root.hideOpacity

          MouseArea {
            id: zone
            x: overlay.zoneRect.x; y: overlay.zoneRect.y
            width: overlay.zoneRect.w; height: overlay.zoneRect.h
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            pressAndHoldInterval: Motion.dock.longPress
            cursorShape: root.hoverSeparator && !root.dragging ? (root.horizontal ? Qt.SizeVerCursor : Qt.SizeHorCursor) : Qt.ArrowCursor
            onEntered: { root.hovering = true; hideTimer.stop(); root.kbMode = false }
            onExited: { if (!pressed) { root.hovering = false; root.invertMagnification = false; root.armAutoHide() } }
            onPositionChanged: function (mouse) { root.moveTo(zone.x + mouse.x, zone.y + mouse.y, pressed, mouse.modifiers) }
            onPressed: function (mouse) { root.pressAt(zone.x + mouse.x, zone.y + mouse.y, mouse.button, mouse.modifiers) }
            onReleased: function (mouse) { root.releaseAt(zone.x + mouse.x, zone.y + mouse.y, mouse.button); if (!containsMouse) { root.hovering = false; root.armAutoHide() } }
            onPressAndHold: root.longPress()
            onCanceled: { root.pressedIndex = -1; if (root.dragging) root.endDrag(); root.resizing = false }
          }

          DropArea {
            anchors.fill: parent
            keys: ["text/uri-list"]
            onEntered: function (drag) { root.externalMove(drag.x, drag.y, drag.hasUrls) }
            onPositionChanged: function (drag) { root.externalMove(drag.x, drag.y, drag.hasUrls) }
            onExited: root.externalLeave()
            onDropped: function (drop) { if (drop.hasUrls) { root.externalDrop(drop.urls); drop.accept() } else root.externalLeave() }
          }

          Repeater {
            id: rep
            model: tiles
            delegate: DockTile {
              dock: root
              main: root.centres[index] !== undefined ? root.centres[index] : root.mainLength / 2
              z: dragged ? 20 : 1
              // dragged tile: at the pointer (or gliding into its slot), lifted
              readonly property var dragRect: root.rectFor(root.ghostMain, root.ghostCross, visSize, visSize)
              x: dragged ? dragRect.x : r.x
              y: dragged ? dragRect.y : r.y
              opacity: dragged ? root.ghostOpacity : 1
              scale: dragged ? lift.value * root.ghostScale : 1
              transformOrigin: Item.Center
              HUi.SpringValue { id: lift; to: dragged && !root.landing && !root.reduceMotion ? Motion.liftScale : 1; preset: Motion.snappy; reduced: root.reduceMotion; epsilon: 0.002 }
            }
          }

          HoverLabel {
            id: hoverLabel
            dock: root
            readonly property var tile: root.dragging ? null : (root.hoverIndex >= 0 && !root.hoverSeparator ? rep.itemAt(root.hoverIndex) : null)
            readonly property var focusTile: root.kbMode ? rep.itemAt(root.kbIndex) : null
            readonly property var src: tile || focusTile
            text: root.removeMode ? "Remove" : (src && src.item ? src.item.name : text)
            shown: (root.removeMode) || ((root.hovering || root.kbMode) && src !== null && !root.popupOpen && !root.dragging && !root.resizing)
            anchorMain: root.dragging ? root.ghostMain : (src ? src.main : anchorMain)
            anchorCross: root.dragging ? root.ghostCross + root.tileSize + Style.space(Apple.dock.labelGap)
                                       : (src ? root.dockBaseline + src.visSize + Style.space(Apple.dock.labelGap) : anchorCross)
            z: 30
          }
        }

        MinimizeEffect {
          id: fx
          dock: root
          property string targetId: ""
          property string restoreAddress: ""
          property string restoreTarget: ""
          z: 40
          onProgressChanged: if (running && targetId) tile = root.tileUV(targetId)
          onFinished: {
            if (reverse && restoreAddress) { root.unparkWindow(restoreAddress, restoreTarget); restoreAddress = "" }
            root.effectTargetId = ""
            targetId = ""
            root.armAutoHide()
            root.layoutDirty()
          }
        }

        DockMenu {
          id: menu
          dock: root
          open: root.menuOpen
          model: root.menuModel
          z: 50
          onActivated: function (entry) { root.menuOpen = false; root.runMenuAction(entry); root.armAutoHide() }
          onDismissRequested: root.closeMenu()
        }

        StackPopup {
          id: stack
          dock: root
          open: root.stackOpen
          z: 45
          onDismissRequested: root.closeStack()
          onOpenEntry: function (entry) { root.closeStack(); if (entry) Quickshell.execDetached(["xdg-open", entry.path]) }
          onOpenFolder: { var f = stack.folder; root.closeStack(); if (f) root.openInFileManager(f.path) }
        }

        SettingsPanel {
          id: settingsPanel
          dock: root
          open: root.settingsOpen
          z: 55
          onDismissRequested: { root.settingsOpen = false; root.armAutoHide() }
        }
      }
    }
  }

  PanelWindow {
    id: bgWindow
    screen: root.screen
    color: "transparent"
    WlrLayershell.namespace: "henri-dock"
    WlrLayershell.layer: root.overFullscreen ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Normal
    // Nothing is reserved before the settings are read: a zone that is taken
    // back during startup stays behind in Hyprland as dead space under the windows.
    exclusiveZone: !root.settingsLoaded || root.autoHide || root.manualHidden ? 0 : Math.round(root.bgThickness)
    anchors {
      bottom: root.position === "bottom" || !root.horizontal
      top: !root.horizontal
      left: root.position !== "right"
      right: root.position !== "left"
    }
    implicitHeight: root.horizontal ? Math.round(root.bgThickness) : 100
    implicitWidth: root.horizontal ? 100 : Math.round(root.bgThickness)
    mask: Region {}

    Item {
      id: bgLayer
      anchors.fill: parent
      transform: Translate { x: root.hideDX; y: root.hideDY }
      opacity: root.hideOpacity
      readonly property var r: root.rectFor(root.bgStart + root.bgLength / 2, root.edgeGap, root.bgLength, root.tileSize + root.padCross * 2, width, height)

      Rectangle {
        // shadow plate (0 10px 30px): a soft dark plate under the sheet
        x: bgSheet.x - Style.space(2); y: bgSheet.y + Style.space(3)
        width: bgSheet.width + Style.space(4); height: bgSheet.height
        radius: bgSheet.radius + Style.space(2)
        color: root.palette.shadow
        opacity: 0.5
      }
      Rectangle {
        id: bgSheet
        x: bgLayer.r.x; y: bgLayer.r.y; width: bgLayer.r.w; height: bgLayer.r.h
        radius: root.cornerRadius
        color: Motion.glass ? root.palette.sheet : root.palette.opaque
        border.width: 1
        border.color: root.palette.hairline
        antialiasing: true
        Behavior on color { ColorAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
        Rectangle {
          anchors.fill: parent; anchors.margins: 1
          radius: parent.radius - 1
          color: "transparent"
          border.width: 1
          border.color: root.palette.border
          antialiasing: true
        }
      }
    }
  }
}
