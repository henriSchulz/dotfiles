import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import QtMultimedia
import "file:///home/henri/.local/share/velum/qml/Velum"
import "LayoutModel.js" as LM
import "FuzzySearch.js" as Fuzzy
import "AppAliases.js" as AppAliases
import "Look.js" as Look
import "Calc.js" as Calc

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
      picks: Object.keys(root.picks).length, info: root.infoId, folderPage: folderPanel.fpage, folderPages: folderPanel.pageCount,
      lastCopy: root.lastCopy, firstResult: root.results.length ? (root.results[0].kind || "app") + ":" + root.results[0].title : "",
      dragId: root.dragId, armed: root.armedTarget, hover: root.hoverTarget, drag: [Math.round(root.dragX), Math.round(root.dragY)], hidden: root.layout.hidden.length, lastLaunch: root.lastLaunch,
      folderTitle: root.openFolder !== "" && root.folderData(root.openFolder) ? root.folderData(root.openFolder).name : "",
      lastOpen: root.lastOpen, wallpaper: root.wallpaperSource, lastRun: root.lastRun, pickFor: root.pickFor, infoSteps: infoSheet.steps.length,
      video: root.videoBackground ? bgVideo.playbackState : -1,
      results0: root.results.length ? root.results[0].kind || "app" : "", cats: root.catIds.length, dirs: Object.keys(root.layout.dirs || {}).length,
      dirSheet: root.dirSheetOpen,
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
    // ids may hold spaces ("app:Disk Usage"): split on " onto " or take the two trailing numbers
    var t = String(arg || "")
    var onto = t.indexOf(" onto ")
    if (onto > 0) { var tg = t.slice(onto + 6); root.commit(LM.dropOnto(root.layout, t.slice(0, onto), tg, root.folderNameFor(tg))); return "ok" }
    var m = /^(.*) (\d+) (\d+)$/.exec(t)
    if (!m) return "usage"
    root.commit(LM.move(root.layout, m[1], parseInt(m[2]), parseInt(m[3])))
    return "ok"
  }
  // centre of a tile's icon in window pixels ("x y"), for the pointer tests
  function tileCenter(id) {
    var at = root.slots[String(id)]
    if (root.openFolder !== "") {
      var items = (root.folderData(root.openFolder) || { items: [] }).items
      var fi = items.indexOf(String(id))
      if (fi >= 0) { var r = folderPanel.cellRect(fi); return Math.round(r.x + folderPanel.cellW / 2) + " " + Math.round(r.y + root.iconSize / 2) }
    }
    if (!at) return ""
    var p = root.slotPos(at.page, at.index)
    return Math.round(p.x - at.page * win.width + root.cellW / 2) + " " + Math.round(p.y + root.iconSize / 2)
  }
  // centre of colour swatch N in the Get Info sheet ("x y", window pixels)
  function swatchCenter(n) { var p = infoSheet.swatchCenter(parseInt(n)); return p ? Math.round(p.x) + " " + Math.round(p.y) : "" }
  function showDirSheet(on) { root.dirSheetOpen = String(on) !== "false"; return "ok" }
  function addDir(path) { root.commit(LM.addDir(root.layout, String(path), "")); return "ok" }
  function testSettings(json) { root.commit(LM.setSettings(root.layout, JSON.parse(String(json)))); return "ok" }
  function pageItems(n) { return JSON.stringify(root.pages[parseInt(n)] || []) }
  function folderItems() { return JSON.stringify((root.folderData(root.openFolder) || { items: [] }).items) }
  function dotCenter(n) {
    var p = dots.mapToItem(stage, (parseInt(n) + 0.5) * (Look.dots.size + Look.dots.gap), Look.dots.hit / 2)
    return Math.round(p.x) + " " + Math.round(p.y)
  }
  function testPicked(path) { root.picturePicked(String(path)); return "ok" }
  function choose(purpose) { root.choosePicture(String(purpose)); return "ok" }
  function getInfo(id) { root.infoId = String(id || ""); return "ok" }
  function pick(id) { root.togglePick(String(id)); return "ok" }
  function testHide(id) { root.commit(LM.hide(root.layout, String(id))); return "ok" }
  function testUnhide(id) { root.commit(LM.unhide(root.layout, String(id))); return "ok" }
  function testContext(id) {
    root.openContext(String(id || ""), win.width / 2, win.height / 2)
    return "ok"
  }

  // The F4 bind comes in as a Hyprland event (`custom>>launchpad toggle`), not
  // a command: no process per key press, so the grid starts coming at once
  // (same path as henri.menu-v3's Super+Space). Through shell.toggle() when
  // the host API is there, so its open/closed bookkeeping stays right.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "custom") return
      var data = String(event.data)
      if (data.indexOf("launchpad") !== 0) return
      var verb = data.slice(9).trim() || "toggle"
      var id = root.manifest && root.manifest.id ? root.manifest.id : "henri.launchpad-v3"
      if (verb === "close") { root.hideAnimated(false); return }
      if (verb === "open") { if (!root.opened) root.open("{}"); return }
      if (root.shell && typeof root.shell.toggle === "function") root.shell.toggle(id, "{}")
      else root.toggle()
    }
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

  // ------------------------------------------ folders: real and virtual
  // folder:  the user's folders (layout.folders)
  // cat:     the categories page's automatic folders, read-only
  // dir:     a folder tile for a directory; its items are the files in it, read-only
  // file:    one file or directory inside a dir: tile, or a search result
  function isCat(id) { return typeof id === "string" && id.indexOf("cat:") === 0 }
  function isFile(id) { return typeof id === "string" && id.indexOf("file:") === 0 }
  function isGroup(id) { return LM.isFolder(id) || root.isCat(id) || LM.isDir(id) }
  function isVirtualGroup(id) { return root.isCat(id) || LM.isDir(id) }
  readonly property var categoryNames: ({ AudioVideo: "Media", Audio: "Media", Video: "Media", Development: "Development",
      Education: "Education", Game: "Games", Graphics: "Graphics", Network: "Internet", Office: "Office",
      Science: "Science", Settings: "Settings", System: "System", Utility: "Utilities" })
  // category -> app ids, every installed app that is not hidden, by display name
  readonly property var catGroups: {
    if (!root.settings.categoriesPage) return ({})
    var hidden = {}
    for (var h = 0; h < root.layout.hidden.length; h++) hidden[root.layout.hidden[h]] = true
    var g = {}
    for (var i = 0; i < root.desktopIds.length; i++) {
      var id = "app:" + root.desktopIds[i]
      var e = root.entries[id]
      if (!e || hidden[id]) continue
      var name = "Other"
      for (var c = 0; c < e.categories.length; c++) if (root.categoryNames[e.categories[c]]) { name = root.categoryNames[e.categories[c]]; break }
      if (!g[name]) g[name] = []
      g[name].push(id)
    }
    return g
  }
  readonly property var catIds: Object.keys(catGroups).sort(function(a, b) { return a === "Other" ? 1 : b === "Other" ? -1 : a.localeCompare(b) }).map(function(k) { return "cat:" + k })
  // what the grid shows: the layout's pages, then the categories page
  readonly property var pages: root.settings.categoriesPage && root.catIds.length > 0
    ? root.layout.pages.concat([root.catIds.slice(0, root.perPage)]) : root.layout.pages

  function folderData(id) {
    if (LM.isFolder(id)) {
      var f = root.layout.folders[LM.folderKey(id)]
      return f ? { name: f.name, items: f.items, color: f.color, emoji: f.emoji, editable: true } : null
    }
    if (root.isCat(id)) {
      var items = root.catGroups[id.slice(4)]
      return items ? { name: id.slice(4), items: items, editable: false } : null
    }
    if (LM.isDir(id)) {
      var d = (root.layout.dirs || {})[LM.dirKey(id)]
      return d ? { name: d.name, items: root.dirFiles[d.path] || [], editable: false, path: d.path } : null
    }
    return null
  }

  // ------------------------------------------------- directory listings
  property var dirFiles: ({})            // path -> ["file:/abs/path" …], directories end in "/"
  property string dirLoading: ""
  Process {
    id: dirProc
    stdout: StdioCollector {
      onStreamFinished: {
        var rows = String(text || "").split("\n").filter(function(l) { return l.length > 2 })
        var files = rows.map(function(l) { return "file:" + l.slice(2) + (l.charAt(0) === "d" ? "/" : "") })
        files.sort(function(a, b) {
          var da = a.slice(-1) === "/", db = b.slice(-1) === "/"
          return da !== db ? (da ? -1 : 1) : root.baseOf(a).localeCompare(root.baseOf(b))
        })
        var n = Object.assign({}, root.dirFiles)
        n[root.dirLoading] = files
        root.dirFiles = n
      }
    }
  }
  function loadDir(path) {
    root.dirLoading = path
    dirProc.running = false
    // one level, no dotfiles, at most 200 entries; type marker d/f in front
    dirProc.command = ["bash", "-c", "fd --max-depth 1 --max-results 200 --color never --absolute-path . \"$1\" 2>/dev/null | while IFS= read -r p; do if [[ -d $p ]]; then printf 'd\\t%s\\n' \"${p%/}\"; else printf 'f\\t%s\\n' \"$p\"; fi; done", "bash", path]
    dirProc.running = true
  }
  function baseOf(fileId) {
    var p = String(fileId).replace(/^file:/, "").replace(/\/$/, "")
    return p.slice(p.lastIndexOf("/") + 1)
  }
  function prettyPath(p) {
    var h = root.home
    return p === h ? "~" : (p.indexOf(h + "/") === 0 ? "~" + p.slice(h.length) : p)
  }
  // a themed icon for a file by its type, a folder icon for a directory tile by its XDG role
  function fileIcon(fileId) {
    var p = String(fileId).replace(/^file:/, "")
    if (p.slice(-1) === "/") return Quickshell.iconPath(root.dirIconName(p.slice(0, -1)), "folder")
    var ext = p.slice(p.lastIndexOf(".") + 1).toLowerCase()
    var byExt = { pdf: "application-pdf", png: "image-x-generic", jpg: "image-x-generic", jpeg: "image-x-generic", gif: "image-x-generic",
      webp: "image-x-generic", heic: "image-x-generic", svg: "image-svg+xml", mp3: "audio-x-generic", flac: "audio-x-generic", wav: "audio-x-generic",
      mp4: "video-x-generic", mkv: "video-x-generic", mov: "video-x-generic", zip: "package-x-generic", tar: "package-x-generic", gz: "package-x-generic",
      md: "text-markdown", txt: "text-x-generic", html: "text-html", json: "text-x-script", sh: "text-x-script", py: "text-x-python",
      doc: "x-office-document", docx: "x-office-document", odt: "x-office-document", xls: "x-office-spreadsheet", xlsx: "x-office-spreadsheet",
      ods: "x-office-spreadsheet", ppt: "x-office-presentation", pptx: "x-office-presentation", odp: "x-office-presentation" }
    return Quickshell.iconPath(byExt[ext] || "text-x-generic", "text-x-generic")
  }
  function dirIconName(path) {
    var x = root.xdgDirs
    var roles = { DESKTOP: "user-desktop", DOWNLOAD: "folder-download", DOCUMENTS: "folder-documents", MUSIC: "folder-music",
      PICTURES: "folder-pictures", VIDEOS: "folder-videos", PUBLICSHARE: "folder-publicshare", TEMPLATES: "folder-templates" }
    for (var k in x) if (x[k] === path && roles[k]) return roles[k]
    return path === root.home ? "user-home" : "folder"
  }

  // XDG user directories from ~/.config/user-dirs.dirs (DOWNLOAD -> /home/…/Downloads)
  property var xdgDirs: ({})
  FileView {
    path: root.home + "/.config/user-dirs.dirs"
    printErrors: false
    onLoaded: {
      var out = {}
      var lines = text().split("\n")
      for (var i = 0; i < lines.length; i++) {
        var m = /^XDG_([A-Z]+)_DIR="(.*)"\s*$/.exec(lines[i])
        if (m) out[m[1]] = m[2].replace("$HOME", root.home).replace(/\/+$/, "") || "/"
      }
      root.xdgDirs = out
    }
  }
  property bool dirSheetOpen: false
  readonly property int cols: settings.columns
  readonly property int rows: settings.rows
  readonly property int perPage: cols * rows
  readonly property int pageCount: pages.length + (dragId !== "" && dragFrom === "grid" ? 1 : 0)

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
    if (root.isFile(id)) return root.fileIcon(id)
    if (LM.isDir(id)) { var dd = (root.layout.dirs || {})[LM.dirKey(id)]; return Quickshell.iconPath(dd ? root.dirIconName(dd.path) : "folder", "folder") }
    var o = root.layout.apps[id]
    var value = o && o.icon ? o.icon : (root.entries[id] ? root.entries[id].icon : "")
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    var themed = value ? Quickshell.iconPath(value, true) : ""
    return themed || Quickshell.iconPath("application-x-executable", true)
  }
  function titleFor(id) {
    if (root.isGroup(id)) { var f = root.folderData(id); return f ? f.name : "" }
    if (LM.isWorkflow(id)) { var w = (root.layout.workflows || {})[LM.workflowKey(id)]; return w ? w.name : "" }
    if (root.isFile(id)) return root.baseOf(id)
    var o = root.layout.apps[id]
    if (o && o.name) return o.name
    return root.entries[id] ? root.entries[id].name : id.slice(4)
  }
  function folderNameFor(targetId) {
    var e = root.entries[targetId]
    var names = root.categoryNames
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
    for (var p = 0; p < root.pages.length; p++)
      for (var i = 0; i < root.pages[p].length; i++) {
        want[root.pages[p][i]] = true
        s[root.pages[p][i]] = { page: p, index: i }
      }
    // a dragged app that is inside a folder still needs its tile on the grid
    if (root.dragId !== "" && !s[root.dragId]) want[root.dragId] = true
    for (var k = tiles.count - 1; k >= 0; k--) if (!want[tiles.get(k).tid]) tiles.remove(k)
    var have = {}
    for (var m = 0; m < tiles.count; m++) have[tiles.get(m).tid] = true
    for (var id in want) if (!have[id]) tiles.append({ tid: id })
    root.slots = s
    root.tilesRev++
    if (root.page >= root.pages.length) root.setPage(root.pages.length - 1)
  }

  function itemAt(pageIndex, index) {
    var pg = root.pages[pageIndex]
    return pg && index >= 0 && index < pg.length ? pg[index] : ""
  }

  // ------------------------------------------------------------- search
  onSelIndexChanged: if (root.openFolder !== "" && root.selIndex >= 0) folderPanel.fpage = folderPanel.pageOf(root.selIndex)
  onQueryChanged: { root.runSearch(); root.selIndex = root.query !== "" ? 0 : -1 }
  function runSearch() {
    if (root.query === "") { root.results = []; return }
    // ":" searches emoji, "clip" the clipboard history
    if (root.query.charAt(0) === ":") { root.results = root.emojiRows(root.query.slice(1)); return }
    var clipM = /^clip(board)?(\s+(.*))?$/i.exec(root.query)
    if (clipM) { root.results = root.clipRows(clipM[3] || ""); return }
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
    for (var wk in (root.layout.workflows || {})) {
      var wfl = root.layout.workflows[wk]
      rows.push({ id: "workflow:" + wk, kind: "workflow", title: wfl.name, domain: "Workflow · " + wfl.items.length + (wfl.items.length === 1 ? " step" : " steps"), tags: ["workflow"] })
    }
    var found = Fuzzy.search(root.query, rows)
    var calc = Calc.evaluate(root.query)
    if (calc !== null) found.unshift({ id: "calc", kind: "calc", title: "= " + Calc.format(calc), domain: "Calculator · Enter copies", value: Calc.format(calc) })
    // files come in a moment later from fd; until then the last answer for this query, if any
    var files = calc === null && root.fileHitsQuery === root.query ? root.fileHits : []
    root.results = found.slice(0, Look.results.maxRows - files.length).concat(files)
    if (calc === null && root.query.length >= Look.results.fileMinChars && root.fileHitsQuery !== root.query) fileDebounce.restart()
  }

  // ------------------------------------------------------- emoji, clipboard
  property var emojis: []
  FileView {
    path: root.omarchyBase + "/shell/plugins/emojis/emojis.json"
    printErrors: false
    onLoaded: { try { root.emojis = JSON.parse(text()) } catch (e) { root.emojis = [] } }
  }
  function emojiRows(q) {
    var words = q.toLowerCase().trim().split(/\s+/).filter(function(w) { return w.length > 0 })
    var out = []
    for (var i = 0; i < root.emojis.length && out.length < Look.results.maxRows; i++) {
      var it = root.emojis[i]
      var k = String(it.k || "")
      var ok = true
      for (var w = 0; w < words.length; w++) if (k.indexOf(words[w]) < 0) { ok = false; break }
      if (ok) out.push({ id: "emoji:" + it.e, kind: "emoji", title: it.e + "  " + k.split(" ").slice(0, 4).join(" "), domain: "Emoji · Enter copies", value: it.e })
    }
    return out
  }
  // Omarchy's clipboard history (newest first), read here only
  property var clipHistory: []
  FileView {
    path: root.home + "/.local/state/omarchy/clipboard-history.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { var h = JSON.parse(text()); root.clipHistory = Array.isArray(h) ? h : [] } catch (e) { root.clipHistory = [] } }
  }
  function clipRows(q) {
    var needle = q.toLowerCase()
    var out = []
    for (var i = 0; i < root.clipHistory.length && out.length < Look.results.maxRows; i++) {
      var c = root.clipHistory[i]
      if (!c) continue
      if (c.type === "image") {
        if (needle === "" || "image".indexOf(needle) === 0)
          out.push({ id: "clip:" + i, kind: "clip", index: i, image: c.path, mime: c.mime || "image/png", title: "Image", domain: "Clipboard · " + String(c.path).slice(String(c.path).lastIndexOf("/") + 1) })
        continue
      }
      var t = String(c.text || "")
      if (needle !== "" && t.toLowerCase().indexOf(needle) < 0) continue
      var line = t.replace(/\s+/g, " ").trim()
      out.push({ id: "clip:" + i, kind: "clip", index: i, title: line.slice(0, Look.results.clipChars), domain: "Clipboard · Enter copies" })
    }
    return out
  }
  function copyClip(r) {
    root.lastCopy = "clip:" + r.index
    if (!root.inRig) {
      if (r.image) Quickshell.execDetached([root.omarchyBase + "/bin/omarchy-clipboard-paste-file", "--copy-only", r.mime, r.image])
      else Quickshell.execDetached([root.omarchyBase + "/bin/omarchy-clipboard-paste-text", "--copy-only", "--history-index", String(r.index)])
    }
    toast.say("Copied")
    root.hideAnimated(false)
  }

  // ---------------------------------------------------------- file search
  // fd over $HOME, names only, no dotfiles; the answer is ranked here like the apps
  property var fileHits: []
  property string fileHitsQuery: ""
  property string fileScanFor: ""
  readonly property var fileExcludes: [".git", "node_modules", ".cache", ".npm", ".cargo", ".rustup", ".venv", "__pycache__", ".var", "Trash"]
  Timer { id: fileDebounce; interval: Look.results.fileDebounce; onTriggered: root.scanFiles() }
  function scanFiles() {
    var q = root.query
    if (q.length < Look.results.fileMinChars) return
    var pattern = q.split(/\s+/).filter(function(t) { return t.length > 0 })
      .map(function(t) { return t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") }).join(".*")
    var cmd = ["fd", "--max-results", "80", "--color", "never", "--absolute-path", "--ignore-case"]
    for (var i = 0; i < root.fileExcludes.length; i++) cmd.push("--exclude", root.fileExcludes[i])
    cmd.push("--", pattern, root.home)
    root.fileScanFor = q
    fileProc.running = false
    fileProc.command = cmd
    fileProc.running = true
  }
  Process {
    id: fileProc
    stdout: StdioCollector {
      onStreamFinished: {
        if (root.fileScanFor !== root.query) return      // typed on meanwhile
        var rows = String(text || "").split("\n").filter(function(l) { return l.length > 0 }).map(function(l) {
          var dirEntry = l.slice(-1) === "/"
          var path = dirEntry ? l.slice(0, -1) : l
          var cut = path.lastIndexOf("/")
          return { id: "file:" + path + (dirEntry ? "/" : ""), kind: "file", path: path,
                   title: path.slice(cut + 1), domain: root.prettyPath(path.slice(0, cut) || "/") }
        })
        root.fileHits = Fuzzy.search(root.fileScanFor, rows).slice(0, Look.results.fileRows)
        root.fileHitsQuery = root.fileScanFor
        root.runSearch()
      }
    }
  }

  // -------------------------------------------------------------- launch
  // In a test rig nothing is started: uwsm-app would open the app in the live session.
  readonly property bool inRig: (Quickshell.env("VELUM_SHELL_RIG") || "") !== ""
  property string lastLaunch: ""
  function startApp(id) {
    var e = root.entries[id]
    if (!e) return false
    root.lastLaunch = id
    if (!root.inRig) Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", e.desktopId + ".desktop"])
    return true
  }
  function launch(id) {
    if (root.startApp(id)) root.hideAnimated(true)
  }
  // a workflow starts every app and opens every path in it, then the Launchpad goes
  property var lastRun: []
  function runWorkflow(id) {
    var w = (root.layout.workflows || {})[LM.workflowKey(id)]
    if (!w) return
    var ran = []
    for (var i = 0; i < w.items.length; i++) {
      var it = w.items[i]
      if (LM.isApp(it)) { if (root.startApp(it)) ran.push(it) }
      else if (root.isFile(it)) {
        var path = it.slice(5).replace(/\/$/, "")
        if (!root.inRig) Quickshell.execDetached(["uwsm-app", "--", "xdg-open", path])
        ran.push(it)
      }
    }
    root.lastRun = ran
    root.hideAnimated(true)
  }
  function activateResult(r) {
    if (!r) return
    if (r.kind === "calc") root.copyText(r.value)
    else if (r.kind === "file") root.openPath(r.path)
    else if (r.kind === "workflow") root.runWorkflow(r.id)
    else if (r.kind === "emoji") { root.copyText(r.value); root.hideAnimated(false) }
    else if (r.kind === "clip") root.copyClip(r)
    else root.launch(r.id)
  }
  function copyText(t) {
    root.lastCopy = String(t)
    Quickshell.execDetached(["bash", "-c", "printf '%s' \"$1\" | wl-copy", "bash", String(t)])
    toast.say("Copied " + t)
  }
  property string lastOpen: ""
  function openPath(path) {
    root.lastOpen = path
    if (!root.inRig) Quickshell.execDetached(["uwsm-app", "--", "xdg-open", path])
    root.hideAnimated(true)
  }
  function activate(id) {
    if (root.isGroup(id)) root.openFolderById(id)
    else if (LM.isApp(id)) root.launch(id)
    else if (root.isFile(id)) root.openPath(String(id).slice(5).replace(/\/$/, ""))
    else if (LM.isWorkflow(id)) root.runWorkflow(id)
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
    // a headless output (HEADLESS-SPARE parks the test rigs) is never where Henri looks:
    // with focus there, take the first real screen instead
    var real = function(sc) { return String(sc.name).indexOf("HEADLESS") !== 0 }
    for (var i = 0; i < screens.length; i++)
      if (mon && screens[i].name === mon.name && (real(screens[i]) || root.inRig)) { win.screen = screens[i]; return }
    for (var k = 0; k < screens.length; k++) if (real(screens[k])) { win.screen = screens[k]; return }
    if (screens.length > 0) win.screen = screens[0]
  }

  // ----------------------------------------------------------- wallpaper
  readonly property string wallpaperLink: home + "/.local/state/omarchy/current/background"
  property string wallpaperToken: ""
  readonly property bool videoBackground: root.settings.wallpaper.kind === "video" && !!root.settings.wallpaper.path && !Theme.reduceMotion
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
    : root.videoBackground ? root.lp.scrimVideo
    : Math.max(root.lp.scrimMin, Math.min(root.lp.scrimMax, 1 - root.lp.scrimTarget / Math.max(root.wallpaperBrightness, root.lp.scrimTarget)))

  // ------------------------------------------------------------- pages
  property real swipePos: 0
  property bool swiping: false
  Spring { id: pageSpring; preset: root.lp.page; reduced: Theme.reduceMotion; target: root.page }
  readonly property real pagePos: swiping ? swipePos : pageSpring.value

  function setPage(n) {
    root.page = Math.max(0, Math.min(root.pageCount - 1, n))
    if (root.query === "") root.selIndex = root.selIndex >= 0 ? Math.min(root.selIndex, Math.max(0, (root.pages[root.page] || []).length - 1)) : -1
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
    if (root.openFolder !== "" && root.query === "") {
      var nowF = Date.now()
      if (nowF > root.wheelCooldown) {
        var dd = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : (wheel.angleDelta.x !== 0 ? wheel.angleDelta.x : -wheel.pixelDelta.x)
        if (dd !== 0) { folderPanel.turn(dd < 0 ? 1 : -1); root.wheelCooldown = nowF + Theme.dur("slow") }
      }
      return
    }
    if (root.query !== "" || root.openFolder !== "" || root.settingsOpen || root.infoId !== "") return
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
  property real restX: 0                 // where the pointer last came to rest
  property real restY: 0
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
  property int dotTarget: -1
  Timer {
    id: dotTimer
    interval: root.lp.edgeHover
    onTriggered: if (root.dotTarget >= 0) { root.setPage(root.dotTarget); root.lastPreview = "" }
  }
  Timer {
    id: edgeTimer
    interval: root.lp.edgeHover
    repeat: true
    onTriggered: if (root.edgeDir !== 0) { root.setPage(root.page + root.edgeDir); root.lastPreview = "" }
  }

  // what may be picked up: apps, folders and folder tiles on the layout's pages, apps in a real folder
  function movable(id, from) {
    if (from === "folder") return LM.isApp(id) && !root.isVirtualGroup(root.openFolder)
    var at = root.slots[id]
    return (LM.isApp(id) || LM.isFolder(id) || LM.isDir(id) || LM.isWorkflow(id)) && !!at && at.page < root.layout.pages.length
  }
  function beginDrag(id, from, px, py, ox, oy) {
    if (!root.movable(id, from)) return
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
    // over a page dot: that page after edgeHover
    var dotHit = dots.visible ? dots.indexAt(px, py) : -1
    if (dotHit >= 0 && dotHit !== root.page) {
      if (root.dotTarget !== dotHit) { root.dotTarget = dotHit; dotTimer.restart() }
      return
    }
    root.dotTarget = -1; dotTimer.stop()
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
    var near = Math.abs(px - cx) < root.iconSize * root.lp.folderZone && Math.abs(py - cy) < root.iconSize * root.lp.folderZone
    if (under && under !== root.dragId && near && LM.isApp(root.dragId) && (LM.isApp(under) || LM.isFolder(under))) {
      reorderTimer.stop()
      if (root.hoverTarget !== under) { root.hoverTarget = under; root.armedTarget = ""; folderTimer.restart() }
      return
    }
    root.disarm()
    var len = (root.baseLayout.pages[root.page] || []).filter(function(x) { return x !== root.dragId }).length
    var to = Math.min(index, len)
    var key2 = root.page + ":" + to
    if (key2 === root.lastPreview) { reorderTimer.stop(); return }
    // the icons make room only once the pointer stops: any real movement restarts the wait
    var moved = Math.abs(px - root.restX) > root.lp.restSlop || Math.abs(py - root.restY) > root.lp.restSlop
    if (moved) { root.restX = px; root.restY = py }
    if (!root.pendingSlot || root.pendingSlot.key !== key2 || moved) {
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
    if (!root.isGroup(id) || !root.folderData(id)) return
    if (LM.isDir(id)) root.loadDir(root.folderData(id).path)
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
    var picked = root.pickedInOrder()
    if (LM.isApp(id)) m = [{ text: "Open", act: "open" }, { text: "Get Info…", act: "info" }, { separator: true }, { text: "Hide", act: "hide" }]
    else if (LM.isWorkflow(id)) m = [{ text: "Run", act: "open" }, { text: "Get Info…", act: "info" }, { separator: true }, { text: "Remove", act: "removeWorkflow" }]
    else if (LM.isFolder(id)) m = [{ text: "Open", act: "open" }, { text: "Get Info…", act: "info" }, { text: "Rename", act: "rename" }, { separator: true }, { text: "Ungroup", act: "ungroup" }]
    else if (LM.isDir(id)) m = [{ text: "Open", act: "open" }, { text: "Open in Files", act: "reveal" }, { separator: true }, { text: "Remove", act: "removeDir" }]
    else if (root.isCat(id)) m = [{ text: "Open", act: "open" }]
    else if (root.isFile(id)) m = [{ text: "Open", act: "open" }, { text: "Copy Path", act: "copyPath" }]
    else m = [{ text: root.editing ? "Done Editing" : "Edit Layout", act: "edit" }, { text: "Add Folder Tile…", act: "addDir" }, { text: "Settings…", act: "settings" },
              { separator: true }, { text: "Sort by Name", act: "reset" }]
    if (picked.length >= 1 && (id === "" || root.picks[id])) {
      var top = [{ text: "New Workflow with " + picked.length + (picked.length === 1 ? " App" : " Apps"), act: "workflow" }]
      if (picked.length >= 2) top.unshift({ text: "New Folder with " + picked.length + " Apps", act: "group" })
      m = top.concat([{ separator: true }], m)
    }
    contextMenu.model = m
    contextMenu.x = Math.min(px, win.width - contextMenu.width)
    contextMenu.y = Math.min(py, win.height - contextMenu.height)
    contextMenu.highlighted = -1
    contextMenu.open = true
  }
  function groupPicks() {
    var ids = root.pickedInOrder()
    if (ids.length < 2) return
    var next = LM.groupInto(root.layout, ids, root.folderNameFor(ids[0]))
    var fid = next.lastFolder
    root.clearPicks()
    root.commit(next)
    if (fid) Qt.callLater(function() { root.openFolderById(fid); Qt.callLater(folderPanel.startRename) })
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
    else if (act === "info") root.infoId = id
    else if (act === "reveal") { var fd0 = root.folderData(id); if (fd0) root.openPath(fd0.path) }
    else if (act === "removeDir") root.commit(LM.removeDir(root.layout, id))
    else if (act === "removeWorkflow") root.commit(LM.removeWorkflow(root.layout, id))
    else if (act === "workflow") {
      var ids = root.pickedInOrder()
      var nw = LM.addWorkflow(root.layout, ids, "Workflow")
      var wid = nw.lastWorkflow
      root.clearPicks()
      root.commit(nw)
      if (wid) Qt.callLater(function() { root.infoId = wid })
    }
    else if (act === "addDir") root.dirSheetOpen = true
    else if (act === "copyPath") root.copyText(String(id).slice(5).replace(/\/$/, ""))
    else if (act === "group") root.groupPicks()
    search.forceActiveFocus()
  }

  // ------------------------------------------------------------ keyboard
  function keyPressed(event) {
    var k = event.key
    if (k === Qt.Key_Escape) {
      event.accepted = true
      if (contextMenu.open) { contextMenu.open = false; return }
      if (root.settingsOpen) { root.settingsOpen = false; return }
      if (root.pickFor !== "") { root.pickFor = ""; return }
      if (root.infoId !== "") { root.infoId = ""; return }
      if (root.dirSheetOpen) { root.dirSheetOpen = false; return }
      if (root.dragId !== "") { root.cancelDrag(); return }
      if (search.text !== "") { search.text = ""; return }
      if (root.openFolder !== "") { root.closeFolder(); return }
      if (Object.keys(root.picks).length > 0) { root.clearPicks(); return }
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
        root.activateResult(root.results[Math.max(0, root.selIndex)])
        event.accepted = true
      }
      return
    }
    // grid / folder navigation
    var list = root.openFolder !== "" ? (root.folderData(root.openFolder) || { items: [] }).items : (root.pages[root.page] || [])
    var cols = root.openFolder !== "" ? root.settings.folderGrid[0] : root.cols
    var s = root.selIndex
    if (k === Qt.Key_Right || k === Qt.Key_Left || k === Qt.Key_Down || k === Qt.Key_Up) {
      event.accepted = true
      if (s < 0) { root.selIndex = 0; return }
      var step = k === Qt.Key_Right ? 1 : k === Qt.Key_Left ? -1 : k === Qt.Key_Down ? cols : -cols
      var n = s + step
      if (root.openFolder === "" && (k === Qt.Key_Right || k === Qt.Key_Left)) {
        if (n >= list.length && root.page < root.pages.length - 1) { root.setPage(root.page + 1); root.selIndex = 0; return }
        if (n < 0 && root.page > 0) { root.setPage(root.page - 1); root.selIndex = (root.pages[root.page] || []).length - 1; return }
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
          visible: root.settings.wallpaper.kind !== "solid" && !root.videoBackground && !Theme.reduceTransparency
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
        // a looping, muted video instead, playing only while the Launchpad is up
        Video {
          id: bgVideo
          anchors.fill: parent
          visible: root.videoBackground && !Theme.reduceTransparency
          source: root.videoBackground ? "file://" + root.settings.wallpaper.path : ""
          fillMode: VideoOutput.PreserveAspectCrop
          loops: MediaPlayer.Infinite
          muted: true
          readonly property bool want: visible && root.shown
          onWantChanged: want ? play() : pause()
          layer.enabled: visible
          layer.effect: MultiEffect { blurEnabled: true; blurMax: 64; blur: root.settings.wallpaper.blur / 100; autoPaddingEnabled: false }
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
        width: 32; height: 18; visible: false  // lint-ok: sample size
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
          // the bright end, not the mean: labels have to read on the brightest parts too
          var lumas = []
          for (var i = 0; i < d.length; i += 4) lumas.push((0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]) / 255) // lint-ok: Rec. 709 luma
          lumas.sort(function(a, b) { return a - b })
          root.wallpaperBrightness = lumas[Math.min(lumas.length - 1, Math.floor(lumas.length * root.lp.scrimQuantile))]
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
          // eases the search toggle; while a folder moves, opacity follows it directly (no lag)
          Behavior on opacity { enabled: folderPanel.progress < 0.001; NumberAnimation { duration: Theme.dur("fast") } }
          // the grid behind an open folder blurs away (only while one is open)
          layer.enabled: folderPanel.progress > 0.001 && !Theme.reduceTransparency
          layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 48
            // squared: blur reads strong long after it starts fading, so it leaves faster than the dim
            blur: folderPanel.progress * folderPanel.progress
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
                folder: LM.isFolder(tid) || root.isCat(tid)
                workflow: LM.isWorkflow(tid)
                cover: { root.tilesRev; var fc = LM.isFolder(tid) ? root.layout.folders[LM.folderKey(tid)] : null; return fc && fc.cover ? fc.cover : "" }
                title: { root.tilesRev; root.catGroups; return root.titleFor(tid) }
                iconSource: { root.entries; root.xdgDirs; return folder ? "" : root.iconFor(tid) }
                previews: {
                  root.tilesRev; root.catGroups
                  if (LM.isWorkflow(tid)) { var wf = (root.layout.workflows || {})[LM.workflowKey(tid)]; return wf ? wf.items.slice(0, 4).map(function(a) { return root.iconFor(a) }) : [] }
                  if (!folder) return []
                  var f = root.folderData(tid)
                  return f ? f.items.slice(0, 9).map(function(a) { return root.iconFor(a) }) : []
                }
                iconSize: root.iconSize
                showTitle: root.settings.showTitles && !((root.layout.apps[tid] || {}).hideTitle)
                selected: root.query === "" && root.openFolder === "" && slot !== null && slot.page === root.page && slot.index === root.selIndex
                pressed: root.pressId === tid && !root.editing
                editing: root.editing
                dragging: isDragged
                dropTarget: root.armedTarget === tid
                picked: root.picks[tid] === true
                folderColor: { root.tilesRev; var f = folder ? root.layout.folders[LM.folderKey(tid)] : null; return f && f.color ? f.color : "" }
                emoji: { root.tilesRev; var f = folder ? root.layout.folders[LM.folderKey(tid)] : null; return f && f.emoji ? f.emoji : "" }
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
          visible: root.query === "" && (root.pages.length > 1 || root.page >= root.pages.length)
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Look.dots.bottom - Look.dots.hit / 2
          Repeater {
            // the spare page a drag opens gets its dot only once you are on it:
            // a dot appearing at drag start would shift every dot under the pointer
            model: root.pages.length + (root.page >= root.pages.length ? 1 : 0)
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
                source: modelData.kind === "calc" || modelData.kind === "emoji" || modelData.kind === "workflow" || (modelData.kind === "clip" && !modelData.image) ? ""
                  : modelData.kind === "clip" ? "file://" + modelData.image
                  : (modelData.kind === "file" ? root.fileIcon(modelData.id) : root.iconFor(modelData.id))
                asynchronous: true; mipmap: true
                VIcon { anchors.centerIn: parent; visible: modelData.kind === "calc" || modelData.kind === "workflow" || (modelData.kind === "clip" && !modelData.image)
                  name: modelData.kind === "calc" ? "calculator" : (modelData.kind === "workflow" ? "workflow" : "clipboard")
                  weight: "fill"; size: Look.results.icon * 0.8; color: root.lp.label } // lint-ok: glyph in icon box
                Text { anchors.centerIn: parent; visible: modelData.kind === "emoji"; text: modelData.value || ""; font.pixelSize: Look.results.icon * 0.8 } // lint-ok: glyph in icon box
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
                  text: modelData.hiddenApp ? "Hidden" : (modelData.folderName ? "In " + modelData.folderName : (modelData.domain || ""))
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
        enabled: root.opened && !root.settingsOpen && root.infoId === "" && !root.dirSheetOpen && root.pickFor === "" && root.openness > 0.5
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
            var fd = folderPanel.dotAt(px, py)
            if (fd >= 0) return { kind: "folderDot", index: fd }
            if (!folderPanel.contains(px, py)) return { kind: "outside" }
            var fi = folderPanel.indexAt(px, py)
            var items = (root.folderData(root.openFolder) || { items: [] }).items
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
          // Shift-click picks apps for a new folder (and enters edit mode)
          if (mouse.button === Qt.LeftButton && (mouse.modifiers & Qt.ShiftModifier) && (hit.kind === "tile" || hit.kind === "folderItem") && LM.isApp(hit.id)) {
            root.togglePick(hit.id)
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
          case "folderItem": if (!root.editing || root.isVirtualGroup(root.openFolder)) root.activate(h.id); break
          case "folderTitle": folderPanel.startRename(); break
          case "outside": root.closeFolder(); break
          case "result": root.activateResult(root.results[h.index]); break
          case "folderDot": folderPanel.fpage = h.index; break
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

      InfoSheet {
        id: infoSheet
        z: 30
        launchpad: root
        itemId: root.infoId
        onDismissed: { root.infoId = ""; search.forceActiveFocus() }
      }

      DirSheet {
        z: 30
        launchpad: root
        open: root.dirSheetOpen
        onDismissed: { root.dirSheetOpen = false; search.forceActiveFocus() }
      }

      ImageSheet {
        id: imageSheet
        z: 35
        launchpad: root
        open: root.pickFor !== ""
        video: root.pickFor === "video"
        title: root.pickFor === "cover" ? "Folder Cover" : root.pickFor === "icon" ? "App Icon" : root.pickFor === "video" ? "Background Video" : "Background Image"
        onPicked: function(path) { root.picturePicked(path) }
        onDismissed: { root.pickFor = ""; if (root.infoId === "" && !root.settingsOpen) search.forceActiveFocus() }
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

  // Shift-click picks (apps) for "New Folder with N Apps"
  property var picks: ({})
  function togglePick(id) {
    if (!LM.isApp(id)) return
    var n = Object.assign({}, root.picks)
    if (n[id]) delete n[id]; else n[id] = true
    root.picks = n
    if (!root.editing) root.editing = true
  }
  function clearPicks() { if (Object.keys(root.picks).length > 0) root.picks = ({}) }
  // picks in grid order, so the new folder keeps the arrangement
  function pickedInOrder() {
    var out = []
    var order = []
    for (var p = 0; p < root.layout.pages.length; p++) order = order.concat(root.layout.pages[p])
    for (var key in root.layout.folders) order = order.concat(root.layout.folders[key].items)
    for (var i = 0; i < order.length; i++) if (root.picks[order[i]]) out.push(order[i])
    return out
  }
  onEditingChanged: if (!editing) clearPicks()

  property string infoId: ""             // Get Info sheet open for this id
  // image picker: what the chosen file is for ("icon" | "cover" -> the Get Info sheet, "wallpaper" | "video" -> settings)
  property string pickFor: ""
  function choosePicture(purpose) { root.pickFor = purpose }
  function picturePicked(path) {
    var what = root.pickFor
    root.pickFor = ""
    if (what === "icon") infoSheet.setIcon(path)
    else if (what === "cover") infoSheet.setCover(path)
    else if (what === "wallpaper") root.commit(LM.setSettings(root.layout, { wallpaper: { kind: "image", path: path } }))
    else if (what === "video") root.commit(LM.setSettings(root.layout, { wallpaper: { kind: "video", path: path } }))
  }
  property string lastCopy: ""

  Component.onCompleted: {
    mkdir.running = true
    root.syncApps()
    root.refreshWallpaper()
  }
}
