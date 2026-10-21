import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import "file:///home/henri/.local/share/velum/qml/Velum"
import "LayoutModel.js" as LM
import "FuzzySearch.js" as Fuzzy
import "AppAliases.js" as AppAliases
import "Look.js" as Look

// Launchpad on Velum: every app full screen on the blurred wallpaper, paged,
// type to search, folders, edit mode with drag and drop. Spec:
// ~/Projects/launchpad/replica (recon, architecture, design/components.md).
//
// One pointer handler over the whole overlay does all hit-testing against the
// grid geometry (no MouseArea per tile), so a drag keeps going when the
// folder it started in closes, and tiles stay cheap.
Item {
  id: root

  // ------------------------------------------------------------- host API
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    // {"screen":"NAME"} opens on that output instead of the focused one (tests)
    root.forcedScreen = typeof payload.screen === "string" ? payload.screen : ""
    if (!root.opened) root.show()
    if (typeof payload.query === "string") root.setQuery(payload.query)
  }
  function close() { root.hideAnimated(false) }

  // shell `call henri.launchpad-v3 <method> <arg>` — for tests, screenshots and binds
  function toggle() { if (root.opened) root.hideAnimated(false); else root.show(); return "ok" }
  function reload() { layoutFile.reload(); return "ok" }
  function state() {
    return JSON.stringify({
      opened: root.opened, openness: Math.round(root.openness * 100) / 100, page: root.page, pages: root.pageCount, editing: root.editing,
      folder: root.openFolder, query: root.query, results: root.results.length, selected: root.selIndex,
      apps: root.desktopIds.length, readOnly: root.readOnly, error: root.loadError,
      settingsOpen: root.settingsOpen, menu: contextMenu.open, menuItems: contextMenu.open ? contextMenu.model.map(function(m) { return m.text || "-" }) : [],
      dragId: root.dragId, armed: root.armedTarget, hover: root.hoverTarget, drag: [Math.round(root.dragX), Math.round(root.dragY)], hidden: root.layout.hidden.length, lastLaunch: root.lastLaunch,
      folderTitle: root.openFolder !== "" && root.layout.folders[LM.folderKey(root.openFolder)] ? root.layout.folders[LM.folderKey(root.openFolder)].name : "",
      screen: win.screen ? win.screen.name : "", screens: Quickshell.screens.map(function(s) { return s.name }), forced: root.forcedScreen, scrim: Math.round(root.scrimAlpha * 100) / 100
    })
  }
  function setQuery(q) { search.text = String(q || ""); return "ok" }
  function goPage(n) { root.setPage(parseInt(n) || 0); return "ok" }
  function edit(on) { root.editing = String(on) !== "false"; return "ok" }
  function folderOpen(id) { if (String(id || "") === "") root.closeFolder(); else root.openFolderById(String(id)); return "ok" }
  function select(n) { root.selIndex = parseInt(n); return "ok" }
  function showSettings(on) { root.settingsOpen = String(on) !== "false"; return "ok" }
  function entryInfo(id) { return JSON.stringify(root.entries[String(id)] || null) }
  function layoutJson() { return LM.serialize(root.layout) }
  // test drags without a pointer: "app:x page index" or "app:x onto app:y"
  function testMove(arg) {
    var p = String(arg || "").split(" ")
    if (p[1] === "onto") { root.commit(LM.dropOnto(root.layout, p[0], p[2], root.folderNameFor(p[2]))); return "ok" }
    root.commit(LM.move(root.layout, p[0], parseInt(p[1]), parseInt(p[2])))
    return "ok"
  }
  // centre of a tile's icon in window pixels ("x y"), for the pointer tests
  function tileCenter(id) {
    var at = root.slots[String(id)]
    if (root.openFolder !== "") {
      var items = (root.layout.folders[LM.folderKey(root.openFolder)] || { items: [] }).items
      var fi = items.indexOf(String(id))
      if (fi >= 0) { var r = folderPanel.cellRect(fi); return Math.round(r.x + folderPanel.cellW / 2) + " " + Math.round(r.y + root.iconSize / 2) }
    }
    if (!at) return ""
    var p = root.slotPos(at.page, at.index)
    return Math.round(p.x - at.page * win.width + root.cellW / 2) + " " + Math.round(p.y + root.iconSize / 2)
  }
  function testHide(id) { root.commit(LM.hide(root.layout, String(id))); return "ok" }
  function testUnhide(id) { root.commit(LM.unhide(root.layout, String(id))); return "ok" }
  function testContext(id) {
    root.openContext(String(id || ""), win.width / 2, win.height / 2)
    return "ok"
  }

  // ----------------------------------------------------------------- state
  readonly property var lp: Theme.core.surface.launchpad
  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string layoutDir: home + "/.config/omarchy/launchpad"
  readonly property string layoutPath: layoutDir + "/layout.json"

  property var layout: LM.empty()
  property bool layoutReady: false
  property bool readOnly: false          // the file could not be parsed: never overwrite it
  property string loadError: ""
  property var entries: ({})             // app id -> { name, icon, generic, keywords, categories, desktopId }
  property var desktopIds: []            // installed, sorted by name
  property var missingOnce: ({})         // app ids gone in one scan; dropped only if still gone on the next
  property var aliasTable: AppAliases.defaultTable()

  property string query: search.text.trim()
  property var results: []
  property int selIndex: -1              // grid: index on the current page; search: row
  property int page: 0
  property bool editing: false
  property string openFolder: ""
  property bool settingsOpen: false
  property bool shown: false             // window mapped (open or closing)
  property bool launching: false

  readonly property var settings: layout.settings
  readonly property int cols: settings.columns
  readonly property int rows: settings.rows
  readonly property int perPage: cols * rows
  readonly property int pageCount: layout.pages.length + (dragId !== "" && dragFrom === "grid" ? 1 : 0)

  // ------------------------------------------------------------- geometry
  readonly property real gridX: win.width * Look.grid.marginX
  readonly property real gridY: win.height * Look.grid.marginTop
  readonly property real gridW: win.width * (1 - 2 * Look.grid.marginX)
  readonly property real gridH: win.height * (1 - Look.grid.marginTop - Look.grid.marginBottom)
  readonly property real cellW: gridW / cols
  readonly property real cellH: gridH / rows
  readonly property real iconSize: Math.min(settings.iconSize, cellW * 0.8, (cellH - (settings.showTitles ? Look.grid.labelGap + Theme.core.type.callout * 1.6 : 0)) * 0.9) // lint-ok: fit factors

  function slotPos(pageIndex, index) {
    return {
      x: pageIndex * win.width + root.gridX + (index % root.cols) * root.cellW,
      y: root.gridY + Math.floor(index / root.cols) * root.cellH
    }
  }

  // ------------------------------------------------------------ apps index
  function scanEntries() {
    var values = []
    try { values = DesktopEntries.applications.values || [] } catch (e) { values = [] }
    var map = {}
    var list = []
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      if (!e || e.noDisplay) continue
      var did = String(e.id || "")
      if (did.slice(-8) === ".desktop") did = did.slice(0, -8)
      if (!did || map["app:" + did] || root.systemHidden[did]) continue
      map["app:" + did] = {
        desktopId: did, name: String(e.name || did), icon: String(e.icon || ""),
        generic: String(e.genericName || ""), keywords: (e.keywords || []).map(String),
        categories: (e.categories || []).map(String)
      }
      list.push(did)
    }
    list.sort(function(a, b) { return map["app:" + a].name.localeCompare(map["app:" + b].name) })
    return { map: map, list: list }
  }

  function syncApps() {
    if (!root.hidesReady) return                // Omarchy's hidden list first, or hidden apps get placed
    var scan = root.scanEntries()
    if (scan.list.length === 0) return          // DesktopEntries not ready yet; try again on its change
    // an app missing in one scan stays one more round (package updates churn the entries)
    var now = {}
    for (var i = 0; i < scan.list.length; i++) now["app:" + scan.list[i]] = true
    var keepIds = scan.list.slice()
    var nextMissing = {}
    for (var j = 0; j < root.desktopIds.length; j++) {
      var id = "app:" + root.desktopIds[j]
      if (!now[id] && !root.missingOnce[id] && root.entries[id]) {
        nextMissing[id] = true
        keepIds.push(root.desktopIds[j])
        scan.map[id] = root.entries[id]
      }
    }
    root.missingOnce = nextMissing
    if (Object.keys(nextMissing).length > 0) recheck.restart()
    root.entries = scan.map
    root.desktopIds = keepIds
    if (!root.layoutReady) { root.applyPending(); return }
    var next = LM.sync(root.layout, keepIds)
    if (JSON.stringify(next) !== JSON.stringify(root.layout)) root.commit(next)
  }

  // Omarchy's own launcher hides (the same list Spotlight uses): the configured
  // file plus desktop entries hidden for this desktop (Hidden=, OnlyShowIn=…)
  readonly property string omarchyBase: String(root.omarchyPath || "") || "/usr/share/omarchy"
  property var systemHidden: ({})
  property bool hidesReady: false
  property string configuredHides: ""
  property string scannedHides: ""
  FileView {
    path: root.omarchyBase + "/default/omarchy/launcher.hides"
    printErrors: false
    onLoaded: { root.configuredHides = text(); hidesScan.running = true }
    onLoadFailed: { root.configuredHides = ""; hidesScan.running = true }
  }
  Process {
    id: hidesScan
    command: ["bash", root.omarchyBase + "/shell/services/hidden-entries.sh",
      [Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")].filter(function(v) { return String(v || "").length > 0 }).join(":")]
    stdout: StdioCollector { onStreamFinished: { root.scannedHides = text; root.applyHides() } }
    onExited: function(code) { if (code !== 0) root.applyHides() }
  }
  function applyHides() {
    var next = {}
    var lines = (root.configuredHides + "\n" + root.scannedHides).split("\n")
    for (var i = 0; i < lines.length; i++) {
      var id = lines[i].trim()
      if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
      if (id && id.charAt(0) !== "#") next[id] = true
    }
    root.systemHidden = next
    root.hidesReady = true
    root.syncApps()
  }

  Timer { id: entriesDebounce; interval: 1000; onTriggered: root.syncApps() }  // lint-ok: churn debounce
  Timer { id: recheck; interval: 3000; onTriggered: root.syncApps() }          // lint-ok: second look
  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { entriesDebounce.restart() }
  }

  function iconFor(id) {
    var o = root.layout.apps[id]
    var value = o && o.icon ? o.icon : (root.entries[id] ? root.entries[id].icon : "")
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    var themed = value ? Quickshell.iconPath(value, true) : ""
    return themed || Quickshell.iconPath("application-x-executable", true)
  }
  function titleFor(id) {
    if (LM.isFolder(id)) { var f = root.layout.folders[LM.folderKey(id)]; return f ? f.name : "" }
    var o = root.layout.apps[id]
    if (o && o.name) return o.name
    return root.entries[id] ? root.entries[id].name : id.slice(4)
  }
  function folderNameFor(targetId) {
    var e = root.entries[targetId]
    var names = { AudioVideo: "Media", Audio: "Media", Video: "Media", Development: "Development",
      Education: "Education", Game: "Games", Graphics: "Graphics", Network: "Internet", Office: "Office",
      Science: "Science", Settings: "Settings", System: "System", Utility: "Utilities" }
    if (e) for (var i = 0; i < e.categories.length; i++) if (names[e.categories[i]]) return names[e.categories[i]]
    return "Folder"
  }

  // ---------------------------------------------------------- persistence
  Process { id: mkdir; command: ["mkdir", "-p", root.layoutDir] }
  Process { id: backupProc }

  FileView {
    id: layoutFile
    path: root.layoutPath
    blockLoading: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyFile(layoutFile.text())
    onLoadFailed: function(err) { root.applyFile("") }
  }

  // The file waits for the app list: loading against an empty list would
  // drop every app from the layout (and the next save would make that stick).
  property var pendingText: null
  function applyFile(text) {
    root.pendingText = String(text || "")
    if (root.desktopIds.length === 0) root.syncApps()
    if (root.desktopIds.length === 0) return
    root.applyPending()
  }
  function applyPending() {
    if (root.pendingText === null) return
    var text = root.pendingText
    root.pendingText = null
    var r = LM.load(text, root.desktopIds)
    root.loadError = r.error
    root.readOnly = r.error !== ""
    if (r.backup) {
      backupProc.command = ["cp", "-f", root.layoutPath, root.layoutPath + ".bak-" + Date.now()]
      backupProc.running = true
    }
    root.layout = r.layout
    root.layoutReady = true
    root.rebuildTiles()
    if (root.loadError) toast.say("Layout file unreadable — changes are not saved")
    else if (LM.serialize(r.layout) !== text) saveSoon.restart()
  }

  Timer { id: saveSoon; interval: 300; onTriggered: root.save() }  // lint-ok: write debounce
  function save() {
    if (root.readOnly || !root.layoutReady) return
    mkdir.running = true
    layoutFile.setText(LM.serialize(root.layout))
  }

  function commit(next) {
    delete next.lastFolder
    root.layout = next
    root.rebuildTiles()
    saveSoon.restart()
  }

  // user alias words (~/.config/omarchy/app-aliases.jsonc), same file Spotlight reads
  FileView {
    path: root.home + "/.config/omarchy/app-aliases.jsonc"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.aliasTable = AppAliases.tableFrom(text(), root.stripJsonc)
    onLoadFailed: root.aliasTable = AppAliases.defaultTable()
  }
  function stripJsonc(raw) {
    return String(raw || "").replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:"\\])\/\/.*$/gm, "$1").replace(/,(\s*[}\]])/g, "$1")
  }

  // ----------------------------------------------------- tiles (stable)
  // One ListModel row per grid item, keyed by id, so a layout change moves
  // tiles (their springs glide) instead of recreating them.
  ListModel { id: tiles }
  property var slots: ({})               // id -> { page, index }
  property int tilesRev: 0

  function rebuildTiles() {
    var want = {}
    var s = {}
    for (var p = 0; p < root.layout.pages.length; p++)
      for (var i = 0; i < root.layout.pages[p].length; i++) {
        want[root.layout.pages[p][i]] = true
        s[root.layout.pages[p][i]] = { page: p, index: i }
      }
    // a dragged app that is inside a folder still needs its tile on the grid
    if (root.dragId !== "" && !s[root.dragId]) want[root.dragId] = true
    for (var k = tiles.count - 1; k >= 0; k--) if (!want[tiles.get(k).tid]) tiles.remove(k)
    var have = {}
    for (var m = 0; m < tiles.count; m++) have[tiles.get(m).tid] = true
    for (var id in want) if (!have[id]) tiles.append({ tid: id })
    root.slots = s
    root.tilesRev++
    if (root.page >= root.layout.pages.length) root.setPage(root.layout.pages.length - 1)
  }

  function itemAt(pageIndex, index) {
    var pg = root.layout.pages[pageIndex]
    return pg && index >= 0 && index < pg.length ? pg[index] : ""
  }

  // ------------------------------------------------------------- search
  onQueryChanged: { root.runSearch(); root.selIndex = root.query !== "" ? 0 : -1 }
  function runSearch() {
    if (root.query === "") { root.results = []; return }
    var folderOf = {}
    for (var key in root.layout.folders) {
      var f = root.layout.folders[key]
      for (var i = 0; i < f.items.length; i++) folderOf[f.items[i]] = f.name
    }
    var hidden = {}
    for (var h = 0; h < root.layout.hidden.length; h++) hidden[root.layout.hidden[h]] = true
    var rows = []
    for (var d = 0; d < root.desktopIds.length; d++) {
      var id = "app:" + root.desktopIds[d]
      var e = root.entries[id]
      if (!e) continue
      rows.push({
        id: id, title: root.titleFor(id), domain: e.generic,
        tags: e.keywords.concat(e.categories, folderOf[id] ? [folderOf[id]] : []).concat(e.name !== root.titleFor(id) ? [e.name] : []),
        aliases: AppAliases.aliasesFor(root.aliasTable, e.desktopId, e.name),
        hiddenApp: hidden[id] === true, folderName: folderOf[id] || ""
      })
    }
    root.results = Fuzzy.search(root.query, rows).slice(0, Look.results.maxRows)
  }

  // -------------------------------------------------------------- launch
  // In a test rig nothing is started: uwsm-app would open the app in the live session.
  readonly property bool inRig: (Quickshell.env("VELUM_SHELL_RIG") || "") !== ""
  property string lastLaunch: ""
  function launch(id) {
    var e = root.entries[id]
    if (!e) return
    root.lastLaunch = id
    if (!root.inRig) Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", e.desktopId + ".desktop"])
    root.hideAnimated(true)
  }
  function activate(id) {
    if (LM.isFolder(id)) root.openFolderById(id)
    else if (LM.isApp(id)) root.launch(id)
  }

  // --------------------------------------------------------- open / close
  property real progress: 0              // 0 closed … 1 open
  Spring {
    id: openSpring
    preset: root.lp.open
    reduced: Theme.reduceMotion
    target: 0
  }
  NumberAnimation {
    id: closeAnim
    target: root; property: "closeProgress"
    duration: root.lp.close
    easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("exit")
    onFinished: { root.shown = false; root.launching = false }
  }
  property real closeProgress: 1         // multiplies the spring while closing
  readonly property real openness: Math.max(0, Math.min(1, openSpring.value)) * closeProgress

  function show() {
    closeAnim.stop()
    root.closeProgress = 1
    root.launching = false
    root.pickScreen()
    root.refreshWallpaper()
    root.opened = true
    root.shown = true
    root.editing = false
    root.openFolder = ""
    root.settingsOpen = false
    search.text = ""
    root.selIndex = -1
    // from(): the target may already be 1, so setting it alone would start nothing
    openSpring.target = 1
    openSpring.from(0)
    search.forceActiveFocus()
  }
  function hideAnimated(launch) {
    if (!root.opened) return
    root.opened = false
    root.launching = launch === true
    root.cancelDrag()
    root.contextId = ""
    contextMenu.open = false
    closeAnim.from = 1; closeAnim.to = 0
    if (Theme.reduceMotion) closeAnim.duration = Theme.dur("fast")
    closeAnim.restart()
    if (root.shell && root.manifest && typeof root.shell.hide === "function") Qt.callLater(function() {
      if (!root.opened) root.shell.hide(root.manifest.id)
    })
  }

  property string forcedScreen: ""
  function pickScreen() {
    var mon = Hyprland.focusedMonitor
    var screens = Quickshell.screens
    if (root.forcedScreen !== "")
      for (var j = 0; j < screens.length; j++) if (screens[j].name === root.forcedScreen) { win.screen = screens[j]; return }
    for (var i = 0; i < screens.length; i++)
      if (mon && screens[i].name === mon.name) { win.screen = screens[i]; return }
    if (screens.length > 0) win.screen = screens[0]
  }

  // ----------------------------------------------------------- wallpaper
  readonly property string wallpaperLink: home + "/.local/state/omarchy/current/background"
  property string wallpaperToken: ""
  readonly property string wallpaperSource: {
    var w = root.settings.wallpaper
    if (w.kind === "image" && w.path) return "file://" + w.path
    return "file://" + root.wallpaperLink + (root.wallpaperToken ? "?v=" + encodeURIComponent(root.wallpaperToken) : "")
  }
  function refreshWallpaper() { if (!wallpaperProbe.running) wallpaperProbe.running = true }
  Process {
    id: wallpaperProbe
    command: ["/bin/sh", root.pluginDir + "/bin/wallpaper-token"]
    clearEnvironment: true
    environment: ({ "HOME": root.home })
    stdout: StdioCollector { onStreamFinished: root.wallpaperToken = String(text || "").trim().slice(0, 128) }
  }

  // mean brightness of the wallpaper (0..1), measured once per picture
  property real wallpaperBrightness: 0.5
  readonly property real scrimAlpha: root.settings.wallpaper.kind === "solid" ? 1
    : Math.max(root.lp.scrimMin, Math.min(root.lp.scrimMax, 1 - root.lp.scrimTarget / Math.max(root.wallpaperBrightness, root.lp.scrimTarget)))

  // ------------------------------------------------------------- pages
  property real swipePos: 0
  property bool swiping: false
  Spring { id: pageSpring; preset: root.lp.page; reduced: Theme.reduceMotion; target: root.page }
  readonly property real pagePos: swiping ? swipePos : pageSpring.value

  function setPage(n) {
    root.page = Math.max(0, Math.min(root.pageCount - 1, n))
    if (root.query === "") root.selIndex = root.selIndex >= 0 ? Math.min(root.selIndex, Math.max(0, (root.layout.pages[root.page] || []).length - 1)) : -1
  }
  function rubber(pos) {
    var maxP = root.pageCount - 1
    if (pos < 0) return -(1 - 1 / (-pos * root.lp.rubberBand + 1)) / root.lp.rubberBand
    if (pos > maxP) return maxP + (1 - 1 / ((pos - maxP) * root.lp.rubberBand + 1)) / root.lp.rubberBand
    return pos
  }
  // settle after a swipe, starting with the release velocity (pages/s)
  function settle(velocity) {
    var target = Math.round(root.swipePos)
    if (Math.abs(velocity) * win.width / 1000 > root.lp.pageFlick)
      target = velocity > 0 ? Math.floor(root.swipePos) + 1 : Math.ceil(root.swipePos) - 1
    target = Math.max(0, Math.min(root.pageCount - 1, target))
    target = Math.max(root.page - 1, Math.min(root.page + 1, target))   // never more than one page per gesture
    pageSpring.snap(root.swipePos)
    pageSpring.velocity = velocity
    root.swiping = false
    root.page = target
    if (pageSpring.value !== pageSpring.target) pageSpring.anim.start()
  }

  // touchpad: pixel deltas follow the fingers; wheel: one page per notch
  property real wheelVelocity: 0
  property real lastWheelTime: 0
  property real wheelCooldown: 0
  function onWheelEvent(wheel) {
    if (root.query !== "" || root.openFolder !== "" || root.settingsOpen) return
    var now = Date.now()
    if (wheel.pixelDelta.x !== 0 || wheel.pixelDelta.y !== 0) {
      var dx = Math.abs(wheel.pixelDelta.x) >= Math.abs(wheel.pixelDelta.y) ? wheel.pixelDelta.x : wheel.pixelDelta.y
      if (!root.swiping) { root.swipePos = pageSpring.value; root.swiping = true; root.wheelVelocity = 0 }
      var raw = root.swipeRaw - dx / win.width
      root.swipeRaw = raw
      root.swipePos = root.rubber(raw)
      var dt = Math.max(1, now - root.lastWheelTime)
      root.wheelVelocity = 0.6 * root.wheelVelocity + 0.4 * (-dx / win.width) / (dt / 1000) // lint-ok: smoothing
      root.lastWheelTime = now
      wheelEnd.restart()
    } else if (now > root.wheelCooldown) {
      var d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
      root.setPage(root.page + (d < 0 ? 1 : -1))
      root.wheelCooldown = now + Theme.dur("slow")
    }
  }
  property real swipeRaw: 0
  onSwipingChanged: if (swiping) swipeRaw = swipePos
  Timer { id: wheelEnd; interval: 120; onTriggered: if (root.swiping) root.settle(root.wheelVelocity) } // lint-ok: gesture end

  // --------------------------------------------------------------- edit
  property real jiggleClock: 0
  FrameAnimation {
    running: root.editing && root.shown && !Theme.reduceMotion
    onTriggered: root.jiggleClock += frameTime * 1000
  }
  function jiggleFor(id) {
    if (!root.editing || Theme.reduceMotion) return 0
    var h = 0
    for (var i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) % 1000
    return root.lp.jiggleAngle * Math.sin(2 * Math.PI * root.jiggleClock / root.lp.jigglePeriod + h)
  }

  // --------------------------------------------------------------- drag
  property string dragId: ""
  property string dragFrom: ""           // "grid" | "folder"
  property real dragX: 0                 // pointer, window coordinates
  property real dragY: 0
  property real grabX: 0                 // pointer offset inside the tile
  property real grabY: 0
  property var baseLayout: null
  property string armedTarget: ""        // folder drop armed on this id
  property string hoverTarget: ""
  property string lastPreview: ""
  property int edgeDir: 0

  Timer {
    id: folderTimer
    interval: root.lp.folderHover
    onTriggered: root.armedTarget = root.hoverTarget
  }
  property var pendingSlot: null         // { page, to, key } waiting for reorderTimer
  Timer {
    id: reorderTimer
    interval: root.lp.reorderHover
    onTriggered: {
      var ps = root.pendingSlot
      if (!ps || root.dragId === "" || ps.key === root.lastPreview) return
      root.lastPreview = ps.key
      root.layout = LM.move(root.baseLayout, root.dragId, ps.page, ps.to)
      root.rebuildTiles()
    }
  }
  Timer {
    id: edgeTimer
    interval: root.lp.edgeHover
    repeat: true
    onTriggered: if (root.edgeDir !== 0) { root.setPage(root.page + root.edgeDir); root.lastPreview = "" }
  }

  function beginDrag(id, from, px, py, ox, oy) {
    root.dragId = id
    root.dragFrom = from
    root.baseLayout = root.layout
    root.dragX = px; root.dragY = py
    root.grabX = ox; root.grabY = oy
    root.armedTarget = ""; root.hoverTarget = ""; root.lastPreview = ""; root.pendingSlot = null
    root.rebuildTiles()
  }

  function dragMove(px, py) {
    root.dragX = px; root.dragY = py
    if (root.dragFrom === "folder") {
      if (folderPanel.contains(px, py)) {
        var fi = folderPanel.indexAt(px, py)
        var key = "f" + fi
        if (fi >= 0 && key !== root.lastPreview) {
          root.lastPreview = key
          root.layout = LM.moveInFolder(root.baseLayout, root.openFolder, root.dragId, fi)
          root.tilesRev++
        }
        return
      }
      // left the panel: the folder closes, the app goes on as a grid drag
      root.dragFrom = "grid"
      root.baseLayout = root.layout
      root.openFolder = ""
      root.lastPreview = ""
    }
    // page edges
    var dir = px < Look.grid.edgeZone ? -1 : (px > win.width - Look.grid.edgeZone ? 1 : 0)
    if (dir !== root.edgeDir) { root.edgeDir = dir; if (dir !== 0) edgeTimer.restart(); else edgeTimer.stop() }
    if (dir !== 0) return

    var col = Math.floor((px - root.gridX) / root.cellW)
    var row = Math.floor((py - root.gridY) / root.cellH)
    if (col < 0 || col >= root.cols || row < 0 || row >= root.rows) { root.disarm(); return }
    var index = row * root.cols + col
    // over the middle of another tile: arm a folder drop instead of reordering
    var under = root.itemAt(root.page, index)
    var c = root.slotPos(root.page, index)
    var cx = c.x - root.page * win.width + root.cellW / 2, cy = c.y + root.iconSize / 2
    var near = Math.abs(px - cx) < root.iconSize * 0.3 && Math.abs(py - cy) < root.iconSize * 0.3 // lint-ok: drop zone
    if (under && under !== root.dragId && near && LM.isApp(root.dragId)) {
      reorderTimer.stop()
      if (root.hoverTarget !== under) { root.hoverTarget = under; root.armedTarget = ""; folderTimer.restart() }
      return
    }
    root.disarm()
    var len = (root.baseLayout.pages[root.page] || []).filter(function(x) { return x !== root.dragId }).length
    var to = Math.min(index, len)
    var key2 = root.page + ":" + to
    if (key2 === root.lastPreview) { reorderTimer.stop(); return }
    // the icons make room only once the pointer rests on the slot
    if (!root.pendingSlot || root.pendingSlot.key !== key2) {
      root.pendingSlot = { page: root.page, to: to, key: key2 }
      reorderTimer.restart()
    }
  }
  function disarm() { folderTimer.stop(); root.hoverTarget = ""; root.armedTarget = "" }

  function endDrag() {
    if (root.dragId === "") return
    var id = root.dragId
    // a drop before the icons made room still lands on the slot under the pointer
    if (reorderTimer.running) { reorderTimer.stop(); reorderTimer.triggered() }
    root.pendingSlot = null
    edgeTimer.stop(); root.edgeDir = 0
    var next = root.layout
    if (root.armedTarget !== "") next = LM.dropOnto(root.baseLayout, id, root.armedTarget, root.folderNameFor(root.armedTarget))
    root.disarm()
    root.dragId = ""; root.dragFrom = ""; root.baseLayout = null
    root.commit(next)
  }
  function cancelDrag() {
    if (root.dragId === "") return
    reorderTimer.stop(); root.pendingSlot = null
    var base = root.baseLayout
    edgeTimer.stop(); root.edgeDir = 0; root.disarm()
    root.dragId = ""; root.dragFrom = ""; root.baseLayout = null
    if (base) { root.layout = base; root.rebuildTiles() }
  }

  // ------------------------------------------------------------ folders
  property var folderFrom: ({ x: 0, y: 0, w: 1, h: 1 })   // tile rect the panel grows from
  function openFolderById(id) {
    if (!LM.isFolder(id) || !root.layout.folders[LM.folderKey(id)]) return
    var at = root.slots[id]
    if (at) {
      var p = root.slotPos(at.page, at.index)
      root.folderFrom = { x: p.x - root.pagePos * win.width + (root.cellW - root.iconSize) / 2, y: p.y, w: root.iconSize, h: root.iconSize }
    }
    root.openFolder = id
    root.selIndex = -1
  }
  function closeFolderFocus() { search.forceActiveFocus() }
  function closeFolder() {
    if (root.openFolder === "") return
    folderPanel.commitTitle()
    root.openFolder = ""
    search.forceActiveFocus()
  }

  // ------------------------------------------------------- context menu
  property string contextId: ""
  function openContext(id, px, py) {
    root.contextId = id === "" ? "empty" : id
    var m = []
    if (LM.isApp(id)) m = [{ text: "Open", act: "open" }, { separator: true }, { text: "Hide", act: "hide" }]
    else if (LM.isFolder(id)) m = [{ text: "Open", act: "open" }, { text: "Rename", act: "rename" }, { separator: true }, { text: "Ungroup", act: "ungroup" }]
    else m = [{ text: root.editing ? "Done Editing" : "Edit Layout", act: "edit" }, { text: "Settings…", act: "settings" },
              { separator: true }, { text: "Sort by Name", act: "reset" }]
    contextMenu.model = m
    contextMenu.x = Math.min(px, win.width - contextMenu.width)
    contextMenu.y = Math.min(py, win.height - contextMenu.height)
    contextMenu.highlighted = -1
    contextMenu.open = true
  }
  function runContext(act) {
    var id = root.contextId
    contextMenu.open = false
    root.contextId = ""
    if (act === "open") root.activate(id)
    else if (act === "hide") root.commit(LM.hide(root.layout, id))
    else if (act === "rename") { root.openFolderById(id); Qt.callLater(folderPanel.startRename) }
    else if (act === "ungroup") root.commit(LM.ungroup(root.layout, id))
    else if (act === "edit") root.editing = !root.editing
    else if (act === "settings") root.settingsOpen = true
    else if (act === "reset") root.commit(LM.reset(root.layout, root.desktopIds))
    search.forceActiveFocus()
  }

  // ------------------------------------------------------------ keyboard
  function keyPressed(event) {
    var k = event.key
    if (k === Qt.Key_Escape) {
      event.accepted = true
      if (contextMenu.open) { contextMenu.open = false; return }
      if (root.settingsOpen) { root.settingsOpen = false; return }
      if (root.dragId !== "") { root.cancelDrag(); return }
      if (search.text !== "") { search.text = ""; return }
      if (root.openFolder !== "") { root.closeFolder(); return }
      if (root.editing) { root.editing = false; return }
      root.hideAnimated(false)
      return
    }
    if (contextMenu.open) {
      if (k === Qt.Key_Down || k === Qt.Key_Up) { contextMenu.step(k === Qt.Key_Down ? 1 : -1); event.accepted = true }
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (contextMenu.highlighted >= 0) contextMenu.choose(contextMenu.highlighted); event.accepted = true }
      return
    }
    if (root.query !== "") {
      if (k === Qt.Key_Down) { root.selIndex = Math.min(root.results.length - 1, root.selIndex + 1); event.accepted = true }
      else if (k === Qt.Key_Up) { root.selIndex = Math.max(0, root.selIndex - 1); event.accepted = true }
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
        var r = root.results[Math.max(0, root.selIndex)]
        if (r) root.launch(r.id)
        event.accepted = true
      }
      return
    }
    // grid / folder navigation
    var list = root.openFolder !== "" ? (root.layout.folders[LM.folderKey(root.openFolder)] || { items: [] }).items : (root.layout.pages[root.page] || [])
    var cols = root.openFolder !== "" ? root.settings.folderGrid[0] : root.cols
    var s = root.selIndex
    if (k === Qt.Key_Right || k === Qt.Key_Left || k === Qt.Key_Down || k === Qt.Key_Up) {
      event.accepted = true
      if (s < 0) { root.selIndex = 0; return }
      var step = k === Qt.Key_Right ? 1 : k === Qt.Key_Left ? -1 : k === Qt.Key_Down ? cols : -cols
      var n = s + step
      if (root.openFolder === "" && (k === Qt.Key_Right || k === Qt.Key_Left)) {
        if (n >= list.length && root.page < root.layout.pages.length - 1) { root.setPage(root.page + 1); root.selIndex = 0; return }
        if (n < 0 && root.page > 0) { root.setPage(root.page - 1); root.selIndex = (root.layout.pages[root.page] || []).length - 1; return }
      }
      if (n >= 0 && n < list.length) root.selIndex = n
      return
    }
    if (k === Qt.Key_PageDown) { root.setPage(root.page + 1); event.accepted = true; return }
    if (k === Qt.Key_PageUp) { root.setPage(root.page - 1); event.accepted = true; return }
    if ((k === Qt.Key_Return || k === Qt.Key_Enter) && s >= 0 && s < list.length) { root.activate(list[s]); event.accepted = true }
  }

  // ===================================================================== UI
  PanelWindow {
    id: win
    visible: root.shown
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "launchpad"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    VelumSettings {}

    Item {
      id: stage
      anchors.fill: parent

      // ---- backdrop: the wallpaper, blurred in-window, darkened by the adaptive scrim
      Item {
        id: backdrop
        anchors.fill: parent
        opacity: root.openness
        Rectangle { anchors.fill: parent; color: root.lp.scrim }
        Image {
          id: wallpaper
          anchors.fill: parent
          visible: root.settings.wallpaper.kind !== "solid" && !Theme.reduceTransparency
          source: root.shown || root.layoutReady ? root.wallpaperSource : ""
          sourceSize.width: Math.ceil(win.width / 2); sourceSize.height: Math.ceil(win.height / 2)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          layer.enabled: true
          layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 64
            blur: root.settings.wallpaper.blur / 100
            saturation: 0.1
            autoPaddingEnabled: false
          }
          onStatusChanged: if (status === Image.Ready) brightness.measure()
        }
        Rectangle {
          anchors.fill: parent
          color: root.lp.scrim
          opacity: Theme.reduceTransparency ? 1 : root.scrimAlpha
        }
      }

      // measures the mean brightness of the wallpaper on a tiny canvas
      Canvas {
        id: brightness
        width: 16; height: 9; visible: false  // lint-ok: sample size
        renderStrategy: Canvas.Immediate
        property string url: ""
        function measure() {
          url = root.wallpaperSource
          if (isImageLoaded(url)) requestPaint(); else loadImage(url)
        }
        onImageLoaded: requestPaint()
        onPaint: {
          if (!url || !isImageLoaded(url)) return
          var ctx = getContext("2d")
          ctx.drawImage(url, 0, 0, width, height)
          var d = ctx.getImageData(0, 0, width, height).data
          var sum = 0
          for (var i = 0; i < d.length; i += 4) sum += (0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]) / 255 // lint-ok: Rec. 709 luma
          root.wallpaperBrightness = sum / (d.length / 4)
        }
      }

      // ---- content: search, pages, dots
      Item {
        id: content
        anchors.fill: parent
        opacity: root.openness
        scale: Theme.reduceMotion ? 1
          : root.launching ? 1 + (root.lp.launchScale - 1) * (1 - root.closeProgress)
          : root.lp.openScale + (1 - root.lp.openScale) * root.openness
        layer.enabled: root.openness < 1 && root.shown
        enabled: root.opened

        // the open folder dims the grid behind it
        Item {
          id: gridLayer
          anchors.fill: parent
          opacity: root.query !== "" ? 0 : 1 - folderPanel.progress * 0.5   // lint-ok: dim factor
          visible: opacity > 0
          Behavior on opacity { NumberAnimation { duration: Theme.dur("fast") } }
          // the grid behind an open folder blurs away (only while one is open)
          layer.enabled: folderPanel.progress > 0.001 && !Theme.reduceTransparency
          layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 48
            blur: folderPanel.progress
            autoPaddingEnabled: false
          }

          Item {
            id: track
            x: -root.pagePos * win.width
            width: root.pageCount * win.width
            height: parent.height

            Repeater {
              model: tiles
              delegate: AppTile {
                id: t
                required property string tid
                readonly property var slot: { root.tilesRev; return root.slots[tid] || null }
                readonly property bool isDragged: tid === root.dragId
                readonly property var home: slot ? root.slotPos(slot.page, slot.index) : ({ x: 0, y: 0 })
                // a dragged tile follows the pointer 1:1 (window → track coordinates)
                x: isDragged ? root.dragX - root.grabX + root.pagePos * win.width : sx.value
                y: isDragged ? root.dragY - root.grabY : sy.value
                z: isDragged ? 10 : 0
                visible: (slot !== null || isDragged) && !(isDragged && root.dragFrom === "folder")
                width: root.cellW; height: root.cellH
                folder: LM.isFolder(tid)
                title: { root.tilesRev; return root.titleFor(tid) }
                iconSource: { root.entries; return folder ? "" : root.iconFor(tid) }
                previews: {
                  root.tilesRev
                  if (!folder) return []
                  var f = root.layout.folders[LM.folderKey(tid)]
                  return f ? f.items.map(function(a) { return root.iconFor(a) }) : []
                }
                iconSize: root.iconSize
                showTitle: root.settings.showTitles && !((root.layout.apps[tid] || {}).hideTitle)
                selected: root.query === "" && root.openFolder === "" && slot !== null && slot.page === root.page && slot.index === root.selIndex
                pressed: root.pressId === tid && !root.editing
                editing: root.editing
                dragging: isDragged
                dropTarget: root.armedTarget === tid
                jiggle: isDragged ? 0 : root.jiggleFor(tid)

                Spring { id: sx; preset: root.lp.reflow; reduced: Theme.reduceMotion; target: t.home.x }
                Spring { id: sy; preset: root.lp.reflow; reduced: Theme.reduceMotion; target: t.home.y }
                // a tile released from a drag lands from where the pointer left it
                onIsDraggedChanged: if (!isDragged) { sx.from(x); sy.from(y) }
              }
            }
          }
        }

        // page dots
        Row {
          id: dots
          visible: root.query === "" && root.pageCount > 1
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Look.dots.bottom - Look.dots.hit / 2
          Repeater {
            model: root.pageCount
            Item {
              required property int index
              width: Look.dots.size + Look.dots.gap; height: Look.dots.hit
              Rectangle {
                anchors.centerIn: parent
                width: Look.dots.size; height: Look.dots.size; radius: width / 2
                color: index === root.page ? root.lp.dotActive : root.lp.dot
              }
            }
          }
          function indexAt(px, py) {
            var p = dots.mapFromItem(stage, px, py)
            if (p.y < 0 || p.y > height || p.x < 0 || p.x > width) return -1
            return Math.floor(p.x / (Look.dots.size + Look.dots.gap))
          }
        }

        // search field
        Rectangle {
          id: field
          anchors.horizontalCenter: parent.horizontalCenter
          y: root.settings.searchPosition === "center" && root.query === "" ? (win.height - height) / 2 - win.height * Look.grid.marginTop / 2 : Look.search.top
          width: search.activeFocus && search.text !== "" ? Look.search.widthFocused : Look.search.width
          Behavior on width { NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
          height: Look.search.height
          radius: Theme.m.radius.control
          color: root.lp.field
          visible: !(root.settings.searchPosition === "center" && root.query === "" && root.editing)
          VIcon {
            id: glass
            anchors.left: parent.left; anchors.leftMargin: Look.search.padX
            anchors.verticalCenter: parent.verticalCenter
            name: "search"; size: Look.search.glyph; color: root.lp.fieldPlaceholder
          }
          TextInput {
            id: search
            anchors.left: glass.right; anchors.leftMargin: Theme.layout.row.gap
            anchors.right: clear.left; anchors.rightMargin: Theme.layout.row.gap
            anchors.verticalCenter: parent.verticalCenter
            color: root.lp.fieldInk
            selectionColor: root.lp.selection
            font.family: Theme.font; font.pixelSize: Theme.core.type.body
            clip: true
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) { root.keyPressed(event) }
            Text {
              anchors.fill: parent
              visible: search.text === ""
              text: "Search"
              color: root.lp.fieldPlaceholder
              font: search.font
              verticalAlignment: Text.AlignVCenter
            }
          }
          VIcon {
            id: clear
            anchors.right: parent.right; anchors.rightMargin: Look.search.padX
            anchors.verticalCenter: parent.verticalCenter
            visible: search.text !== ""
            name: "close"; weight: "bold"; size: Look.search.glyph; color: root.lp.fieldPlaceholder
          }
        }

        // search results
        Column {
          id: resultList
          visible: root.query !== ""
          anchors.horizontalCenter: parent.horizontalCenter
          y: field.y + field.height + Theme.layout.sheet.pad
          width: Look.results.width
          Repeater {
            model: root.results
            Rectangle {
              required property var modelData
              required property int index
              width: resultList.width; height: Look.results.row
              radius: Theme.m.radius.row
              color: index === root.selIndex ? root.lp.selection : "transparent"
              Image {
                id: rIcon
                anchors.left: parent.left; anchors.leftMargin: Theme.layout.row.padX
                anchors.verticalCenter: parent.verticalCenter
                width: Look.results.icon; height: Look.results.icon
                sourceSize.width: Look.results.icon * 2; sourceSize.height: Look.results.icon * 2
                source: root.iconFor(modelData.id)
                asynchronous: true; mipmap: true
              }
              Column {
                anchors.left: rIcon.right; anchors.leftMargin: Theme.layout.row.gap
                anchors.right: parent.right; anchors.rightMargin: Theme.layout.row.padX
                anchors.verticalCenter: parent.verticalCenter
                Text {
                  width: parent.width; elide: Text.ElideRight
                  text: modelData.title
                  color: root.lp.label
                  font.family: Theme.font; font.pixelSize: Theme.core.type.body; font.weight: Font.Medium
                }
                Text {
                  width: parent.width; elide: Text.ElideRight
                  visible: text !== ""
                  text: modelData.hiddenApp ? "Hidden" : (modelData.folderName ? "In " + modelData.folderName : modelData.domain)
                  color: root.lp.fieldPlaceholder
                  font.family: Theme.font; font.pixelSize: Theme.core.type.subheadline
                }
              }
            }
          }
          Text {
            visible: root.results.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            topPadding: Theme.layout.sheet.pad
            text: "No results"
            color: root.lp.fieldPlaceholder
            font.family: Theme.font; font.pixelSize: Theme.core.type.title3
          }
        }

        // ---- the open folder
        FolderPanel {
          id: folderPanel
          anchors.fill: parent
          launchpad: root
        }
      }

      // ---- the single pointer handler
      MouseArea {
        id: pointer
        anchors.fill: parent
        // clicks count only once the Launchpad is really on screen: a surface you cannot
        // see must never launch what happens to be under the pointer
        enabled: root.opened && !root.settingsOpen && root.openness > 0.5
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        hoverEnabled: false
        property real pressX: 0
        property real pressY: 0
        property var hit: null
        property bool moved: false
        property bool swipe: false
        property real lastX: 0
        property real lastT: 0
        property real vel: 0

        function hitAt(px, py) {
          if (root.openFolder !== "") {
            if (!folderPanel.contains(px, py)) return { kind: "outside" }
            var fi = folderPanel.indexAt(px, py)
            var items = (root.layout.folders[LM.folderKey(root.openFolder)] || { items: [] }).items
            if (fi >= 0 && fi < items.length) {
              var r = folderPanel.cellRect(fi)
              return { kind: "folderItem", id: items[fi], index: fi, ox: px - r.x, oy: py - r.y }
            }
            return { kind: folderPanel.titleContains(px, py) ? "folderTitle" : "panel" }
          }
          if (root.query !== "") {
            var rp = resultList.mapFromItem(stage, px, py)
            var ri = Math.floor(rp.y / Look.results.row)
            if (rp.x >= 0 && rp.x <= resultList.width && rp.y >= 0 && ri < root.results.length) return { kind: "result", index: ri }
            return { kind: "empty" }
          }
          var di = dots.visible ? dots.indexAt(px, py) : -1
          if (di >= 0 && di < root.pageCount) return { kind: "dot", index: di }
          var col = Math.floor((px - root.gridX) / root.cellW)
          var row = Math.floor((py - root.gridY) / root.cellH)
          if (col >= 0 && col < root.cols && row >= 0 && row < root.rows) {
            var idx = row * root.cols + col
            var id = root.itemAt(root.page, idx)
            if (id) {
              var p = root.slotPos(root.page, idx)
              var tx = p.x - root.page * win.width, ty = p.y
              var ix = tx + (root.cellW - root.iconSize) / 2
              var inIcon = px >= ix && px <= ix + root.iconSize && py >= ty && py <= ty + root.cellH
              if (inIcon) {
                var badge = root.editing && LM.isApp(id) && px <= ix + Look.badge.size && py <= ty + Look.badge.size
                return { kind: badge ? "badge" : "tile", id: id, index: idx, ox: px - tx, oy: py - ty }
              }
            }
          }
          return { kind: "empty" }
        }

        onPressed: function(mouse) {
          search.forceActiveFocus()
          if (contextMenu.open) { contextMenu.open = false; root.contextId = ""; mouse.accepted = true; hit = { kind: "swallowed" }; return }
          pressX = mouse.x; pressY = mouse.y
          moved = false; swipe = false
          hit = hitAt(mouse.x, mouse.y)
          if (mouse.button === Qt.RightButton) {
            root.openContext(hit.kind === "tile" || hit.kind === "folderItem" ? hit.id : "", mouse.x, mouse.y)
            hit = { kind: "swallowed" }
            return
          }
          root.pressId = hit.kind === "tile" || hit.kind === "folderItem" ? hit.id : ""
          lastX = mouse.x; lastT = Date.now(); vel = 0
          if (root.pressId !== "") holdTimer.restart()
        }
        onPositionChanged: function(mouse) {
          if (!hit || hit.kind === "swallowed") return
          if (root.dragId !== "") { root.dragMove(mouse.x, mouse.y); return }
          var dist = Math.max(Math.abs(mouse.x - pressX), Math.abs(mouse.y - pressY))
          if (!moved && dist > Theme.core.surface.dock.dragThreshold) {
            moved = true
            holdTimer.stop()
            if (root.editing && (hit.kind === "tile" || hit.kind === "folderItem")) {
              root.pressId = ""
              root.beginDrag(hit.id, hit.kind === "folderItem" ? "folder" : "grid", mouse.x, mouse.y, hit.ox, hit.oy)
              return
            }
            if (root.query === "" && root.openFolder === "") {
              root.pressId = ""
              swipe = true
              root.swipePos = pageSpring.value
              root.swiping = true
            }
          }
          if (swipe) {
            var now = Date.now()
            var dx = mouse.x - lastX
            vel = 0.6 * vel + 0.4 * (-dx / win.width) / (Math.max(1, now - lastT) / 1000) // lint-ok: smoothing
            lastX = mouse.x; lastT = now
            root.swipeRaw = root.swipeRaw - dx / win.width
            root.swipePos = root.rubber(root.swipeRaw)
          }
        }
        onReleased: function(mouse) {
          holdTimer.stop()
          var h = hit
          hit = null
          root.pressId = ""
          if (!h || h.kind === "swallowed") return
          if (root.dragId !== "") { root.endDrag(); return }
          if (swipe) { swipe = false; root.settle(vel); return }
          if (moved) return
          switch (h.kind) {
          case "tile":
            if (root.editing) { if (LM.isFolder(h.id)) root.openFolderById(h.id) }
            else root.activate(h.id)
            break
          case "badge": root.commit(LM.hide(root.layout, h.id)); break
          case "folderItem": if (!root.editing) root.launch(h.id); break
          case "folderTitle": folderPanel.startRename(); break
          case "outside": root.closeFolder(); break
          case "result": root.launch(root.results[h.index].id); break
          case "dot": root.setPage(h.index); break
          case "panel": break
          default:
            if (root.editing) root.editing = false
            else if (search.text !== "") search.text = ""
            else root.hideAnimated(false)
          }
        }
        onCanceled: { holdTimer.stop(); root.pressId = ""; if (root.dragId !== "") root.cancelDrag(); if (swipe) { swipe = false; root.settle(0) } }
        onWheel: function(wheel) { root.onWheelEvent(wheel) }

        Timer {
          id: holdTimer
          interval: root.lp.longPress
          onTriggered: {
            var h = pointer.hit
            if (!h || (h.kind !== "tile" && h.kind !== "folderItem")) return
            root.editing = true
            root.pressId = ""
            root.beginDrag(h.id, h.kind === "folderItem" ? "folder" : "grid", pointer.mouseX, pointer.mouseY, h.ox, h.oy)
          }
        }
      }

      // the app dragged out of a folder is drawn here while the panel is still up
      AppTile {
        visible: root.dragId !== "" && root.dragFrom === "folder"
        x: root.dragX - root.grabX; y: root.dragY - root.grabY
        width: folderPanel.cellW; height: folderPanel.cellH
        title: visible ? root.titleFor(root.dragId) : ""
        iconSource: visible ? root.iconFor(root.dragId) : ""
        iconSize: root.iconSize
        dragging: true
      }

      VMenu {
        id: contextMenu
        z: 20
        onTriggered: function(index) { root.runContext(model[index].act) }
      }

      SettingsSheet {
        id: settingsSheet
        z: 30
        launchpad: root
        open: root.settingsOpen
        onDismissed: { root.settingsOpen = false; search.forceActiveFocus() }
      }

      // toast
      Rectangle {
        id: toast
        z: 40
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: Look.toast.bottom
        width: toastText.implicitWidth + 2 * Theme.layout.sheet.pad
        height: Theme.layout.capsule.height + Theme.layout.list.gap
        radius: height / 2
        color: root.lp.folderPanel
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: Theme.dur("base") } }
        function say(t) { toastText.text = t; opacity = 1; toastHold.restart() }
        Text {
          id: toastText
          anchors.centerIn: parent
          color: root.lp.label
          font.family: Theme.font; font.pixelSize: Theme.core.type.callout; font.weight: Font.Medium
        }
        Timer { id: toastHold; interval: Look.toast.hold; onTriggered: toast.opacity = 0 }
      }
    }
  }

  property string pressId: ""

  Component.onCompleted: {
    mkdir.running = true
    root.syncApps()
    root.refreshWallpaper()
  }
}
