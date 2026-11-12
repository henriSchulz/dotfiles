import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "file:///home/henri/.local/share/velum/qml/Velum"
import "HomeModel.js" as HM
import "MaterialModel.js" as MM
import "switcher"
import "widgets"
import "widgets/Widgets.js" as W

// Tablet mode's home screen and home gesture (henri.tablet-v4). The home screen is the Material lab
// (lab/mui-material) native: MaterialHome.qml, its values surface.material, Roboto from fonts/, with
// the lab's search view (SearchView.qml: the search bar, or a key typed while the home shows), All
// apps (AppDrawer.qml: a swipe up on the grid), the widgets (widgets/: Photos, Battery, Clock, Tablet,
// the picker from the wallpaper's menu) and the App Switcher (switcher/MaterialSwitcher.qml).
// Gesture navigation (switcher/NavGesture.qml's rule) on the home screen: a finger up from the bottom
// strip brings the App Switcher with it, let go past nav.travel it stays, a quick flick goes home only
// when there is a way home (something open, another page). Over an app the home gesture is still
// v3's (as on an iPad, lab/web/home.html), except that "pull and pause" hands over to the Material
// App Switcher instead of v3's cards:
//
// The home screen is an empty workspace: a bottom-layer surface draws the app grid and the dock
// (MaterialHome.qml) wherever the focused workspace has no window. The home gesture runs on an
// overlay over the app area: the app becomes a card (a one-time snapshot of its window, Card.qml)
// that follows the finger over the home screen; released it goes into its icon, pauses into the
// App Switcher, or springs back. Workspace changes happen underneath while the overlay covers the
// area, so their slide is never seen, and the overlay lets go once the compositor shows the same
// picture. Nothing re-renders while a card moves: only transform and opacity change.
//
// Tablet.qml feeds it: prepare(screen) when a finger lands in the home zone, then lift / arm /
// release from Gesture.js.
Item {
  id: home

  property bool active: false
  property var dispatch: function (lua, legacy) {}
  readonly property var tt: Theme.core.surface.tablet
  readonly property var cfg: tt.home
  readonly property string homeDir: Quickshell.env("HOME")
  readonly property bool inRig: (Quickshell.env("VELUM_SHELL_RIG") || "") !== ""

  // Roboto for the Material home screen (fonts/, Apache 2.0 / OFL, from google/fonts): registered
  // once for the whole shell, MText asks for the family by name
  FontLoader { source: Qt.resolvedUrl("fonts/Roboto-Regular.ttf") }
  FontLoader { source: Qt.resolvedUrl("fonts/Roboto-Medium.ttf") }
  FontLoader { source: Qt.resolvedUrl("fonts/Roboto-Bold.ttf") }
  FontLoader { source: Qt.resolvedUrl("fonts/Roboto-Light.ttf") }
  readonly property var mt: Theme.core.surface.material

  // for tests: what happened last
  property var log: []
  function note(s) { var l = log.slice(-19); l.push(s); log = l }

  // ================================================================ apps
  property var entries: ({})     // desktop id → { id, name, icon }
  property var appIds: []        // sorted by name, hidden ones left out
  property var pinnedIds: []
  property var systemHidden: ({})
  readonly property string omarchyBase: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  FileView {
    path: home.homeDir + "/.config/omarchy/dock.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var list = []
      try { var p = JSON.parse(text()); list = Array.isArray(p) ? p : (p && Array.isArray(p.pinned) ? p.pinned : []) } catch (e) {}
      home.pinnedIds = list.map(function (s) { return String(s).replace(/\.desktop$/, "") })
    }
    onFileChanged: reload()
  }
  property string configuredHides: ""
  FileView {
    path: home.omarchyBase + "/default/omarchy/launcher.hides"
    printErrors: false
    onLoaded: { home.configuredHides = text(); hidesScan.running = true }
    onLoadFailed: { home.configuredHides = ""; hidesScan.running = true }
  }
  Process {
    id: hidesScan
    command: ["bash", home.omarchyBase + "/shell/services/hidden-entries.sh",
      [Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")].filter(function (v) { return String(v || "").length > 0 }).join(":")]
    stdout: StdioCollector { onStreamFinished: home.applyHides(text) }
    onExited: function (code) { if (code !== 0) home.applyHides("") }
  }
  // the home screen's own list (home.hides) and categories: developer and system tools stay in
  // the launcher, not on the home screen
  readonly property var hiddenCategories: ["Development", "Debugger", "IDE", "ConsoleOnly"]
  property var homeHidden: ({})
  function idSet(text) {
    var next = {}, lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var id = lines[i].trim().replace(/\.desktop$/, "")
      if (id && id.charAt(0) !== "#") next[id] = true
    }
    return next
  }
  FileView {
    path: Qt.resolvedUrl("home.hides").toString().replace(/^file:\/\//, "")
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { home.homeHidden = home.idSet(text()); home.scanApps() }
  }
  function homeHides(e, id) {
    if (home.localHidden[id]) return true
    if (home.localShown[id]) return false     // put on the home screen from All apps (Add to Home)
    if (home.homeHidden[id]) return true
    var cats = []
    try { cats = e.categories || [] } catch (err) {}
    for (var i = 0; i < cats.length; i++) if (home.hiddenCategories.indexOf(String(cats[i])) >= 0) return true
    return false
  }
  function applyHides(scanned) {
    var next = {}, lines = (home.configuredHides + "\n" + scanned).split("\n")
    for (var i = 0; i < lines.length; i++) {
      var id = lines[i].trim().replace(/\.desktop$/, "")
      if (id && id.charAt(0) !== "#") next[id] = true
    }
    home.systemHidden = next
    home.scanApps()
  }
  function iconOf(value) {
    value = String(value || "")
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    return (value ? Quickshell.iconPath(value, true) : "") || Quickshell.iconPath("application-x-executable", true)
  }
  function scanApps() {
    var values = []
    try { values = DesktopEntries.applications.values || [] } catch (e) {}
    var map = {}, list = []
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      if (!e || e.noDisplay) continue
      var id = String(e.id || "").replace(/\.desktop$/, "")
      if (!id || map[id] || home.systemHidden[id]) continue
      var cats = []
      try { cats = (e.categories || []).map(String) } catch (err) {}
      var cmd = []
      try { cmd = (e.command || []).map(String) } catch (err) {}
      // the entry's own actions (Chromium's New Incognito Window …): rows of the icon's context menu
      var acts = []
      try { acts = (e.actions || []).map(function (a) { return { id: String(a.id || ""), name: String(a.name || a.id || ""), command: (a.command || []).map(String) } }) } catch (err) {}
      map[id] = { id: id, name: String(e.name || id), icon: home.iconOf(e.icon), cats: cats, command: cmd, actions: acts }
      if (!home.homeHides(e, id)) list.push(id)
    }
    list.sort(function (a, b) { return map[a].name.localeCompare(map[b].name) })
    home.entries = map
    home.appIds = list
  }
  Connections { target: DesktopEntries.applications; function onValuesChanged() { appsDebounce.restart() } }
  Timer { id: appsDebounce; interval: Theme.delay("settle"); onTriggered: home.scanApps() }
  // the hotseat (Launcher3): saved in home-layout.json "hotseat", until then the Dock's pinned apps
  // (dock.json is the desktop Dock's and never written here); any known app (also one the grid leaves
  // out by category), not one this machine removed, at most hotseatMax. An app is in one place only.
  property var savedHotseat: null
  readonly property var hotseatIds: {
    var known = {}
    for (var id in entries) if (!localHidden[id]) known[id] = true
    return MM.arrangeHotseat(savedHotseat, pinnedIds, known, mt.grid.hotseatMax)
  }
  readonly property var dockApps: hotseatIds.map(function (id) { return entries[id] }).filter(Boolean)
  // filter(Boolean): scanApps sets entries before appIds, so for one evaluation an id of the old
  // list can miss in the new map (an app removed, a rescan) — "Value is undefined" at layout
  readonly property var gridApps: appIds.filter(function (id) { return hotseatIds.indexOf(id) < 0 }).map(function (id) { return entries[id] }).filter(Boolean)
  // the grid: what edit mode saved (order + folders), new apps after it (HM.arrangeLayout)
  property var savedOrder: []
  property var savedFolders: ({})
  // widgets (widgets/, kinds and spans in Widgets.js / surface.material.widgets.cells): an order entry
  // each, the app a tap opens. Photos is there unless removed (phase 1: one the saved order does not
  // know yet starts at the top left of the first page, as iPadOS puts a new widget); the others only
  // once the picker added them (they are in the saved order then).
  // `open`: the app's arguments that show the widget's item (the photo on it)
  readonly property var knownWidgets: {
    var o = {}
    for (var i = 0; i < W.kinds.length; i++) o["widget:" + W.kinds[i][0]] = { name: W.kinds[i][1] }
    o["widget:photos"] = { name: "Photos", app: "de.henri.IcloudPhotos", open: ["--open"] }
    return o
  }
  function spanOf(id) { return HM.isWidget(id) ? W.span(mt.widgets.cells, id.slice(7)) : [1, 1] }
  // what this machine's home screen leaves out, apps and widgets (home-layout.json "hidden"): the
  // layout belongs to the machine, home.hides to every machine. The launcher and Spotlight still find the apps.
  property var localHidden: ({})
  // apps the home screen would leave out (home.hides, a category) that All apps' Add to Home put there
  // (home-layout.json "shown")
  property var localShown: ({})
  readonly property var widgets: {
    var out = {}
    for (var w in knownWidgets) if (!localHidden[w] && (w === "widget:photos" || savedOrder.indexOf(w) >= 0)) out[w] = knownWidgets[w]
    return out
  }
  function openWidget(id, item) {
    var w = widgets[id]
    if (!w || !entries[w.app]) return
    guard("openApp", function () { home.openApp(w.app, item && w.open ? w.open.concat([item]) : [], id) })
  }
  readonly property var layout: {
    var ids = Object.keys(widgets).concat(gridApps.map(function (a) { return a.id }))
    var saved = savedOrder.slice()
    for (var w in widgets) if (saved.indexOf(w) < 0) saved.unshift(w)
    var l = HM.arrangeLayout(ids, saved, savedFolders)
    return { order: l.order, folders: l.folders, hotseat: hotseatIds.slice() }
  }
  readonly property var gridOrder: layout.order
  readonly property int gridPages: HM.pageCount(HM.place(gridOrder, home.spanOf, home.mt.grid.cols, home.mt.grid.rows))
  property bool editing: false      // v4 has no edit mode (Launcher3); kept for the IPC
  property string openFolder: ""   // "folder:…" open on the home screen
  // the home screen's tiles: apps and folders (with their apps). A new list only when tiles come,
  // go or a folder changes — a new order only moves them (MaterialHome keeps a tile whose key stays)
  property var gridTiles: []
  property string tilesKey: ""
  // each with a `key` that changes with what it shows: MaterialHome's Repeater keeps a tile whose key
  // stays and builds only the new ones
  function syncTiles() {
    var l = home.layout, tiles = []
    for (var w in widgets) tiles.push({ key: w, id: w, name: widgets[w].name, widget: w.slice(7) })
    for (var i = 0; i < gridApps.length; i++) {
      var a = gridApps[i]
      if (!HM.folderOf(l.folders, a.id)) tiles.push({ key: a.id + "|" + a.name + "|" + a.icon, id: a.id, name: a.name, icon: a.icon })
    }
    for (var k in l.folders) {
      var f = l.folders[k], items = f.items.map(function (id) { return home.entries[id] }).filter(Boolean)
      tiles.push({ key: "folder:" + k + "|" + f.name + "|" + items.map(function (x) { return x.id + x.icon }).join(","), id: "folder:" + k, name: f.name, folder: true, items: items })
    }
    var key = JSON.stringify(tiles.map(function (t) { return t.key }))
    if (layoutRead) VBoot.release("home")
    if (key === tilesKey) return
    tilesKey = key
    gridTiles = tiles
    VBoot.poke()
  }
  // The shell's start (VBoot): the home screen holds the entrance until its layout is read and its
  // tiles stand, then comes in as from the home gesture — the grid zooms down from homeZoom and
  // fades in, the dock rises (reduced motion: a fade)
  property bool layoutRead: false
  Spring { id: bootIn; preset: Theme.spring("gentle"); target: VBoot.chrome ? 1 : 0 }
  onRecentAppsChanged: VBoot.poke()
  onDockAppsChanged: VBoot.poke()
  // a folder whose last app went (removed from the home screen) closes
  onLayoutChanged: { syncTiles(); if (openFolder && !layout.folders[HM.folderKey(openFolder)]) openFolder = "" }
  onOpenFolderChanged: if (openFolder && !layout.folders[HM.folderKey(openFolder)]) openFolder = ""
  FileView {
    id: layoutFile
    path: (Quickshell.env("XDG_STATE_HOME") || (home.homeDir + "/.local/state")) + "/velum/home-layout.json"
    printErrors: false
    onLoaded: {
      var d = {}
      try { d = JSON.parse(text()) } catch (e) {}
      home.savedFolders = d.folders && typeof d.folders === "object" ? d.folders : {}
      home.savedOrder = Array.isArray(d.order) ? d.order : []
      home.savedHotseat = Array.isArray(d.hotseat) ? d.hotseat.map(String) : null
      home.localHidden = home.idSet(Array.isArray(d.hidden) ? d.hidden.join("\n") : "")
      home.localShown = home.idSet(Array.isArray(d.shown) ? d.shown.join("\n") : "")
      home.layoutRead = true
      home.scanApps()
    }
    onLoadFailed: { home.layoutRead = true; home.syncTiles() }
  }
  // { order, folders, hotseat? } — a layout without a hotseat keeps the saved one
  function saveLayout(l) {
    home.savedFolders = l.folders
    home.savedOrder = l.order.slice()
    if (Array.isArray(l.hotseat)) home.savedHotseat = l.hotseat.slice()
    var hidden = Object.keys(home.localHidden), shown = Object.keys(home.localShown)
    layoutFile.setText(JSON.stringify({ order: home.savedOrder, folders: home.savedFolders, hidden: hidden.length ? hidden : undefined,
                                        hotseat: home.savedHotseat === null ? undefined : home.savedHotseat,
                                        shown: shown.length ? shown : undefined }, null, 1) + "\n")
  }
  function saveOrder(ids) { saveLayout({ order: ids, folders: home.layout.folders }) }
  // Removed from this machine's home screen (MaterialHome: dropped on Remove, or a folder's Remove
  // folder): apps (a folder's with it), widgets — saved in home-layout.json "hidden", the launcher and
  // Spotlight still find the apps. The layout before is kept for the snackbar's Undo (Launcher3).
  property var undoState: null
  property var snack: null              // { text, undo }: the snackbar of every home screen
  Timer { id: snackTimer; interval: home.mt.time.undo; onTriggered: { home.snack = null; home.undoState = null } }
  function showSnack(text, undo) { snack = { text: text, undo: !!undo }; snackTimer.restart() }
  function hideItems(ids, name) {
    var apps = ids.filter(function (id) { return !HM.isFolder(id) && !HM.isBreak(id) })
    if (!apps.length) return
    undoState = { order: savedOrder.slice(), folders: JSON.parse(JSON.stringify(savedFolders)), hidden: Object.assign({}, localHidden),
                  hotseat: savedHotseat === null ? null : savedHotseat.slice() }
    var next = Object.assign({}, localHidden)
    for (var i = 0; i < apps.length; i++) next[apps[i]] = true
    note("remove " + ids.join(","))
    localHidden = next
    saveLayout({ order: savedOrder, folders: savedFolders })
    scanApps()
    showSnack(name + " removed", true)
  }
  function undo() {
    var u = undoState
    if (!u) return
    note("undo")
    undoState = null
    snack = null
    localHidden = u.hidden
    savedHotseat = u.hotseat
    saveLayout({ order: u.order, folders: u.folders })
    scanApps()
  }
  // ---- All apps' Add to Home and the widget picker's add (the lab's onAdd): an app already on the home
  // screen (grid, folder, hotseat) only says so; otherwise it comes back from "hidden" (and past
  // home.hides / the categories the grid leaves out: "shown"), goes after the last item (page breaks
  // normalised: onto the last page while it has room, else a new one) and the home screen turns to its page
  function isOnHome(id) {
    if (hotseatIds.indexOf(id) >= 0 || layout.order.indexOf(id) >= 0) return true
    return !!HM.folderOf(layout.folders, id)
  }
  function homeIdMap() {
    var o = {}, ord = layout.order
    for (var i = 0; i < ord.length; i++) if (!HM.isFolder(ord[i]) && !HM.isBreak(ord[i]) && !HM.isWidget(ord[i])) o[ord[i]] = true
    for (var k in layout.folders) for (var j = 0; j < layout.folders[k].items.length; j++) o[layout.folders[k].items[j]] = true
    for (var h = 0; h < hotseatIds.length; h++) o[hotseatIds[h]] = true
    return o
  }
  function addToHome(id, screenName) {
    var e = entries[id]
    if (!e) return
    note("add " + id)
    if (isOnHome(id)) { showSnack(e.name + " is on the Home screen"); return }
    var hid = Object.assign({}, localHidden), sh = Object.assign({}, localShown)
    delete hid[id]
    localHidden = hid
    var order = layout.order.filter(function (x) { return x !== id }).concat([id])
    savedOrder = HM.normalizeBreaks(order)
    scanApps()
    // still left out (home.hides, a category): shown on purpose
    if (appIds.indexOf(id) < 0) { sh[id] = true; localShown = sh; scanApps() }
    saveLayout({ order: HM.normalizeBreaks(order), folders: savedFolders })
    showSnack(e.name + " added to the Home screen")
    showItem(id, screenName)
  }
  function addWidget(kind, screenName) {
    var id = "widget:" + kind, w = knownWidgets[id]
    if (!w) return
    note("add widget " + kind)
    if (widgets[id] && layout.order.indexOf(id) >= 0) { showSnack(w.name + " is on the Home screen"); return }
    var hid = Object.assign({}, localHidden)
    delete hid[id]
    localHidden = hid
    savedOrder = HM.normalizeBreaks(layout.order.filter(function (x) { return x !== id }).concat([id]))
    saveLayout({ order: savedOrder, folders: savedFolders })
    showItem(id, screenName)
  }
  // the page an item landed on, once the home screen has its tiles
  function showItem(id, screenName) {
    Qt.callLater(function () {
      var h = home.screenHomes[screenName || home.screenName] || home.screenHomes[Object.keys(home.screenHomes)[0]]
      var r = h ? h.item.tileRect(id, 0) : null
      if (r) home.showPage(r.page, h.item.pages)
    })
  }
  function showPage(p, pages) {
    pageCount = Math.max(pages || 1, p + 1)
    if (p === page && Math.abs(pageV.value + p * areaW) < 1) return
    page = p
    pageV.velocity = 0
    pageV.target = -page * areaW
  }

  // ---- the search view (SearchView.qml on the home screen's window): the search bar, or a key typed
  // while the home screen shows (initial = that key). A tap also asks for the on-screen keyboard, as
  // the window bar's search does.
  function search(screenName, initial) {
    var h = screenHomes[screenName]
    if (!h) return
    note("search" + (initial ? " " + initial : ""))
    if (h.drawer.active) h.drawer.close()
    h.search.open(initial || "", h.barRect())
    if (!initial) dispatch("hl.dsp.event(\"velum-keyboard open " + screenName + "\")", "event velum-keyboard open " + screenName)
  }
  function launches() { return !inRig || (Quickshell.env("VELUM_TABLET_LAUNCH") || "") !== "" }
  function searchAction(id, action) {
    note("search action " + id + " " + (action ? action.id : ""))
    var cmd = action && action.command && action.command.length ? ["uwsm-app", "--"].concat(action.command) : ["uwsm-app", "--", "gtk-launch", id + ".desktop"]
    openApp(id, [], id, cmd)
  }
  // the default browser with the query (xdg-open); in a rig only noted unless it may launch
  readonly property string webSearchUrl: "https://www.google.com/search?q="
  function webSearch(text) {
    var url = webSearchUrl + encodeURIComponent(String(text || "").trim())
    note("web " + url)
    if (launches()) Quickshell.execDetached(["uwsm-app", "--", "xdg-open", url])
  }

  // ---- the App Switcher (switcher/MaterialSwitcher.qml, on the gesture overlay of the gesture's
  // screen) and gesture navigation. swProgress / swDragging drive it; NavGesture (no surface of its
  // own here: Tablet.qml's home zone takes the finger and draws the handle) decides on the home screen.
  property real swProgress: 0
  property bool swDragging: false
  property var switcherItem: null        // the gesture screen's MaterialSwitcher
  readonly property bool swOpen: swProgress > 0 || (switcherItem !== null && switcherItem.open)
  NavGesture {
    id: navG
    visible: false
    enabled: false
    handleVisible: false
    screenHeight: home.areaH
    wayHome: home.wayHome(home.screenName)
    onOpenSwitcher: { home.swDragging = false; home.swProgress = 1; home.note("nav switcher") }
    onSank: { home.swDragging = false; home.swProgress = 0; home.note("nav back") }
    onHome: { home.swDragging = false; home.swProgress = 0; home.note("nav home"); home.homeLocal(home.screenName) }
  }
  readonly property var navCfg: mt.switcher.nav
  // the handle rises a little with the finger (Tablet.qml springs it back)
  readonly property real navRise: navG.dragging ? Math.min(navG.travel, navCfg.travel) * navCfg.handleRise : 0
  // the lab's rule: a flick goes home only when there is a way home — something open over the grid,
  // or another page than the first (not the switcher the finger itself brings: a flick that stands it
  // open is handled by the home zone while it is open, swZone)
  function wayHome(screenName) {
    var h = screenHomes[screenName]
    if (!h) return page !== 0
    return page !== 0 || h.search.shown || h.drawer.active || h.picker.open || openFolder !== "" || h.item.menuOpen
  }
  // home on the home screen: close what is open, the first page
  function homeLocal(screenName) {
    var h = screenHomes[screenName]
    if (h) { h.search.close(); h.drawer.close(); h.picker.open = false; h.item.menuOpen = false }
    openFolder = ""
    showPage(0, pageCount)
  }
  function navMove(up) {
    if (!navG.dragging) { navG.begin(0); swDragging = true; note("nav") }
    navG.update(-Math.max(0, up))
    swProgress = navG.pull
  }
  function navEnd(kind) {
    if (!navG.dragging) return
    if (kind === "cancel") navG.abort(); else navG.end()
  }
  // over an app, the v3 card let go into "the switcher": the Material one takes over — it rises over
  // the card, the card fades under its backdrop, then the overlay lets go of the card
  function toMaterialSwitcher(hand) {
    note("material switcher")
    // the app's card and its neighbours hand themselves to the Material switcher where they rest (one
    // movement into the row); windows without a card fade in there
    var c = card(cur), e = cards[cur]
    dimV.target = 0; labelV.target = 0
    swDragging = false
    swProgress = 1
    if (c && e && switcherItem) {
      // the neighbour cards still showing go along, each from where it stands
      var others = []
      for (var j = 0; j < cards.length; j++) {
        var n = card(j)
        if (j === cur || !n || n.po < cfg.nearScale) continue
        others.push({ address: cards[j].address, rect: n.mapToItem(switcherItem, 0, 0, n.width, n.height) })
      }
      switcherItem.takeHand(c.mapToItem(switcherItem, 0, 0, c.width, c.height), e.address, others)
    }
    else for (var i = 0; i < cards.length; i++) { var o = card(i); if (o) o.to("o", 0, "snappy") }
    settleWhen(function () { var c = home.card(home.cur); return (!c || c.near(["o"])) && (!home.switcherItem || home.switcherItem.shown >= 1 - home.cfg.nearScale) }, "idle", false)
  }
  function openMaterialSwitcher(screenName) {
    if (screenName) home.screenName = screenName
    swDragging = false
    swProgress = 1
  }
  function switchToWindow(address) {
    note("switch " + address)
    swDragging = false
    swProgress = 0
    appSwitchAt = Date.now()
    dispatch("hl.dsp.focus({ window = \"address:" + address + "\" })", "focuswindow address:" + address)
  }
  function closeWindow(address) {
    note("close window " + address)
    dispatch("hl.dsp.window.close({ window = \"address:" + address + "\" })", "closewindow address:" + address)
  }

  // ---- for the tests (IPC homeFind / homeProbe): a named point of the integrated parts, screen coordinates
  //   drawer:ID (an app's cell in All apps), drawermenu:KEY (add | info), picker:KIND, switcher:I (card i)
  function findChild(it, test) {
    var kids = it.children || []
    for (var i = 0; i < kids.length; i++) {
      if (test(kids[i])) return kids[i]
      var f = findChild(kids[i], test)
      if (f) return f
    }
    if (it.contentItem && kids.indexOf(it.contentItem) < 0) return findChild(it.contentItem, test)
    return null
  }
  function findPoint(screenName, what) {
    var h = screenHomes[screenName]
    if (!h) return null
    var s = String(what), i = s.indexOf(":"), kind = i < 0 ? s : s.slice(0, i), arg = i < 0 ? "" : s.slice(i + 1), top = h.top(), p = null
    if (kind === "drawer") {
      var g = findChild(h.drawer, function (c) { return c.cellWidth !== undefined })
      var n = h.drawer.list.map(function (a) { return a.id }).indexOf(arg)
      if (!g || n < 0) return null
      var cols = Math.max(1, h.drawer.columns)
      p = g.mapToItem(null, (n % cols) * g.cellWidth + g.cellWidth / 2, Math.floor(n / cols) * g.cellHeight + g.cellHeight / 2 - g.contentY)
    } else if (kind === "drawermenu") {
      var m = findChild(h.drawer, function (c) { return c.cardX !== undefined && c.tiles !== undefined })
      if (!m || !m.shown) return null
      var c = mt.drawer.menu, at = m.tiles.map(function (t) { return t.key }).indexOf(arg)
      if (at < 0) return null
      var w = (m.cardW - 2 * c.pad - (m.tiles.length - 1) * c.tileGap) / m.tiles.length
      p = m.mapToItem(null, m.cardX + c.pad + at * (w + c.tileGap) + w / 2, m.cardY + m.cardH - c.pad - c.tile / 2)
    } else if (kind === "picker") {
      var t = findChild(h.picker, function (x) { return x.kind === arg && x.there !== undefined })
      if (!t) return null
      p = t.mapToItem(null, t.width / 2, t.height / 2)
    } else if (kind === "switcher") {
      var si = switcherItem ? switcherItem.info() : null, k = Number(arg)
      if (!si || !si.open || k < 0 || k >= si.n) return null
      return { x: Math.round(areaW / 2 + (k - (si.n - 1)) * si.step + si.offset), y: Math.round(areaH / 2) }
    }
    return p ? { x: Math.round(p.x), y: Math.round(p.y + top) } : null
  }
  function integratedProbe(screenName) {
    var h = screenHomes[screenName]
    if (!h) return null
    var r = h.search.results
    return {
      search: { shown: h.search.shown, text: h.search.text, first: r.first ? r.first.kind + ":" + (r.first.app ? r.first.app.id : r.first.text) : null, last: h.search.lastActivated },
      drawer: { active: h.drawer.active, position: +h.drawer.position.toFixed(3), dragging: h.drawer.dragging, menu: h.drawer.menuOpen, last: h.drawer.lastActivated, count: h.drawer.list.length, ids: h.drawer.list.map(function (a) { return a.id }) },
      picker: { open: h.picker.open },
      switcher: { progress: swProgress, dragging: swDragging, open: swOpen, info: switcherItem ? switcherItem.info() : null, nav: navG.last, wayHome: wayHome(screenName) },
      widgets: Object.keys(widgets), page: page, keys: h.keys()
    }
  }

  // a new folder's name, from the categories its apps share (iPadOS names it by the App Store's)
  readonly property var folderNames: [["Office", "Office"], ["Graphics", "Creativity"], ["AudioVideo", "Entertainment"],
    ["Game", "Games"], ["Education", "Education"], ["Network", "Social"], ["Utility", "Utilities"], ["System", "Utilities"]]
  function foldApps(id, target) {
    var ids = HM.isFolder(target) ? [id] : [id, target]
    var name = HM.folderName(ids.map(function (a) { return (home.entries[a] || {}).cats || [] }), home.folderNames, "Folder")
    saveLayout(HM.fold(home.layout, id, target, name))
  }
  function renameFolder(key, name) {
    var l = home.layout
    if (!l.folders[key]) return
    var folders = HM.copyFolders(l.folders)
    folders[key].name = name
    note("rename " + key + " " + name)
    saveLayout({ order: l.order, folders: folders })
  }
  // a held icon resting at a side: the next page, as a release with no speed would settle
  function turnPage(dir) {
    var to = Math.max(0, Math.min(pageCount - 1, page + dir))
    if (to === page) return
    page = to
    pageV.velocity = 0
    pageV.target = -page * areaW
  }

  // running apps not in the dock, newest first
  readonly property var recentApps: {
    var out = [], seen = {}, ws = windows
    for (var i = ws.length - 1; i >= 0 && out.length < cfg.dockRecents; i--) {
      var id = ws[i].appId
      if (!id || seen[id] || pinnedIds.indexOf(id) >= 0 || !entries[id]) continue
      seen[id] = true
      out.push(entries[id])
    }
    return out
  }

  // apps with a window: a dot under their dock icon
  readonly property var runningApps: {
    var o = {}
    for (var i = 0; i < windows.length; i++) if (windows[i].appId) o[windows[i].appId] = true
    return o
  }
  readonly property string wallpaperSource: "file://" + wallpaperLink + (wallpaperTarget ? "?v=" + encodeURIComponent(wallpaperTarget) : "")

  // the desktop entry of a window class (only a real match; heuristicLookup guesses wide)
  function appIdOf(cls) {
    if (!cls) return ""
    if (entries[cls]) return cls
    var e = null
    try { e = DesktopEntries.byId(cls) || DesktopEntries.heuristicLookup(cls) } catch (err) {}
    var id = e ? String(e.id || "").replace(/\.desktop$/, "") : ""
    return id
  }

  // ================================================================ windows
  // the apps on a screen, oldest first (one per workspace in tablet mode); dialogs and special
  // workspaces left out
  property var windows: []
  function scanWindows(screenName) {
    var mon = monitorOf(screenName), out = []
    var tl = Hyprland.toplevels.values
    for (var i = 0; i < tl.length; i++) {
      var t = tl[i], o = t.lastIpcObject
      // named workspaces have negative ids too: the cast screen HEADLESS-SPARE shows "spare" while no
      // monitor is there (2026-10-28: every pull on it ended "not dragging"); only special ones stay out
      if (!o || !o.workspace || String(o.workspace.name || "").indexOf("special:") === 0 || o.floating || !o.mapped) continue
      if (mon && o.monitor !== mon.id) continue
      var id = appIdOf(o.class), e = entries[id]
      out.push({ key: String(o.address), address: String(o.address), toplevel: t, workspace: o.workspace.id, appId: id, order: i,
                 icon: e ? e.icon : iconOf(o.class), name: e ? e.name : String(o.title || o.class || ""),
                 focus: typeof o.focusHistoryID === "number" ? o.focusHistoryID : 1000 })
    }
    out.sort(function (a, b) { return b.focus - a.focus })
    windows = out
    return out
  }
  function monitorOf(screenName) {
    var mons = Hyprland.monitors.values
    for (var i = 0; i < mons.length; i++) if (mons[i].name === screenName) return mons[i]
    return null
  }
  // no app on the screen's active workspace (from the toplevels' own IPC objects: a workspace's
  // toplevel list can lag behind a move)
  function emptyOn(screenName) {
    var m = monitorOf(screenName)
    if (!m || !m.activeWorkspace) return false
    // the workspace's own count first (refreshed with the workspaces), then the toplevels
    var ipc = m.activeWorkspace.lastIpcObject
    if (ipc && typeof ipc.windows === "number" && ipc.windows === 0) return true
    var id = m.activeWorkspace.id, tl = Hyprland.toplevels.values
    for (var i = 0; i < tl.length; i++) {
      var o = tl[i].lastIpcObject
      if (o && o.workspace && o.workspace.id === id && o.mapped !== false) return false
    }
    return true
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var n = event.name
      if (n === "openwindow" && home.launchedId) home.launchOpened = true
      if (n === "openwindow" || n === "closewindow" || n === "movewindow" || n === "movewindowv2" || n === "workspacev2") refreshSoon.restart()
    }
  }
  Timer { id: refreshSoon; interval: Theme.dur("fast"); onTriggered: { Hyprland.refreshMonitors(); Hyprland.refreshToplevels(); Hyprland.refreshWorkspaces(); rescan.restart() } }
  // the IPC objects arrive after the refresh; then the dock's recent apps follow
  Timer {
    id: rescan
    interval: Theme.dur("fast")
    onTriggered: {
      if (home.mode !== "idle" && home.mode !== "home") return
      if (!home.screenName && Quickshell.screens[0]) home.screenName = Quickshell.screens[0].name
      home.cards = home.scanWindows(home.screenName)
      // left the home screen another way (a sideways swipe, a launched app): it is no longer ours
      if (home.mode === "home" && !home.emptyOn(home.screenName)) home.mode = "idle"
    }
  }

  // ================================================================ state
  // idle      an app on screen, nothing drawn
  // ready     a finger in the home zone: the overlay is mapped (clear) while the snapshot comes
  // drag      the card follows the finger
  // switcher  the App Switcher
  // settle    the overlay covers a change underneath, then lets go
  // home      the home screen (an empty workspace), nothing drawn over it
  property string mode: "idle"
  function preset(r, d) { return { response: r / 1000 * (Theme.reduceMotion ? 0 : 1), dampingRatio: d } }
  readonly property var backPreset: preset(cfg.backResponse, cfg.backDamping)
  readonly property var switcherPreset: preset(cfg.switcherResponse, cfg.switcherDamping)
  readonly property var flyInPreset: preset(cfg.flyInResponse, cfg.flyInDamping)
  // what has no finger to follow goes on SpringBoard's critically damped spring (0.336 s, no
  // overshoot): a Home button press (iconZoomDown, toggleAppSwitcher, switcherToHome) and an app
  // growing to full screen (zoomUp from its icon, launchAppFromSwitcher from a card)
  readonly property var buttonPreset: preset(cfg.buttonResponse, cfg.buttonDamping)
  readonly property var launchPreset: preset(cfg.launchResponse, cfg.launchDamping)
  readonly property var followPreset: ({ response: cfg.followResponse / 1000 * (Theme.reduceMotion ? 0 : 1), dampingRatio: cfg.followDamping })
  property string screenName: ""
  property var cards: []            // the entries shown as cards, oldest first
  property int cur: -1              // the card that was on screen
  property bool fromHome: false
  // a finger of the home zone is down (Tablet.qml): the switcher that finger opened takes no touch
  // until it lifts, or its own release would land on the new surface as a tap
  property bool zoneFinger: false
  // a finger on the bottom edge, from the home zone or a cast screen's edge (Tablet.qml): the App
  // Switcher builds its cards meanwhile (warm)
  property bool gestureFinger: false
  property bool armed: false
  property real areaW: 0
  property real areaH: 0
  property var cardRep: null        // the Repeater of the gesture screen's cards
  property string settleTo: "idle"
  readonly property bool covering: mode === "drag" || mode === "switcher" || mode === "settle"

  // The backdrop, as SpringBoard layers it: the home screen's icons (homeV) only appear when the
  // card goes home; behind a dragged card and in the switcher lies the blurred wallpaper (blurV);
  // the dock slides up when a gesture starts and stays through the switcher (dockV).
  Spring { id: homeV; preset: home.preset(home.cfg.homeScreenResponse, home.cfg.homeScreenDamping); reduced: Theme.reduceMotion }
  // the Material switcher's entrance spring: the backdrop stands by the time a pause hands the card over
  // (v3's 0.574 s blur was still coming when the switcher took over, Henri 2026-11-12)
  Spring { id: blurV; preset: home.mt.switcher.enterSpring; reduced: Theme.reduceMotion }
  Spring { id: dockV; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion }
  // a spring sits at v and stays there: Spring.snap() keeps the old target, so the next same
  // target would not move it (the dock stayed down after a gesture that had snapped it)
  function jumpTo(sp, v) { sp.target = v; sp.snap(v) }
  function backdrop(grid, blur, dock, now) {
    if (now) { jumpTo(homeV, grid); jumpTo(blurV, blur); jumpTo(dockV, dock) }
    else { homeV.target = grid; blurV.target = blur; dockV.target = dock }
  }
  Spring { id: dimV; preset: Theme.spring("smooth"); reduced: Theme.reduceMotion }
  // in the App Switcher (1) or not: what stays of the home screen behind it (switcherHome,
  // switcherHomeBlur, switcherTint — iPadOS: at 0.9, half seen, blurred, darkened), on the blur's spring
  Spring { id: switchV; preset: home.preset(home.cfg.blurResponse, home.cfg.blurDamping); reduced: Theme.reduceMotion; target: home.mode === "switcher" ? 1 : 0 }
  Spring { id: labelV; preset: Theme.spring("smooth"); reduced: Theme.reduceMotion }
  Spring { id: pageV; preset: Theme.spring("smooth"); reduced: Theme.reduceMotion }
  property int page: 0
  property real swX: 0              // the switcher's scroll: where the newest column's centre sits

  // the card shown for cards[i], straight from the Repeater (a registry of its own kept references
  // to delegates Qt had already deleted, and every call on one threw — 2026-10-28, the overlay
  // then covered the screen for good)
  function card(i) {
    var o = cardRep && i >= 0 && i < cardRep.count ? cardRep.itemAt(i) : null
    return o && typeof o.to === "function" ? o : null
  }
  // every way in (Tablet.qml, timers, the switcher's fingers) goes through here: whatever throws,
  // the overlay lets go of the screen instead of covering it
  function guard(name, fn) {
    try { fn() } catch (e) {
      console.warn("henri.tablet-v4 Home: " + name + ": " + e)
      note("error " + name)
      abort()
    }
  }

  // ---- a finger landed in the home zone
  // the finger did something else (a tap, a long press, a slide): nothing to draw
  function other(kind) {
    swZone = false
    if (mode === "ready") { mode = "idle"; endStat(kind) }
    else if (fromHome && stat.t0) endStat(kind)
  }
  // drop whatever the overlay is doing (a new finger always wins over a stuck animation)
  function abort() {
    settleTick.stop(); letGo.stop(); openLater.stop(); closeLater.stop(); relayoutLater.stop()
    // the app that was chosen still gets its workspace (a finger landing mid-flight dropped it)
    if (focusAddress) focusNow()
    settleCheck = null; launchedId = ""; armed = false; sliding = false; homeSwitchAt = 0; appSwitchAt = 0; swZone = false
    if (navG.dragging) navG.abort()
    mode = emptyOn(screenName) ? "home" : "idle"
    note("abort")
    endStat("abort")
  }
  // a finger in the home zone while the Material App Switcher is open: a flick home closes it and goes
  // home, anything else leaves it (its own touch handles the rest)
  property bool swZone: false
  function prepare(screenName) {
    if (!active) return
    swZone = false
    if (swOpen && !swDragging) { swZone = true; home.screenName = screenName; return }
    if (mode === "settle" || mode === "ready" || mode === "drag" || mode === "homeDrag") abort()
    if (mode !== "idle" && mode !== "home") return
    home.screenName = screenName
    // the monitor's active workspace can lag behind a change the overlay made (Quickshell updates
    // it on the next refresh); our own "home" counts as well
    Hyprland.refreshMonitors()
    Hyprland.refreshWorkspaces()
    fromHome = mode === "home" || emptyOn(screenName)
    armed = false
    sliding = false
    Hyprland.refreshToplevels()
    var list = scanWindows(screenName)
    var m = monitorOf(screenName), at = -1
    for (var i = 0; i < list.length; i++) if (m && m.activeWorkspace && list[i].workspace === m.activeWorkspace.id) at = i
    if (fromHome) { cur = list.length - 1; cards = list; mode = "home"; return }
    startStat()
    if (at < 0) return
    cards = list
    cur = at
    backdrop(0, 0, 0, true); jumpTo(dimV, 0); jumpTo(labelV, 0)
    for (var j = 0; j < list.length; j++) {
      var o = card(j)
      if (!o) continue
      o.set("x", HM.besideX(j, at, 1, 0, areaW, cfg)); o.set("y", 0); o.set("s", 1); o.set("m", 0); o.set("l", 0); o.set("o", 1)
      o.z = j === at ? 2 : 1
    }
    var c = card(at)
    if (c) c.refresh()
    stat.shot = c && c.hasShot ? 0 : -1
    mode = "ready"
    note("ready " + list[at].appId)
  }

  // ---- the finger moves up (lift) — or keeps moving while the switcher is armed
  function lift(up, dx, vy, x0) {
    if (swZone) return
    // on the home screen: gesture navigation, the Material App Switcher follows the finger
    if (fromHome) { if (mode === "home") navMove(up); return }
    if (mode !== "ready" && mode !== "drag") return
    var c = card(cur)
    var now = Date.now()
    if (stat.last) { var gap = now - stat.last; stat.maxGap = Math.max(stat.maxGap, gap); stat.sumGap += gap; if (gap > 50) mark("gap " + gap) }
    stat.last = now; stat.lifts++
    if (!c || !c.hasShot) return               // the overlay stays clear until the snapshot is there
    if (stat.shot < 0) stat.shot = now - stat.t0
    mode = "drag"
    var f = HM.follow(up, dx, areaW, areaH, cfg, { left: cur <= 0, right: cur >= cards.length - 1 }, vy || 0)
    // SpringBoard scales the card about the finger's x, not the screen's centre
    if (x0 !== undefined) f.x += (1 - f.s) * (x0 - areaW / 2)
    // a very fast spring instead of a jump: finger events from a cast come unevenly, the card glides
    var fp = followPreset
    c.to("x", f.x, fp); c.to("y", f.y, fp); c.to("s", f.s, fp)
    for (var i = 0; i < cards.length; i++) {
      if (i === cur) continue
      var o = card(i)
      if (o) { o.to("x", HM.besideX(i, cur, f.s, f.x, areaW, cfg), fp); o.to("y", f.y, fp); o.to("s", f.s, fp); o.set("o", 1) }
    }
    // no dock coming up under the card: the Material switcher it leads to has none (Henri 2026-11-12)
    if (blurV.target !== 1) backdrop(0, 1, 0, false)
  }
  function arm() {
    if (armed || swZone) return
    armed = true
    note("armed")
    if (fromHome) return                       // from the home screen the cards come when the finger lets go
    for (var i = 0; i < cards.length; i++) { var o = card(i); if (o) o.capture = true }
    dimV.target = 1; labelV.target = 1
  }

  // ---- the finger let go: "home" (far / fast), "switcher" (after a pause), "end" (short), "cancel"
  function release(kind, info) {
    info = info || {}
    if (swZone) {
      swZone = false
      if (kind === "home") { swProgress = 0; if (emptyOn(screenName)) homeLocal(screenName); else goHomeNow() }
      return
    }
    stat.release = kind
    stat.travel = Math.round(info.travel || 0)
    if (fromHome) {
      // gesture navigation decides (NavGesture: a flick home only with a way home, past nav.travel
      // the switcher, else it sinks back); the zone's own "home" / pause are only its classification
      navEnd(kind)
      endStat(mode)
      return
    }
    if (mode === "ready") { mode = "idle"; if (kind === "home") goHomeNow(); endStat("no snapshot"); return }   // no snapshot yet: no card to animate
    if (mode !== "drag") { endStat("not dragging: " + mode); return }
    var c = card(cur)
    var hand = { x: c.velocity("x"), y: c.velocity("y"), s: c.velocity("s") }
    if (kind === "cancel") { back(hand); return }
    // where it goes is read from the finger's last speed, as SpringBoard does (a pause shown while
    // dragging only previewed the switcher)
    var to = HM.destination(info.travel || 0, info.dx || 0, info.velocity || 0, info.vx || 0,
                            cards.length, cur, areaW, areaH, cfg, tt)
    stat.decided = to
    if (to === "home") toHome(hand, info.velocity || 0)
    else if (to === "switcher") toMaterialSwitcher(hand)
    else if (to === "next" || to === "prev") openCard(cur + (to === "next" ? 1 : -1), hand)
    else back(hand)
  }

  // ---- what each gesture did, for tuning on the device (IPC homeStats): how long the snapshot
  // took, how many finger events came and the largest gap between them
  property var stat: ({})
  property var stats: []
  function startStat() { stat = { t0: Date.now(), shot: -1, lifts: 0, last: 0, maxGap: 0, sumGap: 0, release: "", travel: 0, fromHome: fromHome, frames: 0, sumFrame: 0, maxFrame: 0, slow: 0, tl: [] } }
  // the gesture's timeline: [ms since its start, what happened] — mode changes, the home screen's
  // window showing, slow frames (with their length) and long pauses between finger events
  function mark(what) { if (stat.t0 && stat.tl.length < 60) stat.tl.push([Date.now() - stat.t0, what]) }
  // the overlay's own frames while it moves (QML frame clock): is the drawing smooth?
  FrameAnimation {
    running: home.mode === "drag" || home.mode === "settle" || home.mode === "switcher" || home.mode === "homeDrag"
    onTriggered: {
      if (!home.stat.t0 || frameTime <= 0) return
      var ms = frameTime * 1000
      home.stat.frames++; home.stat.sumFrame += ms; home.stat.maxFrame = Math.max(home.stat.maxFrame, ms)
      if (ms > 25) { home.stat.slow++; home.mark("slow " + Math.round(ms) + " " + home.mode) }
    }
  }
  function endStat(to) {
    if (!stat.t0) return
    var l = stats.slice(-29)
    l.push({ ms: Date.now() - stat.t0, shotMs: stat.shot, lifts: stat.lifts, maxGap: stat.maxGap,
             avgGap: stat.lifts > 1 ? Math.round(stat.sumGap / (stat.lifts - 1)) : 0,
             frames: stat.frames, avgFrame: stat.frames ? +(stat.sumFrame / stat.frames).toFixed(1) : 0, maxFrame: Math.round(stat.maxFrame), slowFrames: stat.slow,
             release: stat.release, decided: stat.decided || "", travel: stat.travel, fromHome: stat.fromHome, to: to, tl: stat.tl })
    stats = l
    stat = {}
  }

  // ---- outcomes
  function layoutApp(at, hand, spring) {
    for (var i = 0; i < cards.length; i++) {
      var o = card(i)
      if (!o) continue
      var here = i === at
      var bp = spring || home.backPreset
      o.to("x", HM.besideX(i, at, 1, 0, areaW, cfg), bp, here && hand ? hand.x : undefined)
      o.to("y", 0, bp, here && hand ? hand.y : undefined)
      o.to("s", 1, bp, here && hand ? hand.s : undefined)
      o.to("m", 0, bp); o.to("l", 0, bp); if (here) o.to("o", 1, bp)
      o.z = here ? 2 : 1
    }
    backdrop(0, 0, 0, false); dimV.target = 0; labelV.target = 0
  }
  function back(hand) {
    note("back")
    layoutApp(cur, hand)
    settleWhen(function () { var c = card(cur); return !c || c.settled(["x", "y", "s"]) }, "idle", false)
  }
  function toHome(hand, vUp, button) {
    note("home")
    var c = card(cur), e = cards[cur]
    var r = homeScreenItem ? homeScreenItem.iconRect(e.appId, coverItem || homeScreenItem) : null
    // no icon on screen (another page): it shrinks in the middle and fades
    var tx = r ? r.x + r.w / 2 - areaW / 2 : 0, ty = r ? r.y + r.w / 2 - areaH / 2 : 0
    var size = r ? r.w : HM.grid(areaW, areaH, cfg).icon
    // SpringBoard's flight into the icon: the position on its own spring with half the finger's
    // vertical speed (it carries on up, then arcs to the icon); the window turns into the icon
    // quickly on faster springs (the iPad video: an icon after ~0.12 s, landed after ~0.35 s)
    var fly = button ? buttonPreset : preset(cfg.flyResponse, cfg.flyDamping)
    var shrink = button ? buttonPreset : preset(cfg.scaleResponse, cfg.scaleDamping)
    var morph = preset(cfg.morphResponse, cfg.morphDamping)
    // the scale is handed the finger's speed (SpringBoard: 1.5 × vy / H, capped)
    var sv = -Math.min(cfg.scaleVelocityCap, cfg.scaleVelocity * Math.max(0, vUp || 0) / areaH)
    c.to("x", tx, fly, hand.x); c.to("y", ty, fly, hand.y * cfg.flyVelocity); c.to("s", size / areaH, shrink, sv)
    c.to("m", 1, morph); c.z = 2
    if (!r) c.to("o", 0, shrink)
    for (var i = 0; i < cards.length; i++) if (i !== cur && card(i)) card(i).to("o", 0, "snappy")
    backdrop(1, 0, 1, false); dimV.target = 0; labelV.target = 0
    // the workspace changes once the card has landed (settleTick → goHomeNow): sent during the flight,
    // the switch's slow frame stopped the card just before the icon (Henri 2026-11-12)
    settleWhen(function () { return c.near(["x", "y", "s"]) }, "home", true)
  }
  // the first empty workspace on the gesture's screen (not just any empty one: another monitor's
  // would leave this screen on its app)
  // how long the overlay waits after a workspace switch: Hyprland's slide, or in tablet mode (no slide,
  // tablet.lua) only the frames until the workspace shows
  readonly property int settleMs: Theme.touch ? cfg.settleTablet : cfg.settle
  property real homeSwitchAt: 0       // when the last switch to an empty workspace went out
  property real appSwitchAt: 0        // when the last switch to an app's workspace went out
  function goHomeNow() {
    homeSwitchAt = Date.now()
    var mon = String(screenName).replace(/[^A-Za-z0-9_-]/g, "")
    dispatch("function() hl.dispatch(hl.dsp.focus({ monitor = \"" + mon + "\" })) hl.dispatch(hl.dsp.focus({ workspace = \"emptynm\" })) end",
             "workspace emptynm")
  }
  // v3's card switcher: no gesture reaches it any more (the Material App Switcher took over, see
  // toMaterialSwitcher); its fingers, closeCard and layoutSwitcher stay for the v3 code paths that remain
  function toSwitcher(hand, button) {
    note("switcher")
    mode = "switcher"
    var g = HM.switcherGeo(cards.length, areaW, areaH, cfg)
    swX = g.lo
    for (var i = 0; i < cards.length; i++) {
      var o = card(i)
      if (!o) continue
      var p = HM.switcherPos(i, cards.length, swX, g, cfg), here = i === cur
      o.capture = true
      // the dragged card on SpringBoard's app-to-switcher spring, the others fly in
      var sp = here ? (button ? buttonPreset : switcherPreset) : flyInPreset
      o.to("x", p.x, sp, here && hand ? hand.x : undefined)
      o.to("y", p.y, sp, here && hand ? hand.y : undefined)
      o.to("s", g.s, sp, here && hand ? hand.s : undefined)
      o.to("m", 0, sp); o.to("o", 1, sp); o.to("l", 0, sp)
      o.z = 1
    }
    backdrop(0, 1, 1, false); dimV.target = 1; labelV.target = 1
  }
  // an app from the switcher, or the neighbour a sideways finger brought: full size, then its workspace
  function openCard(i, hand) {
    note("open " + (cards[i] ? cards[i].appId : ""))
    mark("open")
    var was = cur
    cur = i
    layoutApp(i, i === was ? hand : null, launchPreset)
    for (var j = 0; j < cards.length; j++) if (j !== i && card(j) && Math.abs(j - i) > 1) card(j).to("o", 0, "snappy")
    var e = cards[i]
    // another app's workspace only once the card stands (focusLater): the switch costs the shell a
    // frame of 50-130 ms (homeStats on the M1, 2026-11-09), which sent at the tap held the card in
    // the switcher before it moved; on a standing card nothing shows it. The overlay then waits for
    // Hyprland's slide too.
    if (i !== was) { focusNear = true; focusAddress = e.address }
    else dispatch("hl.dsp.focus({ window = \"address:" + e.address + "\" })", "focuswindow address:" + e.address)
    var c = card(i)
    settleWhen(function () { return (!c || c.settled(["x", "y", "s"])) && !focusAddress }, "idle", i !== was)
  }
  // ---- a finger sliding along the home zone, or four fingers sideways on a touchpad (Tablet.qml):
  // the windows of the screen side by side at full size, following it 1:1, in screen order —
  // workspace by workspace, an app's windows on its workspace in the order they opened. So an
  // app's second window is one step away too, and the swipe carries on across workspaces (Henri
  // 2026-11-09: switch between the fullscreen windows, not the workspaces).
  function sideOrder(list) {
    return list.slice().sort(function (a, b) { return a.workspace - b.workspace || a.order - b.order })
  }
  // the window on screen: the focused one on the screen's workspace, else the one used last there;
  // -1 on an empty workspace (the home screen)
  function sideAt(list, screenName) {
    var m = monitorOf(screenName)
    if (!m || !m.activeWorkspace) return -1
    var ws = m.activeWorkspace.id, act = Hyprland.activeToplevel
    var a = act && act.lastIpcObject ? String(act.lastIpcObject.address) : "", best = -1
    for (var i = 0; i < list.length; i++) {
      if (list[i].workspace !== ws) continue
      if (list[i].address === a) return i
      if (best < 0 || list[i].focus < list[best].focus) best = i
    }
    return best
  }
  // the window `step` places from what the screen shows (from the home screen: the first window on
  // a later workspace, or the last on an earlier one)
  function sideStep(screenName, step) {
    var list = sideOrder(scanWindows(screenName)), at = sideAt(list, screenName)
    if (at >= 0) return list[at + step] || null
    var m = monitorOf(screenName), ws = m && m.activeWorkspace ? m.activeWorkspace.id : 0
    if (step > 0) { for (var i = 0; i < list.length; i++) if (list[i].workspace > ws) return list[i] }
    else for (var j = list.length - 1; j >= 0; j--) if (list[j].workspace < ws) return list[j]
    return null
  }
  // the icons beside the indicator while a finger slides
  function sideNeighbours(screenName) {
    var p = sideStep(screenName, -1), n = sideStep(screenName, 1)
    return { prev: p ? String(p.icon || "") : "", next: n ? String(n.icon || "") : "" }
  }
  property bool sliding: false
  function slide(dx) {
    if (fromHome || (mode !== "ready" && mode !== "drag")) return
    var fp = followPreset
    if (!sliding) {
      var c0 = card(cur)
      if (!c0 || !c0.hasShot) return             // the overlay stays clear until the snapshot is there
      var list = sideOrder(cards), at = sideAt(list, screenName)
      if (at < 0) return
      sliding = true
      if (list.map(e => e.key).join() !== cards.map(e => e.key).join()) cards = list
      cur = at
      for (var j = 0; j < cards.length; j++) {
        var o0 = card(j)
        if (!o0) continue
        o0.set("x", HM.besideX(j, cur, 1, 0, areaW, cfg)); o0.set("y", 0); o0.set("s", 1); o0.set("m", 0); o0.set("l", 0); o0.set("o", 1)
        o0.capture = true
        o0.z = j === cur ? 2 : 1
      }
      if (stat.shot < 0 && stat.t0) stat.shot = Date.now() - stat.t0
      mode = "drag"
      backdrop(0, 1, 0, false)
      note("slide " + cards[cur].appId)
    }
    var f = HM.follow(0, dx, areaW, areaH, cfg, { left: cur <= 0, right: cur >= cards.length - 1 }, 0)
    for (var i = 0; i < cards.length; i++) { var o = card(i); if (o) o.to("x", HM.besideX(i, cur, 1, f.x, areaW, cfg), fp) }
    stat.lifts = (stat.lifts || 0) + 1
  }
  // the finger let go: step +1 / -1 to the window beside it, 0 back. Without cards (no snapshot
  // yet, the home screen) the window still gets the focus, only without the slide.
  function slideEnd(step) {
    if (!sliding) {
      other("slide")
      if (swOpen) { swDragging = false; swProgress = 0 }
      var e = step ? sideStep(screenName, step) : null
      if (e) { note("side " + e.appId); dispatch("hl.dsp.focus({ window = \"address:" + e.address + "\" })", "focuswindow address:" + e.address) }
      return
    }
    sliding = false
    stat.release = "slide"
    var to = cur + step
    if (step && to >= 0 && to < cards.length) { stat.decided = step > 0 ? "next" : "prev"; openCard(to, null) }
    else { stat.decided = "back"; back(null) }
  }
  function switcherHome() {
    note("switcher home")
    for (var i = 0; i < cards.length; i++) { var o = card(i); if (o) { o.to("o", 0, buttonPreset); o.to("s", o.value("s") * cfg.dockIcon, buttonPreset) } }
    backdrop(1, 0, 1, false); dimV.target = 0; labelV.target = 0
    goHomeNow()
    settleWhen(function () { return true }, "home", true)
  }
  // ---- a Home button (the iPad's, through ipad-link, IPC homeButton): one press = the home screen,
  // two = the App Switcher, each one movement. A played finger swipe could not do it: the switcher
  // needs the finger to rest, and the app stopped half-way before it went on (Henri 2026-11-06);
  // in the switcher the swipe is not even listened to.
  property string buttonWant: ""
  property real buttonAt: 0
  function button(screenName, kind) {
    if (!active || (kind !== "home" && kind !== "switcher")) return
    if (swOpen) {                                           // the Material App Switcher: either press closes it
      swDragging = false; swProgress = 0
      if (kind === "home") { if (emptyOn(screenName)) homeLocal(screenName); else { home.screenName = screenName; goHomeNow() } }
      return
    }
    if (mode === "switcher") {
      if (kind === "home") switcherHome()
      else if (cards.length && !fromHome) openCard(cur, null)
      return
    }
    if (mode !== "idle" && mode !== "home") return          // a gesture or a flight is under way
    prepare(screenName)
    if (mode === "home") { if (kind === "switcher") openMaterialSwitcher(screenName); else homeLocal(screenName); return }   // Home on the home screen: close what is open
    if (mode !== "ready") return
    buttonWant = kind
    buttonAt = Date.now()
    buttonLater.start()
  }
  // the app's snapshot first (prepare asked for it), then the card goes as a released finger sends it
  Timer {
    id: buttonLater
    interval: Theme.dur("fast") / 4
    repeat: true
    onTriggered: home.guard("button", function () {
      var c = home.card(home.cur)
      if (home.mode !== "ready") { stop(); return }
      if (!c || !c.hasShot) {
        if (Date.now() - home.buttonAt < Theme.dur("slow")) return
        stop(); home.mode = "idle"; if (home.buttonWant === "home") home.goHomeNow(); home.endStat("button, no snapshot"); return
      }
      stop()
      home.stat.release = "button " + home.buttonWant
      home.mode = "drag"
      var still = { x: 0, y: 0, s: 0 }
      if (home.buttonWant === "home") home.toHome(still, 0, true)
      else home.toMaterialSwitcher(still)
    })
  }
  function closeCard(i) {
    var e = cards[i]
    if (!e) return
    note("close " + e.appId)
    dispatch("hl.dsp.window.close({ window = \"address:" + e.address + "\" })", "closewindow address:" + e.address)
    var c = card(i)
    if (c) c.to("l", -areaH, "snappy", c.velocity("l"))
    closeLater.key = e.key
    closeLater.restart()
  }
  Timer {
    id: closeLater
    property string key: ""
    interval: Theme.dur("normal")
    onTriggered: home.guard("closeLater", function () {
      var list = home.cards.filter(function (c) { return c.key !== key })
      home.cards = list
      if (!list.length) { home.switcherHome(); return }
      home.cur = list.length - 1
      var g = HM.switcherGeo(list.length, home.areaW, home.areaH, home.cfg)
      home.swX = Math.max(g.lo, Math.min(g.hi, home.swX))
      relayoutLater.restart()
    })
  }
  Timer { id: relayoutLater; interval: 0; onTriggered: home.guard("relayout", function () { home.layoutSwitcher(home.swX, false) }) }
  function layoutSwitcher(sx, jumpNow) {
    var g = HM.switcherGeo(cards.length, areaW, areaH, cfg), t = Date.now()
    for (var i = 0; i < cards.length; i++) {
      var o = card(i)
      if (!o) continue
      var p = HM.switcherPos(i, cards.length, sx, g, cfg)
      if (jumpNow) o.jump(p.x, o.value("y"), o.value("s"), 0, t)
      else { o.to("x", p.x, "snappy"); o.to("y", p.y, "snappy"); o.to("s", g.s, "snappy") }
    }
  }

  // ---- from the home screen: an app's icon
  // args: started with them (also when it runs: a running app takes them over D-Bus and shows
  // the item); from: the tile the card grows out of when it is not the app's icon (a widget)
  // fresh: a command that opens a new window even when the app runs (the context menu's New Window)
  function openApp(id, args, from, fresh) {
    if (!active) return
    var e = entries[id]
    if (!e) return
    var list = scanWindows(screenName || (Quickshell.screens[0] ? Quickshell.screens[0].name : ""))
    var at = -1
    for (var i = list.length - 1; !fresh && i >= 0; i--) if (list[i].appId === id) { at = i; break }
    note("tap " + id + (at >= 0 ? " (running)" : ""))
    startStat(); mark("open " + id)
    var r = homeScreenItem ? homeScreenItem.iconRect(from || id, coverItem || homeScreenItem) : null
    var cmd = fresh ? fresh : args && args.length && e.command && e.command.length ? ["uwsm-app", "--"].concat(e.command, args) : null
    if (cmd && (!inRig || (Quickshell.env("VELUM_TABLET_LAUNCH") || "") !== "")) Quickshell.execDetached(cmd)
    if (at >= 0) {
      cards = list
      cur = at
    } else {
      cards = [{ key: "launch:" + id, address: "", toplevel: null, workspace: 0, appId: id, icon: e.icon, name: e.name, focus: 0 }]
      cur = 0
      if (!cmd && (!inRig || (Quickshell.env("VELUM_TABLET_LAUNCH") || "") !== "")) Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", id + ".desktop"])
      launchedId = id
      launchOpened = false
      launchStart = Date.now()
    }
    backdrop(1, 0, 1, true); jumpTo(dimV, 0); jumpTo(labelV, 0)
    openFrom = r
    // the card sits on the icon before the overlay shows: shown first, it was drawn for one frame at
    // the screen's size (an app's snapshot, or the launch card) and the app seemed to open twice
    if (placeOnIcon()) mode = "settle"
    openLater.restart()
  }
  property var openFrom: null
  function placeOnIcon() {
    var c = card(cur), r = openFrom
    if (!c) return false
    c.capture = true
    for (var i = 0; i < cards.length; i++) if (i !== cur && card(i)) card(i).set("o", 0)
    c.set("x", r ? r.x + r.w / 2 - areaW / 2 : 0); c.set("y", r ? r.y + r.w / 2 - areaH / 2 : 0)
    c.set("s", (r ? r.w : areaH * cfg.splashIcon) / areaH); c.set("m", 1); c.set("o", 1); c.set("l", 0)
    c.z = 2
    return true
  }

  // ---- the long-press menus (MaterialMenu, the lab's ActionMenu.jsx): an app's (its own actions,
  // New window / App info as tiles), a folder's (Rename, Remove folder), the wallpaper's. A new window
  // lands on the home screen's empty workspace, so it is an app of its own there (tablet.lua); the
  // card grows out of the icon as at a launch.
  property var screenHomes: ({})        // screen name → its interactive home screen (IPC)
  property string menuOpenId: ""         // the item whose menu is open (IPC home: "menu")
  function isNewWindow(a) { return /^new[-_ ]?window$/i.test(a.id || "") || /^new.?window$/i.test(a.name || "") }
  function menuFor(id, where) {
    if (where === "home") return {
      rows: [{ key: "wallpaper", text: "Wallpaper & style", icon: "image" }, { key: "widgets", text: "Widgets", icon: "apps" },
             { key: "settings", text: "Home settings", icon: "settings" }]
    }
    if (HM.isFolder(id)) {
      var f = layout.folders[HM.folderKey(id)]
      if (!f) return null
      var apps = f.items.map(function (a) { return home.entries[a] }).filter(Boolean)
      return { header: { folder: HM.miniApps(apps, cfg.folder.miniCols), title: f.name, subtitle: apps.length + " apps" },
               rows: [{ key: "rename", text: "Rename", icon: "pencil" }, { key: "removeFolder", text: "Remove folder", icon: "close", danger: true }] }
    }
    var e = entries[id]
    if (!e) return null
    var acts = (e.actions || []).filter(function (a) { return !home.isNewWindow(a) && a.command.length }).slice(0, mt.menu.actionsMax)
    return { header: { icon: e.icon, title: e.name, subtitle: where === "dock" ? "In the dock" : "" },
             rows: acts.map(function (a) { return { key: "action:" + a.id, text: a.name, icon: "bolt" } }),
             tiles: [{ key: "new", text: "New window", icon: "open.external" }, { key: "info", text: "App info", icon: "info" }] }
  }
  function menuChosen(id, key) {
    note("menu " + (id || "home") + " " + key)
    if (key === "wallpaper") { Quickshell.execDetached(["omarchy-shell", "-q", "wallpaper", "open"]); return }
    if (key === "widgets") { var hw = screenHomes[screenName]; if (hw) hw.picker.open = true; return }
    if (key === "settings") { note("later " + key); showSnack("Home settings come in a later phase"); return }
    var e = entries[id]
    if (!e) return
    if (key === "info") { appInfo(id); return }
    // New window: the entry's own new-window action when it has one (browsers), else the app again
    var want = key.indexOf("action:") === 0 ? function (a) { return a.id === key.slice(7) } : isNewWindow
    var act = (e.actions || []).filter(want)[0]
    var cmd = act && act.command.length ? ["uwsm-app", "--"].concat(act.command) : ["uwsm-app", "--", "gtk-launch", id + ".desktop"]
    openApp(id, [], id, cmd)
  }
  // App info (the long-press menu, All apps' menu): a snackbar for now
  function appInfo(id) {
    var e = entries[id]
    if (!e) return
    note("info " + id)
    showSnack("App info: " + e.name + " (comes in a later phase)")
  }
  // ---- Uninstall (a drop target): the system's dialog; phase 1 asks and runs nothing, it only says
  // what it would run (bin/uninstall-plan follows Omarchy's omarchy-remove-launcher-entry read-only)
  property var confirm: null            // { id, name, plan }
  function askUninstall(id, name) {
    confirm = { id: id, name: name, plan: "" }
    planProc.command = [Qt.resolvedUrl("bin/uninstall-plan").toString().replace(/^file:\/\//, ""), id, name]
    planProc.running = true
  }
  Process {
    id: planProc
    stdout: StdioCollector { onStreamFinished: if (home.confirm) home.confirm = Object.assign({}, home.confirm, { plan: String(text || "").trim() }) }
  }
  function confirmed(ok) {
    var c = confirm
    confirm = null
    if (!c || !ok) return
    note("uninstall (not run) " + c.id + ": " + (c.plan || "?"))
    showSnack("Nothing was uninstalled (phase 1) — it would run: " + (c.plan || "?"))
  }
  property string launchedId: ""
  property bool launchOpened: false
  property real launchStart: 0
  Timer {
    id: openLater
    interval: 0
    onTriggered: home.guard("openLater", function () {
      var c = home.card(home.cur), e = home.cards[home.cur]
      if (!c) return
      // placed by openApp already, unless the Repeater had no card for it yet
      if (home.mode !== "settle") home.placeOnIcon()
      var lp = home.launchPreset
      c.to("x", 0, lp); c.to("y", 0, lp); c.to("s", 1, lp); c.to("m", 0, lp)
      backdrop(0, 0, 0, false)
      // a running app's workspace once its card stands (focusNear, as from the switcher)
      if (e.address) {
        home.focusNear = true
        home.focusAddress = e.address
      }
      home.settleWhen(function () {
        if (!c.settled(["x", "y", "s"])) return false
        if (home.focusAddress) return false
        if (!home.launchedId) return true
        // a launched app: wait for a new window, or give up after launchTimeout
        return home.launchOpened || Date.now() - home.launchStart > home.cfg.launchTimeout
      }, "idle", !!e.address)
    })
  }

  // an app's workspace only once the overlay covers the screen: sent at once, Hyprland showed the
  // switch (the app at full size) before the overlay's first covering frame was on screen.
  // focusNear (every card that grows to an app): only once that card has landed
  property string focusAddress: ""
  property bool focusNear: false
  function focusNow() {
    var a = focusAddress
    focusAddress = ""
    focusNear = false
    appSwitchAt = Date.now()
    mark("focus")
    dispatch("hl.dsp.focus({ window = \"address:" + a + "\" })", "focuswindow address:" + a)
  }
  // nothing on the overlay still visibly moving: the landed card alone was not enough, the
  // neighbours sliding off and the backdrop fading caught the switch's slow frame (homeStats on
  // the M1, 2026-11-09: a 42-47 ms frame ~40 ms after the focus, in the switcher's tail)
  function stillAll() {
    for (var i = 0; i < cards.length; i++) { var k = card(i); if (k && !k.near(["x", "y", "s", "o"])) return false }
    var sp = [homeV, blurV, dockV, dimV, labelV]
    for (var j = 0; j < sp.length; j++) if (Math.abs(sp[j].value - sp[j].target) > cfg.nearScale) return false
    return true
  }
  FrameAnimation {
    id: focusLater
    property int frames: 0
    running: home.focusAddress !== ""
    onRunningChanged: frames = 0
    onTriggered: home.guard("focusLater", function () {
      if (++focusLater.frames < home.cfg.coverFrames) return
      if (home.focusNear && !home.stillAll() && Date.now() - home.settleStart < home.cfg.launchTimeout) return
      home.focusNow()
    })
  }

  // ---- the overlay lets go once the condition holds and (after a workspace change) the slide is over
  property var settleCheck: null
  property bool settleWait: false
  property real settleStart: 0
  function settleWhen(check, to, workspaceChange) {
    settleStart = Date.now()
    settleCheck = check
    settleTo = to
    settleWait = workspaceChange
    if (mode !== "switcher") mode = "settle"
    settleTick.start()
  }
  Timer {
    id: settleTick
    interval: Theme.dur("fast") / 2
    repeat: true
    onTriggered: {
      // never cover the screen for good: past launchTimeout the overlay lets go whatever it waits for
      var late = Date.now() - home.settleStart > home.cfg.launchTimeout
      var waiting = false
      try { waiting = !!home.settleCheck && !late && !home.settleCheck() } catch (e) { waiting = false }
      if (waiting) return
      stop()
      home.settleCheck = null
      if (home.settleTo === "home") {
        if (!home.homeSwitchAt) home.goHomeNow()
        letGo.to = "home"
      } else letGo.to = "idle"
      // the workspace's slide may still run underneath: only what is left of it (an app's workspace
      // too, or its window slides in from the side once the overlay is gone)
      var since = home.homeSwitchAt ? Date.now() - home.homeSwitchAt : 0
      var appSince = home.appSwitchAt ? Date.now() - home.appSwitchAt : 0
      var floor = Math.min(Theme.dur("fast"), home.settleMs)
      letGo.interval = home.settleTo === "home" ? Math.max(floor, home.settleMs - since)
                     : home.settleWait && home.appSwitchAt ? Math.max(floor, home.settleMs - appSince)
                     : home.launchedId ? home.cfg.settle      // a new window still turns fullscreen (tablet.lua)
                     : home.settleWait ? home.settleMs : Theme.dur("fast")
      letGo.restart()
    }
  }
  Timer {
    id: letGo
    property string to: "idle"
    onTriggered: {
      home.mode = to
      home.homeSwitchAt = 0
      home.appSwitchAt = 0
      home.launchedId = ""
      home.armed = false
      home.cards = home.scanWindows(home.screenName)
      home.note("→ " + to)
      home.endStat(to)
    }
  }

  // ---- home screen pages
  // the pages follow the finger 1:1, give way past the first and last (rubber band), and settle on
  // a spring that keeps the finger's speed (Spring.from() would drop it)
  property int pageCount: 1
  function pageMoved(dx, t) {
    var x = -page * areaW + dx, lo = -(pageCount - 1) * areaW
    if (x > 0) x = HM.rubber(x, areaW * mt.grid.overscroll)
    else if (x < lo) x = lo - HM.rubber(lo - x, areaW * mt.grid.overscroll)
    pageV.snap(x)
  }
  function pageReleased(v, pages) {
    pageCount = pages
    var i = Math.round(-pageV.value / Math.max(1, areaW))
    if (Math.abs(v) > mt.grid.pageFlick) i = page + (v < 0 ? 1 : -1)
    page = Math.max(0, Math.min(pages - 1, i))
    var t = -page * areaW
    pageV.velocity = v
    if (pageV.target === t) pageV.target = t + (pageV.value < t ? -0.01 : 0.01)   // a change, so it runs
    pageV.velocity = v
    pageV.target = t
  }
  onActiveChanged: { if (!active) { mode = "idle"; cards = []; editing = false; swProgress = 0; swDragging = false } else rescan.restart() }

  // ================================================================ surfaces
  property var homeScreenItem: null      // the overlay's copy on the gesture's screen (for icon rects)
  property var coverItem: null           // the overlay's content: card coordinates are its own
  property string wallpaperTarget: ""
  readonly property string wallpaperLink: homeDir + "/.local/state/omarchy/current/background"
  Process {
    id: wallpaperProbe
    command: ["readlink", "-f", home.wallpaperLink]
    stdout: StdioCollector { onStreamFinished: home.wallpaperTarget = String(text || "").trim().slice(0, 512) }
  }
  // the Photos widget's photos: new picks once a day (the tool does nothing while they are fresh,
  // and nothing on a machine without the iCloud Photos catalog)
  Process { id: photoPicks; command: [home.homeDir + "/.local/share/velum/bin/velum-photo-picks"] }
  Timer { interval: home.cfg.widget.refreshEvery; repeat: true; running: true; triggeredOnStart: true; onTriggered: if (!photoPicks.running) photoPicks.running = true }
  Component.onCompleted: { VBoot.hold("home"); wallpaperProbe.running = true; scanApps(); Hyprland.refreshMonitors(); rescan.restart() }
  Component.onDestruction: VBoot.release("home")
  onModeChanged: {
    mark("mode " + mode)
    if (mode === "ready") wallpaperProbe.running = true
    if (mode !== "idle") editing = false   // edit mode ends whenever the home screen is left
  }

  Variants {
    model: home.active ? Quickshell.screens : []

    Scope {
      id: per
      required property var modelData
      readonly property string name: modelData.name

      property real homeH: 0
      // the bar's and the home zone's reserved strips (Hyprland): where the home screen's own window sits
      readonly property var reserved: {
        var m = home.monitorOf(per.name), r = m && m.lastIpcObject ? m.lastIpcObject.reserved : null
        return r && r.length === 4 ? r : [0, 0, 0, home.tt.homeZone]
      }
      // behind an open folder: the wallpaper blurred over the whole screen, on the background layer
      // (under the home screen's window, over the wallpaper) — the home screen's own window stops
      // at the bar and the home zone. No input; the home screen fades its icons out meanwhile.
      PanelWindow {
        id: folderWin
        screen: per.modelData
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        // also under the search view and All apps: the strips the home screen's window leaves (the bar's,
        // the home zone's, the on-screen keyboard's reserved zone) show the same blurred wallpaper
        readonly property real shownBy: Math.max(homeItem.folderShown, homeSearch.fade, homeDrawer.position)
        visible: homeWin.shown && shownBy > 0.002
        WlrLayershell.namespace: "velum-home-folder"
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region { item: folderNone }
        Item { id: folderNone; width: 0; height: 0 }
        FolderBackdrop {
          anchors.fill: parent
          opacity: Math.min(1, folderWin.shownBy)
          wallSource: home.wallpaperSource
          wallRect: Qt.rect(0, 0, width, height)
          tint: home.mt.color.scrim
        }
      }
      // the home screen itself, under the windows of an empty workspace
      PanelWindow {
        id: homeWin
        screen: per.modelData
        onHeightChanged: if (height > 0) per.homeH = height
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        color: "transparent"
        // Mapped for the whole of tablet mode, its icons loaded: mapping it when a gesture landed
        // cost the frame after it 75–97 ms on the M1 and 366–727 ms on the tablet (homeStats,
        // 2026-10-28). Hidden it is see-through and takes no input — only its opacity changes.
        // Shown also while the overlay is about to hand over to it (no flicker).
        readonly property bool shown: home.emptyOn(per.name) || (home.screenName === per.name && (home.mode === "home" || home.homeSwitchAt > 0))
        onShownChanged: home.mark("homeWindow " + (shown ? "shown" : "hidden") + " " + per.name)
        visible: true
        WlrLayershell.namespace: "velum-home-screen"
        WlrLayershell.layer: WlrLayer.Bottom
        // the keyboard: while the search view or the widget picker is up all of it (they are modal and
        // Escape closes them; both open on a lifted finger, so the grab never ends under a held one);
        // while the home screen shows on demand — a key typed there opens the search view (the
        // compositor focuses it as the pointer or a finger comes over it); an open folder's name too
        readonly property bool modalKeys: homeSearch.shown || picker.open
        WlrLayershell.keyboardFocus: modalKeys ? WlrKeyboardFocus.Exclusive : homeWin.shown || homeItem.wantsKeys ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        // no input while a home-zone finger is down: a pointer standing in for it would otherwise
        // move its focus here halfway up
        mask: Region { item: home.zoneFinger || !homeWin.shown ? homeNone : homeAll }
        Item { id: homeAll; anchors.fill: parent }
        Item { id: homeNone; width: 0; height: 0 }
        // a key typed while the home screen shows (nothing open over it): the search view with that key
        Item {
          id: keyCatch
          focus: true
          Keys.onPressed: function (ev) {
            if (!homeWin.shown || homeSearch.shown || homeDrawer.active || picker.open || home.openFolder || homeItem.menuOpen || homeItem.dragging || home.confirm) return
            var t = String(ev.text || "")
            if (t.length !== 1 || t === " " || t.charCodeAt(0) < 0x20 || (ev.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) return
            ev.accepted = true
            home.screenName = per.name
            home.search(per.name, t)
          }
        }
        // what lies under the search view and All apps: the wallpaper (only while one of them is up: the
        // compositor draws it under the window otherwise) and the home screen — taken once per open
        Item {
          id: homeBackdrop
          anchors.fill: parent
          Image {
            x: homeItem.wallRect.x; y: homeItem.wallRect.y; width: homeItem.wallRect.width; height: homeItem.wallRect.height
            visible: homeSearch.active || homeDrawer.active
            source: visible ? home.wallpaperSource : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: per.modelData.width
            sourceSize.height: per.modelData.height
            cache: true
          }
        MaterialHome {
          id: homeItem
          anchors.fill: parent
          folderBackdrop: false      // folderWin draws it, under the bar and the home zone too
          opacity: homeWin.shown ? 1 : home.cfg.warmOpacity
          gridOpacity: bootIn.value
          gridScale: Theme.reduceMotion ? 1 : home.cfg.homeZoom - (home.cfg.homeZoom - 1) * bootIn.value
          dockShift: Theme.reduceMotion ? 0 : (1 - bootIn.value) * homeItem.dockTravel
          tiles: home.gridTiles
          hotApps: home.dockApps
          layout: home.layout
          entries: home.entries
          menuFor: home.menuFor
          nameFolder: function (ids) { return HM.folderName(ids.map(function (a) { return (home.entries[a] || {}).cats || [] }), home.folderNames, "Folder") }
          openFolder: home.openFolder
          snack: home.snack
          confirm: home.confirm
          page: home.page
          pageX: pageV.value
          interactive: homeWin.shown
          running: home.runningApps
          wallSource: home.wallpaperSource
          wallRect: Qt.rect(0, -per.reserved[1], homeAll.width, homeAll.height + per.reserved[1] + per.reserved[3])
          onArranged: function (next) { home.guard("arranged", function () { home.note("arranged"); home.saveLayout(next) }) }
          onRemoveRequested: function (ids, name) { home.guard("hideItems", function () { home.hideItems(ids, name) }) }
          onRenamed: function (key, name) { home.guard("rename", function () { home.renameFolder(key, name) }) }
          onFolderRequested: function (id) { home.openFolder = id }
          onTurnPage: function (dir) { home.pageCount = pages; home.turnPage(dir) }
          onTapped: function (id) { home.screenName = per.name; home.guard("openApp", function () { home.openApp(id) }) }
          onWidgetTapped: function (id, item) { home.screenName = per.name; home.openWidget(id, item) }
          onMenuChosen: function (id, key) { home.screenName = per.name; home.guard("menuChosen", function () { home.menuChosen(id, key) }) }
          onMenuOpenChanged: { home.menuOpenId = menuOpen ? (menuId || "home") : ""; if (menuOpen) home.note("menu open " + (menuId || "home")) }
          onSearchRequested: { home.screenName = per.name; home.search(per.name) }
          onDrawerDrag: function (travel) { homeDrawer.dragging = true; homeDrawer.progress = Math.max(0, Math.min(1, travel / Math.max(1, homeDrawer.height * homeDrawer.cfg.travel))) }
          onDrawerRelease: function (v) { homeDrawer.release(v) }
          onUninstallRequested: function (id, name) { home.askUninstall(id, name) }
          onConfirmed: function (ok) { home.confirmed(ok) }
          onUndoRequested: home.undo()
          onPageMoved: function (dx, t) { home.pageCount = pages; home.pageMoved(dx, t) }
          onPageReleased: function (v) { home.pageReleased(v, pages) }
          Component.onCompleted: {
            var m = Object.assign({}, home.screenHomes)
            m[per.name] = { item: homeItem, search: homeSearch, drawer: homeDrawer, picker: picker, top: function () { return per.reserved[1] },
                            keys: function () { return homeWin.modalKeys ? "exclusive" : homeWin.shown || homeItem.wantsKeys ? "ondemand" : "none" },
                            barRect: function () { var g = homeItem.geo.search; return Qt.rect(g.x, g.y + homeItem.dockShift, g.w, g.h) } }
            home.screenHomes = m
          }
        }
        }

        // All apps: a swipe up on the grid brings it with the finger (MaterialHome's drawerDrag)
        AppDrawer {
          id: homeDrawer
          apps: home.entries
          homeIds: home.homeIdMap()
          columns: homeItem.geo.cols
          topInset: 0
          backdropSource: homeBackdrop
          onOpenApp: function (id) { home.screenName = per.name; homeDrawer.close(); home.guard("openApp", function () { home.openApp(id) }) }
          onAddToHome: function (id) { homeDrawer.close(); home.guard("addToHome", function () { home.addToHome(id, per.name) }) }
          onAppInfo: function (id) { home.appInfo(id) }
          onClosed: keyCatch.forceActiveFocus()
        }
        // the search view: the search bar grows into it
        SearchView {
          id: homeSearch
          apps: home.entries
          // the hotseat, then the grid's first apps (the lab's suggested), one row
          suggested: home.hotseatIds.concat(home.layout.order.filter(function (id) { return !!home.entries[id] && home.hotseatIds.indexOf(id) < 0 })).slice(0, homeItem.geo.cols)
          columns: homeItem.geo.cols
          backdropSource: homeBackdrop
          onOpenApp: function (id) { home.screenName = per.name; home.guard("openApp", function () { home.openApp(id) }) }
          onRunAction: function (id, action) { home.screenName = per.name; home.guard("searchAction", function () { home.searchAction(id, action) }) }
          onWebSearch: function (text) { home.webSearch(text) }
          onVoiceSearch: home.showSnack("Voice search comes in a later phase")
          onClosed: keyCatch.forceActiveFocus()
          // it stands in for Spotlight: a keyboard that came with it (velum-keyboard open) goes with it
          onShownChanged: if (!shown) home.dispatch("hl.dsp.event(\"velum-menu hidden\")", "event velum-menu hidden")
        }
        // the widget picker (the wallpaper's menu: Widgets): a tap puts the widget on the home screen
        WidgetPicker {
          id: picker
          anchors.fill: parent
          cell: Qt.size(homeItem.geo.cellW, homeItem.geo.cellH)
          sizeOf: function (k) { var c = W.span(home.mt.widgets.cells, k); return { w: c[0] * homeItem.geo.cellW - 2 * homeItem.geo.iconX, h: c[1] * homeItem.geo.cellH - 2 * homeItem.geo.iconY } }
          onScreen: function (k) { return home.layout.order.indexOf("widget:" + k) >= 0 }
          onAdd: function (k) { picker.open = false; home.guard("addWidget", function () { home.addWidget(k, per.name) }) }
          onClosed: { picker.open = false; keyCatch.forceActiveFocus() }
        }
      }

      // the gesture's overlay over the app area
      PanelWindow {
        id: overlay
        screen: per.modelData
        anchors { top: true; bottom: true; left: true; right: true }
        // the whole screen: in tablet mode every app is fullscreen, its card is the screen's size
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        color: "transparent"
        readonly property bool mine: home.screenName === per.name
        // mapped for as long as tablet mode is on: unmapping dropped every texture (wallpaper, blur,
        // snapshots), and building them again stalled the first frames of each gesture ~200 ms
        visible: mine
        readonly property bool shown: home.mode !== "idle" && home.mode !== "home" && home.mode !== "ready"
        WlrLayershell.namespace: "velum-home-overlay"
        // overlay layer: the top layer is hidden under a fullscreen app
        WlrLayershell.layer: WlrLayer.Overlay
        // the Material App Switcher takes Escape once it stands (never under a finger that still drives
        // it: taking the keyboard ends the pointer's grab)
        WlrLayershell.keyboardFocus: matSwitcher.open && !home.swDragging && !home.zoneFinger ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        mask: Region { item: home.mode === "switcher" || matSwitcher.open ? all : none }
        // the app area's size (a surface being mapped reports 0 for a moment: keep the last real one)
        function measure() { if (width > 0 && height > 0) { home.areaW = width; home.areaH = height } }
        onWidthChanged: if (mine || home.areaW === 0) measure()
        onHeightChanged: if (mine || home.areaH === 0) measure()
        onMineChanged: if (mine) { measure(); home.homeScreenItem = shadowHome; home.coverItem = cover; home.cardRep = cardRepeater; home.switcherItem = matSwitcher }
        Component.onCompleted: if (mine || !home.homeScreenItem) { measure(); home.homeScreenItem = shadowHome; home.coverItem = cover; home.cardRep = cardRepeater; home.switcherItem = matSwitcher }

        Item { id: all; anchors.fill: parent }
        Item { id: none; width: 0; height: 0 }

        Item {
          id: cover
          anchors.fill: parent
          opacity: overlay.shown ? 1 : 0              // clear at rest and until the snapshot is there
          clip: true

          // wallpaper and blur; once the home workspace is on its way the bar's strip stays clear, so
          // the real bar (back over an empty workspace) comes down during the flight
          Item {
            id: backdropBox
            readonly property real stripTop: home.homeSwitchAt > 0 ? per.reserved[1] : 0
            y: stripTop
            width: parent.width
            height: parent.height - stripTop
            clip: true
            Item {
              y: -backdropBox.stripTop
              width: all.width
              height: all.height
              // the wallpaper, as the compositor draws it under the whole screen. Sizes from what fills the
              // window (`all`), never the ShellScreen's: on the iPad cast (HEADLESS-SPARE reshaped from
              // portrait to landscape) that kept 768 wide and the blur ended two thirds across the
              // switcher (Henri 2026-11-06); nor the PanelWindow's own width/height, not its real size here
              Image {
                width: all.width
                height: all.height
                source: "file://" + home.wallpaperLink + (home.wallpaperTarget ? "?v=" + encodeURIComponent(home.wallpaperTarget) : "")
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: per.modelData.width      // the resolution only, as below
                sourceSize.height: per.modelData.height
                asynchronous: false
                cache: true
              }
              // the same home screen as the bottom layer's, on the same spot (below the bar, above the home zone)
              // behind a dragged card: the Material App Switcher's own backdrop (the blurred wallpaper under its
              // tint and scrim), so the hand-over to it changes nothing on screen — the v3 look (sharp, its
              // own blur) stood first and the switcher's blur came over it after the pause (Henri 2026-11-12).
              // Made once into a cached layer: only its opacity changes per frame
              Item {
                id: blurBox
                width: all.width
                height: all.height
                opacity: Math.max(0, Math.min(1, blurV.value))
                visible: opacity > 0.002
                layer.enabled: true
                FolderBackdrop {
                  anchors.fill: parent
                  wallSource: home.wallpaperSource
                  wallRect: Qt.rect(0, 0, width, height)
                  tint: home.mt.switcher.backdropTint
                }
                Rectangle { anchors.fill: parent; color: home.mt.switcher.scrim }
              }
            }
          }
          MaterialHome {
            id: shadowHome
            running: home.runningApps
            wallSource: home.wallpaperSource
            wallRect: Qt.rect(0, -per.reserved[1], all.width, all.height)
            x: 0
            y: per.reserved[1]
            width: overlay.width
            height: overlay.height - per.reserved[1] - per.reserved[3]
            tiles: home.gridTiles
            hotApps: home.dockApps
            layout: home.layout
            entries: home.entries
            openFolder: home.openFolder
            page: home.page
            pageX: pageV.value
            gridOpacity: Math.max(0, Math.min(1, Math.max(homeV.value, home.cfg.switcherHome * switchV.value)))
            gridBlur: home.cfg.switcherHomeBlur * Math.max(0, Math.min(1, switchV.value)) * (1 - Math.max(0, Math.min(1, homeV.value)))
            gridBlurMax: home.cfg.blurMax
            gridScale: home.cfg.homeZoom - (home.cfg.homeZoom - 1) * Math.max(0, Math.min(1, homeV.value))
            dockShift: (1 - Math.max(0, Math.min(1, dockV.value))) * dockTravel
          }
          Rectangle {
            anchors.fill: parent
            color: home.cfg.dimColor
            opacity: home.cfg.dim * Math.max(0, dimV.value)   // 0 since 2026-10-28 (Henri: no grey veil)
            visible: opacity > 0.002
          }
          Rectangle {
            anchors.fill: parent
            color: home.cfg.switcherTintColor
            opacity: home.cfg.switcherTint * Math.max(0, Math.min(1, switchV.value))
            visible: opacity > 0.002
          }
          // the cards stay between gestures (kept by window), and so do their snapshots: a gesture
          // starts on the last one at once and only asks for a fresh one
          Repeater {
            id: cardRepeater
            model: ScriptModel { values: overlay.mine ? home.cards : []; objectProp: "key" }
            Card {
              required property var modelData
              entry: modelData
              areaW: overlay.width
              areaH: overlay.height
              origin: { var m = home.monitorOf(home.screenName), o = m ? m.lastIpcObject : null
                        return o ? Qt.point(o.x || 0, o.y || 0) : Qt.point(0, 0) }
              labelOn: Math.max(0, labelV.value)
              capture: true
            }
          }
        }

        // the App Switcher's fingers: scroll sideways, swipe a card up to close it, tap to open.
        // Real touch through a MultiPointTouchArea: Qt's mouse stand-in for touch never reached the
        // MouseArea here, so on the cast a tap on a card opened nothing and swipes stuck (Henri
        // 2026-11-07, as the home zone found 2026-10-28); a pointer (the rig) through the MouseArea.
        Item {
          id: switcherFinger
          anchors.fill: parent
          readonly property bool on: home.mode === "switcher" && !home.zoneFinger
          property real x0: 0
          property real y0: 0
          property real sx0: 0
          property string axis: ""
          property int hit: -1
          property var samples: []
          function cardAt(x, y) {
            for (var i = home.cards.length - 1; i >= 0; i--) {
              var c = home.card(i)
              if (!c) continue
              var cx = overlay.width / 2 + c.px, cy = overlay.height / 2 + c.py + c.pl
              if (Math.abs(x - cx) <= c.ps * overlay.width / 2 && Math.abs(y - cy) <= c.ps * overlay.height / 2) return i
            }
            return -1
          }
          function down(mx, my) { x0 = mx; y0 = my; sx0 = home.swX; axis = ""; hit = cardAt(mx, my); samples = [[Date.now(), mx, my]] }
          function move(mx, my) { home.guard("switcher move", function () {
            var t = Date.now(), list = samples.concat([[t, mx, my]])
            while (list.length > 2 && t - list[0][0] > home.tt.sampleWindow) list.shift()
            samples = list
            var dx = mx - x0, dy = my - y0
            if (!axis && Math.hypot(dx, dy) > home.tt.slop) axis = Math.abs(dy) > Math.abs(dx) && hit >= 0 ? "y" : "x"
            if (axis === "x") {
              var g = HM.switcherGeo(home.cards.length, overlay.width, overlay.height, home.cfg)
              home.swX = HM.switcherClamp(sx0 + dx, g, home.cfg.edgeInset * 3)
              home.layoutSwitcher(home.swX, true)
            } else if (axis === "y") {
              var c = home.card(hit)
              if (c) c.set("l", dy < 0 ? dy : HM.rubber(dy, home.cfg.pushDown))
            }
          }) }
          function up() { home.guard("switcher up", function () {
            var a = samples[0], b = samples[samples.length - 1], dt = (b[0] - a[0]) / 1000
            var vx = dt > 0 ? (b[1] - a[1]) / dt : 0, vup = dt > 0 ? (a[2] - b[2]) / dt : 0
            if (!axis) { if (hit >= 0) home.openCard(hit, null); else home.switcherHome(); return }
            if (axis === "x") {
              var g = HM.switcherGeo(home.cards.length, overlay.width, overlay.height, home.cfg)
              home.swX = HM.switcherSnap(home.swX, vx, g, home.cfg)
              home.layoutSwitcher(home.swX, false)
              return
            }
            var c = home.card(hit)
            if (!c) return
            if (-c.pl > overlay.height * home.cfg.closeTravel || vup > home.cfg.closeFlick) home.closeCard(hit)
            else c.to("l", 0, "snappy")
          }) }
          function cancel() { if (axis === "x") home.layoutSwitcher(home.swX, false) }
          MultiPointTouchArea {
            anchors.fill: parent
            enabled: switcherFinger.on
            maximumTouchPoints: 1
            mouseEnabled: false
            onPressed: function (pts) { switcherFinger.down(pts[0].x, pts[0].y) }
            onUpdated: function (pts) { switcherFinger.move(pts[0].x, pts[0].y) }
            onReleased: function (pts) { switcherFinger.up() }
            onCanceled: switcherFinger.cancel()
          }
          MouseArea {
            anchors.fill: parent
            enabled: switcherFinger.on
            preventStealing: true
            onPressed: function (m) { switcherFinger.down(m.x, m.y) }
            onPositionChanged: function (m) { switcherFinger.move(m.x, m.y) }
            onReleased: function (m) { switcherFinger.up() }
            onCanceled: switcherFinger.cancel()
          }
        }

        // the Material App Switcher (phase 5): the screen's windows in a row over the blurred wallpaper;
        // closed it is an empty Loader (no captures). Driven by swProgress / swDragging.
        MaterialSwitcher {
          id: matSwitcher
          anchors.fill: parent
          screenName: per.name
          progress: overlay.mine ? home.swProgress : 0
          dragging: overlay.mine && home.swDragging
          warm: overlay.mine && home.gestureFinger
          keep: overlay.mine && home.active
          handoff: home.settleMs
          appFor: function (cls) { var id = home.appIdOf(cls), e = home.entries[id]; return e ? { name: e.name, icon: e.icon } : null }
          backdrop: Component {
            FolderBackdrop {
              wallSource: home.wallpaperSource
              wallRect: Qt.rect(0, 0, width, height)
              tint: home.mt.switcher.backdropTint
            }
          }
          onSwitchTo: function (address) { home.guard("switchTo", function () { home.switchToWindow(address) }) }
          onCloseWindow: function (address) { home.guard("closeWindow", function () { home.closeWindow(address) }) }
          onClosed: { home.swDragging = false; home.swProgress = 0 }
          // its card stands where the app's card rests: that one goes at once
          onHandTaken: { for (var i = 0; i < home.cards.length; i++) { var c = home.card(i); if (c) c.set("o", 0) } }
        }
      }
    }
  }
}
