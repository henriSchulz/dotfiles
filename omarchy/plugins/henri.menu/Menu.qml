import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import qs.Ui
import "MenuModel.js" as MenuModel
import "FuzzySearch.js" as FuzzySearch
import "AppAliases.js" as AppAliases
import "/usr/share/omarchy/shell/services/AppSearch.js" as AppSearch
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi
import "file:///home/henri/.local/share/apple-ui/Apple.js" as Apple
import QtQuick.Effects

Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // Plugin lifecycle hooks. The host calls open(payloadJson) after
  // `omarchy-shell shell summon omarchy.menu ...` and close() when hidden.
  property string pendingInitialMenu: "root"

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    if (payload.fontFamily) root.fontFamily = payload.fontFamily

    if (payload.mode === "select" || payload.mode === "input") {
      root.openDmenu(payload)
    } else {
      if (!root.appLibrary) root.refreshFallbackHides()
      root.openRoute(payload.initialMenu || payload.menu || "root")
    }
  }

  function close() {
    root.cancel()
  }

  function refresh() {
    defaultMenuFile.reload()
    userMenuFile.reload()
    return "ok"
  }

  function ping() { return "ok" }

  // Super+Space kommt als Hyprland-Ereignis herein, nicht als Kommando:
  // `omarchy-menu toggle` startete bash + jq + den qs-IPC-Client, zusammen
  // ~95 ms, bevor die Shell vom Tastendruck überhaupt etwas mitbekam. Das
  // Ereignis läuft über die ohnehin offene Event-Socket-Verbindung, also
  // fängt die Karte im selben Moment an zu kommen (wie beim Super+Tab-
  // Switcher). Der Umweg über shell.toggle() statt direkt openRoute() hält
  // die Sichtbarkeits-Buchführung der Shell intakt.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "custom") return
      var data = String(event.data)
      if (data.indexOf("menu ") !== 0) return
      var parts = data.slice(5).trim().split(/\s+/)
      var verb = parts[0] || "toggle"
      var route = parts[1] || "root"
      var id = (root.manifest && root.manifest.id) ? root.manifest.id : "henri.menu"
      var payload = JSON.stringify({ menu: route })
      // Beim Plugin-Hot-Reload zieht die Shell die hier hereingereichte API
      // wieder ein (revokePluginShellApi), das Panel selbst bleibt aber
      // geladen (keepLoaded: true) — danach steht in root.shell null und
      // Super+Space war bis zum nächsten Shell-Neustart tot. Der Umweg über
      // die IPC kostet genau die ~95 ms, die der Ereignisweg sonst spart,
      // aber nur in diesem kaputten Zustand.
      if (!root.shell) {
        if (verb === "close") Quickshell.execDetached(["omarchy-shell", "-q", "shell", "hide", id])
        else if (verb === "summon") Quickshell.execDetached(["omarchy-shell", "-q", "shell", "summon", id, payload])
        else Quickshell.execDetached(["omarchy-shell", "-q", "shell", "toggle", id, payload])
        return
      }
      if (verb === "close") root.shell.hide(id)
      else if (verb === "summon") root.shell.summon(id, payload)
      else root.shell.toggle(id, payload)
    }
  }

  property string fontFamily: Style.font.menuFamily
  // JSONC menu definitions. The shell parses both at startup and merges
  // the user file on top of the defaults, so the keybind → IPC → visible
  // path doesn't have to shell out to bash + jq on every open.
  property string defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  property var defaultMenuItems: []
  property var userMenuItems: []
  property bool opened: false
  property string mode: "menu"
  readonly property bool dmenuActive: mode === "select" || mode === "input"
  property string dmenuPrompt: ""
  property var dmenuOptions: []
  property string selectionFile: ""
  property string doneFile: ""
  property int dmenuWidth: 300
  property int dmenuMaxHeight: 0
  property bool requestActive: false
  property bool rowsLoaded: false
  property string activeMenu: "root"
  property string filterText: ""
  // A stray multi-kilobyte clipboard must not be ranked against every row.
  readonly property int maxPasteLength: 512
  property int selectedIndex: 0
  property bool cursorActive: false
  property int requestSerial: 0
  property int applySerial: 0
  property var items: ({})
  property var itemOrder: []
  property var navStack: []
  property var providersLoaded: ({})
  property var providerQueue: []
  property int providerRevision: 0

  // Shared application engine (entries, hidden filters, icons, launch,
  // removal), owned by the shell and also used by the standalone launcher.
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  property var fallbackHiddenIds: ({})
  property string fallbackConfiguredHides: ""
  property string searchEngineRaw: ""

  function fallbackBase() {
    var base = String(root.omarchyPath || "")
    return base.length > 0 ? base : "/usr/share/omarchy"
  }
  function fallbackDesktops() {
    return [Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")].filter(function(v) { return String(v || "").length > 0 }).join(":")
  }
  function fallbackIsHidden(entry) {
    var id = String((entry && entry.id) || "")
    if (!id) return true
    if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
    return root.fallbackHiddenIds[id] === true
  }
  function fallbackEntries(query) {
    var values = []
    try { values = DesktopEntries.applications.values || [] } catch (e) { return [] }
    return AppSearch.sortedEntries(values, query, root.fallbackIsHidden)
  }
  function fallbackName(entry) { return AppSearch.entryName(entry) }
  function fallbackSubtext(entry) { return AppSearch.entrySubtext(entry) }
  function fallbackIcon(icon) {
    var value = String(icon || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var themed = Quickshell.iconPath(value, true)
    if (themed.length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }
  function fallbackLaunch(appId) {
    var id = String(appId || "")
    if (!id) return
    if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
    Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", id + ".desktop"])
  }
  function fallbackRemove(appId, label) {
    var id = String(appId || "")
    if (!id) return
    if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
    Quickshell.execDetached([root.fallbackBase() + "/bin/omarchy-remove-launcher-entry", id, String(label || id)])
  }
  function loadFallbackHides(rawText) {
    var next = ({})
    var lines = String(rawText || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var id = lines[i].trim()
      if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
      if (id.length > 0) next[id] = true
    }
    root.fallbackHiddenIds = next
    if (root.opened && root.providersLoaded["apps"]) root.mergeAppRows()
  }
  function refreshFallbackHides() {
    fallbackHidesScan.running = false
    fallbackHidesScan.command = ["bash", root.fallbackBase() + "/shell/services/hidden-entries.sh", root.fallbackDesktops()]
    fallbackHidesScan.running = true
  }
  function searchEngineTemplate() {
    var raw = String(root.searchEngineRaw || "").trim()
    if (raw.length === 0) raw = "google"
    if (raw.indexOf("%s") >= 0) return { name: "Web", url: raw }
    var presets = {
      google: ["Google", "https://www.google.com/search?q=%s"],
      duckduckgo: ["DuckDuckGo", "https://duckduckgo.com/?q=%s"],
      bing: ["Bing", "https://www.bing.com/search?q=%s"],
      brave: ["Brave", "https://search.brave.com/search?q=%s"]
    }
    var hit = presets[raw.toLowerCase()]
    if (hit) return { name: hit[0], url: hit[1] }
    return { name: "Google", url: presets.google[1] }
  }
  function searchEngineUrl(query) {
    var template = root.searchEngineTemplate().url
    return template.replace("%s", encodeURIComponent(query).replace(/'/g, "%27"))
  }

  // -------------------------------------------------------- file search mode
  //
  // A query that opens with a space searches the filesystem instead of the
  // menu: " report" finds files and folders by name under $HOME, and a query
  // that names a path (" ~/Projects/", " /etc/ho") lists that directory. The
  // leading space is what switches modes -- a menu search trims to nothing on
  // it, so the two can never claim the same keystrokes.
  //
  // Scanning is fd (shipped in omarchy-base), ranking is FuzzySearch here:
  // fd hands over a bounded candidate set in one pass and the ordering is
  // recomputed on every keystroke, so the list narrows without rescanning.
  // The Files category (⌃2, the doc button) searches files as well, without
  // the leading blank.
  readonly property bool fileSearchActive: !root.dmenuActive && (root.category === "files" || root.filterText.charAt(0) === " ")
  readonly property string fileQuery: !root.fileSearchActive ? ""
    : root.category === "files" ? root.filterText.trim() : root.filterText.slice(1).trim()
  property var fileRows: []
  property string fileScanQuery: ""
  property bool fileScanPending: false
  readonly property int fileResultLimit: 40
  readonly property string folderGlyph: Apple.sf(0x100215)   // SF folder
  readonly property string fileGlyph: Apple.sf(0x100237)     // SF doc

  function homeDir() { return Quickshell.env("HOME") || "" }

  function expandHome(path) {
    var value = String(path || "")
    if (value === "~") return root.homeDir()
    if (value.indexOf("~/") === 0) return root.homeDir() + value.slice(1)
    return value
  }

  function prettyPath(path) {
    var value = String(path || "")
    var home = root.homeDir()
    if (!home) return value
    if (value === home) return "~"
    if (value.indexOf(home + "/") === 0) return "~" + value.slice(home.length)
    return value
  }

  function escapeRegex(value) {
    return String(value || "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  }

  function dirNameOf(path) {
    var value = String(path || "")
    var cut = value.lastIndexOf("/")
    if (cut < 0) return ""
    return cut === 0 ? "/" : value.slice(0, cut)
  }

  function baseNameOf(path) {
    var value = String(path || "")
    var cut = value.lastIndexOf("/")
    return cut < 0 ? value : value.slice(cut + 1)
  }

  // What to ask fd for. A query naming a directory browses that directory one
  // level deep; anything else is a name search rooted at $HOME. Several words
  // match against the whole path so "proj readme" can span directories, while
  // a single word stays on the file name -- matched against the path, "doc"
  // would answer with everything under ~/Documents.
  function fileScanPlan(query) {
    var raw = String(query || "")
    var expanded = root.expandHome(raw)

    if (!raw || raw === "~" || expanded.charAt(0) === "/") {
      var dir = root.homeDir()
      var base = ""
      if (raw && raw !== "~") {
        if (expanded.slice(-1) === "/") dir = expanded.length > 1 ? expanded.slice(0, -1) : "/"
        else {
          dir = root.dirNameOf(expanded) || "/"
          base = root.baseNameOf(expanded)
        }
      }
      return { mode: "path", dir: dir, pattern: root.escapeRegex(base), rank: base, showHidden: base.charAt(0) === "." }
    }

    var tokens = raw.split(/\s+/).filter(function(token) { return token.length > 0 })
    var escaped = []
    for (var i = 0; i < tokens.length; i++) escaped.push(root.escapeRegex(tokens[i]))
    return {
      mode: tokens.length > 1 ? "full" : "name",
      dir: root.fileSearchRoots().join("\n"),
      pattern: escaped.join(".*"),
      rank: raw
    }
  }

  // A home's worth of dotfiles is mostly caches and vendored trees; excluding
  // them is what keeps a name search answering with the user's own files.
  readonly property var defaultFileScanExcludes: [".git", "node_modules", ".cache",
    ".npm", ".cargo", ".rustup", ".venv", "__pycache__",
    ".mozilla", ".thunderbird", ".steam", ".var", "Trash"]

  // User settings from the "fileSearch" section of ~/.config/omarchy/menu.json:
  //   roots            folders a name search covers (default ["~"])
  //   exclude          extra fd/gitignore-style globs to skip; "~/foo" is
  //                    anchored to the home root, "foo" matches at any depth
  //   defaultExcludes  false drops the built-in list above
  //   hidden           false skips dotfiles and dot-directories
  // Browsing a folder (the bare " " listing or a typed path) hides the same
  // excluded entries and dotfiles; typing a "." brings dotfiles back, and
  // browsing *into* an excluded folder still lists what is inside it.
  property var fileSearchConfig: ({})

  function fileSearchRoots() {
    var configured = root.fileSearchConfig.roots
    var roots = []
    if (Array.isArray(configured)) {
      for (var i = 0; i < configured.length; i++) {
        var value = root.expandHome(String(configured[i] || "").trim())
        if (value.length > 1 && value.slice(-1) === "/") value = value.slice(0, -1)
        if (value.charAt(0) === "/") roots.push(value)
      }
    }
    return roots.length > 0 ? roots : [root.homeDir()]
  }

  function fileScanExcludeList() {
    var list = root.fileSearchConfig.defaultExcludes === false ? [] : root.defaultFileScanExcludes.slice()
    var extra = root.fileSearchConfig.exclude
    if (!Array.isArray(extra)) return list
    var home = root.homeDir()
    for (var i = 0; i < extra.length; i++) {
      var pattern = String(extra[i] || "").trim()
      if (!pattern) continue
      if (pattern === "~" || pattern === home) continue
      if (pattern.indexOf("~/") === 0) pattern = pattern.slice(1)
      else if (home && pattern.indexOf(home + "/") === 0) pattern = pattern.slice(home.length)
      list.push(pattern)
    }
    return list
  }

  // Emits `<d|f>\t<absolute path>` per line. fd marks a directory with a
  // trailing slash, which would leave the row with an empty name, so it comes
  // back off. The query never reaches the shell as text: mode, roots (one per
  // line), pattern, hidden flag and excludes arrive as positional parameters.
  readonly property string fileScanScript: "mode=$1; pat=$3; hidden=$4\n"
    + "mapfile -t dirs <<<\"$2\"\n"
    + "shift 4\n"
    + "roots=(); for d in \"${dirs[@]}\"; do [[ -d $d ]] && roots+=(\"$d\"); done\n"
    + "(( ${#roots[@]} )) || exit 0\n"
    + "ex=(); for e in \"$@\"; do ex+=(--exclude \"$e\"); done\n"
    + "hid=(); [[ $hidden == 1 ]] && hid=(--hidden)\n"
    + "case $mode in\n"
    + "  path) fd --hidden --no-ignore --max-depth 1 --max-results 500 --color never --absolute-path --regex -- \"$pat\" \"${roots[@]}\" ;;\n"
    + "  full) fd \"${hid[@]}\" --full-path --max-results 500 --color never --absolute-path --regex \"${ex[@]}\" -- \"$pat\" \"${roots[@]}\" ;;\n"
    + "  *) fd \"${hid[@]}\" --max-results 500 --color never --absolute-path --regex \"${ex[@]}\" -- \"$pat\" \"${roots[@]}\" ;;\n"
    + "esac 2>/dev/null | awk '!seen[$0]++' | while IFS= read -r p; do\n"
    + "  [[ -z $p ]] && continue\n"
    + "  if [[ -d $p ]]; then printf 'd\\t%s\\n' \"${p%/}\"; else printf 'f\\t%s\\n' \"$p\"; fi\n"
    + "done\n"

  function requestFileScan() {
    if (!root.fileSearchActive) return
    fileScanDebounce.restart()
  }

  // Process ignores a command change while it is running, so a keystroke that
  // lands mid-scan is queued rather than dropped and the exit handler starts
  // it. `fileScanQuery` is written only here, which is what lets that handler
  // tell the run it is finishing apart from the one the user is now typing.
  function startFileScan() {
    if (!root.fileSearchActive) { root.fileScanPending = false; return }
    if (fileScanProc.running) { root.fileScanPending = true; return }

    root.fileScanPending = false
    root.fileScanQuery = root.fileQuery
    var plan = root.fileScanPlan(root.fileScanQuery)
    fileScanProc.collected = ""
    var hidden = root.fileSearchConfig.hidden === false ? "0" : "1"
    fileScanProc.command = ["bash", "-c", root.fileScanScript, "bash", plan.mode, plan.dir, plan.pattern, hidden]
      .concat(root.fileScanExcludeList())
    fileScanProc.running = true
  }

  function globToRegex(glob) {
    var body = String(glob).replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\?/g, ".")
    return new RegExp("^" + body + "$")
  }

  // fd applies the excludes during a name search; a one-level listing runs
  // without them, so the same rules are checked here per row.
  function browseFilter() {
    var home = root.homeDir()
    var anchored = ({})
    var names = []
    var list = root.fileScanExcludeList()
    for (var i = 0; i < list.length; i++) {
      var pattern = list[i].replace(/\/+$/, "")
      if (!pattern) continue
      if (pattern.charAt(0) === "/") anchored[home + pattern] = true
      else if (pattern.indexOf("/") < 0) {
        try { names.push(root.globToRegex(pattern)) } catch (e) {}
      }
    }
    return function(row) {
      if (anchored[row.path]) return false
      for (var j = 0; j < names.length; j++) if (names[j].test(row.name)) return false
      return true
    }
  }

  function applyFileRows(raw) {
    if (!root.opened || !root.fileSearchActive) return

    var plan = root.fileScanPlan(root.fileScanQuery)
    var browsing = plan.mode === "path"
    var keep = browsing ? root.browseFilter() : null

    var lines = String(raw || "").split("\n")
    var rows = []
    for (var i = 0; i < lines.length; i++) {
      var tab = lines[i].indexOf("\t")
      if (tab < 0) continue
      var path = lines[i].slice(tab + 1)
      if (!path) continue
      var row = { isDir: lines[i].slice(0, tab) === "d", path: path, name: root.baseNameOf(path) }
      if (browsing && !plan.showHidden && row.name.charAt(0) === ".") continue
      if (browsing && !keep(row)) continue
      rows.push(row)
    }

    root.fileRows = rows
    root.rebuildDisplay()
  }

  // Ranked against whatever is in the search line right now, which may be
  // ahead of the scan these candidates came from -- typing keeps narrowing
  // the list already on screen while the next scan is still out.
  function fileDisplayRows() {
    var needle = String(root.fileScanPlan(root.fileQuery).rank || "")
    var candidates = root.fileRows
    var scored = []

    for (var i = 0; i < candidates.length; i++) {
      var score = 0
      if (needle) {
        try {
          score = FuzzySearch.scoreBookmark(needle, {
            title: candidates[i].name,
            domain: "",
            tags: [],
            link: candidates[i].path
          })
        } catch (e) { score = -1 }
        if (score < 0) continue
      }
      scored.push({ hit: candidates[i], score: score, index: i })
    }

    // A directory listing has no ranking to do, so it reads as a listing:
    // folders first, then alphabetical.
    if (!needle) {
      scored.sort(function(a, b) {
        if (a.hit.isDir !== b.hit.isDir) return a.hit.isDir ? -1 : 1
        var aName = a.hit.name.toLowerCase()
        var bName = b.hit.name.toLowerCase()
        return aName < bName ? -1 : (aName > bName ? 1 : 0)
      })
    } else {
      scored.sort(function(a, b) {
        if (a.score !== b.score) return b.score - a.score
        if (a.hit.name.length !== b.hit.name.length) return a.hit.name.length - b.hit.name.length
        return a.index - b.index
      })
    }

    var rows = []
    var limit = Math.min(scored.length, root.fileResultLimit)
    for (var j = 0; j < limit; j++) {
      var hit = scored[j].hit
      rows.push({
        itemId: "file." + hit.path,
        kind: "file",
        icon: hit.isDir ? root.folderGlyph : root.fileGlyph,
        iconFont: Apple.symbolFont,
        appIcon: "",
        appId: "",
        isDir: hit.isDir,
        label: hit.name,
        target: hit.path,
        detail: root.prettyPath(root.dirNameOf(hit.path)),
        path: "",
        childCount: 0,
        action: "",
        provider: "",
        score: j,
        section: needle ? "files" : ""
      })
    }

    return rows
  }

  function rebuildFileDisplay() {
    displayModel.clear()
    root.searchDivider = false

    var rows = root.fileDisplayRows()
    for (var i = 0; i < rows.length; i++) displayModel.append(rows[i])
    layoutSerial += 1
    root.updateTopRow()

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  // Tab descends: on a folder it browses into it, on a file it browses the
  // folder holding it. Enter always opens instead, so neither gesture has to
  // guess which one was meant.
  function completeFileSelection() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.kind !== "file") return
    var target = String(row.target || "")
    root.setFilter(" " + root.prettyPath(row.isDir ? target : root.dirNameOf(target)) + "/")
  }

  function openPath(path) {
    var target = String(path || "")
    if (!target) return
    // gio, not xdg-open: xdg-open sniffs a .md as text/plain and hands it to
    // nvim.desktop without a terminal, so nothing ever appears. gio types by
    // extension and wraps Terminal=true apps in xdg-terminal-exec.
    Util.execArgv(["uwsm-app", "--", "bash", "-c", 'command -v gio >/dev/null && exec gio open "$1"; exec xdg-open "$1"', "bash", target])
  }

  Timer {
    id: fileScanDebounce
    interval: 110
    repeat: false
    onTriggered: root.startFileScan()
  }

  Process {
    id: fileScanProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { fileScanProc.collected += data + "\n" }
    }
    onExited: {
      root.applyFileRows(fileScanProc.collected)
      if (root.fileScanPending || (root.fileSearchActive && root.fileScanQuery !== root.fileQuery))
        Qt.callLater(function() { root.startFileScan() })
    }
  }

  FileView {
    id: fallbackHidesFile
    path: root.fallbackBase() + "/default/omarchy/launcher.hides"
    watchChanges: true
    printErrors: false
    onLoaded: { root.fallbackConfiguredHides = text(); root.loadFallbackHides(text() + "\n" + fallbackHidesOutput.text) }
    onFileChanged: fallbackHidesFile.reload()
    onLoadFailed: { root.fallbackConfiguredHides = ""; root.loadFallbackHides(fallbackHidesOutput.text) }
  }
  QtObject { id: fallbackHidesOutput; property string text: "" }
  Process {
    id: fallbackHidesScan
    stdout: SplitParser { onRead: function(line) { fallbackHidesOutput.text += line + "\n" } }
    onStarted: fallbackHidesOutput.text = ""
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      root.loadFallbackHides(root.fallbackConfiguredHides + "\n" + fallbackHidesOutput.text)
    }
  }
  // ------------------------------------------------------------ app aliases
  //
  // Extra search words per application (AppAliases.js), so a query that is not
  // the app's name still finds it. The user file is watched: adding a word
  // there re-merges the app rows without a restart.
  property var appAliasTable: AppAliases.defaultTable()
  readonly property string appAliasPath: Quickshell.env("HOME") + "/.config/omarchy/app-aliases.jsonc"
  function loadAppAliases(rawText) {
    root.appAliasTable = AppAliases.tableFrom(rawText, MenuModel.stripJsonc)
    if (root.providersLoaded["apps"]) root.mergeAppRows()
  }
  FileView {
    id: appAliasFile
    path: root.appAliasPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadAppAliases(text())
    onFileChanged: appAliasFile.reload()
    onLoadFailed: root.loadAppAliases("")
  }

  FileView {
    id: searchEngineFile
    path: Quickshell.env("HOME") + "/.config/omarchy/menu.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadEngineConfig(text())
    onFileChanged: searchEngineFile.reload()
    onLoadFailed: { root.searchEngineRaw = ""; root.fileSearchConfig = ({}) }
  }
  function loadEngineConfig(rawText) {
    var value = ""
    var fileSearch = ({})
    try {
      var parsed = JSON.parse(String(rawText || ""))
      if (parsed && typeof parsed.searchEngine === "string") value = parsed.searchEngine.trim()
      fileSearch = parsed && typeof parsed.fileSearch === "object" && parsed.fileSearch ? parsed.fileSearch : ({})
    } catch (e) {}
    root.searchEngineRaw = value
    root.fileSearchConfig = fileSearch
  }
  property bool deleteConfirmOpen: false
  property var deleteTarget: null
  onOpenedChanged: if (!opened) {
    // The query comes back, fully selected, on the next open (spec §8) — only
    // from the plain root search; a submenu, dmenu or category starts blank.
    lastQuery = (mode === "menu" && activeMenu === "root" && category === "") ? filterText : ""
    deleteConfirmOpen = false
    deleteTarget = null
    fileScanProc.running = false
    fileRows = []
    category = ""
    querySelected = false
    buttonsPinned = false
  }
  // ------------------------------------------------------------ spotlight look
  //
  // macOS 26 "Tahoe" Spotlight (spotlight-design-spec.md, Variante A): a
  // capsule search field pinned at 23 % of the screen, a separate glass panel
  // for the results growing downward only, four round category buttons to the
  // right. Geometry and material come from apple-ui (`Apple.spotlight`), motion
  // from henri-ui, the selection colour follows the theme accent like macOS
  // follows the system accent. Point values go through Style.space().
  readonly property var sp: Apple.spotlight
  function pt(v) { return Style.space(v) }
  readonly property string uiFont: Apple.uiFont
  readonly property string symbolFont: Apple.symbolFont

  // Light or dark glass follows the theme's appearance (colors.toml mode),
  // judged from the background luminance so a custom theme needs no flag.
  readonly property bool dark: {
    var c = Color.background
    return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5
  }
  readonly property var pal: Apple.spotlightPalette(root.dark)
  readonly property color glassFill: Motion.glass ? pal.fill : pal.opaqueFill
  readonly property color glassBorder: pal.border
  readonly property color glassHighlight: pal.highlight
  readonly property color ink: pal.textPrimary
  readonly property color inkSecondary: pal.textSecondary
  readonly property color inkTertiary: pal.textTertiary
  readonly property color separator: pal.separator
  readonly property color selection: Color.accent
  readonly property color selectionText: Motion.onColor(Color.accent)
  readonly property color hoverFill: pal.hover
  readonly property real shadowAlpha: pal.shadowAlpha

  // The ConfirmDialog (uninstall) still takes the old colour roles.
  readonly property color background: pal.opaqueFill
  readonly property color foreground: root.ink
  readonly property color scrim: Util.alpha(pal.opaqueFill, 0.5)
  readonly property color selectedBackground: root.selection
  readonly property color selectedText: root.selectionText

  readonly property int spotWidth: pt(sp.width)
  readonly property int fieldHeight: pt(sp.fieldHeight)
  readonly property int fieldInset: pt(sp.fieldInset)
  readonly property int fieldIconSize: pt(sp.fieldIcon)
  readonly property int fieldGap: pt(sp.fieldGap)
  readonly property int fieldFontSize: pt(sp.fieldFont)
  readonly property int chipHeight: pt(sp.chipHeight)
  readonly property int chipFontSize: pt(sp.chipFont)
  readonly property int chipPadX: pt(sp.chipPadX)
  readonly property int buttonSize: pt(sp.button)
  readonly property int buttonIconSize: pt(sp.buttonIcon)
  readonly property int buttonGap: pt(sp.buttonGap)
  readonly property int buttonOffset: pt(sp.buttonOffset)
  readonly property int buttonSlide: pt(sp.buttonSlide)
  readonly property int resultsGap: pt(sp.resultsGap)
  readonly property int resultsRadius: pt(sp.resultsRadius)
  readonly property int resultsPadding: pt(sp.resultsPadding)
  readonly property int resultsMaxHeight: pt(sp.resultsMaxHeight)
  readonly property int rowHeight: pt(sp.rowHeight)
  readonly property int rowIcon: pt(sp.rowIcon)
  readonly property int rowGap: pt(sp.rowGap)
  readonly property int rowInset: pt(sp.rowInset)
  readonly property int rowRadius: pt(sp.rowRadius)
  readonly property int rowFontSize: pt(sp.rowFont)
  readonly property int metaFontSize: pt(sp.metaFont)
  readonly property real metaAlpha: sp.metaAlpha
  readonly property int topHeight: pt(sp.topHeight)
  readonly property int topIcon: pt(sp.topIcon)
  readonly property int topGap: pt(sp.topGap)
  readonly property int topFontSize: pt(sp.topFont)
  readonly property int calcFontSize: pt(sp.calcFont)
  readonly property int sectionFontSize: pt(sp.sectionFont)
  readonly property int sectionInset: pt(sp.sectionInset)
  readonly property int sectionLine: Math.round(pt(sp.sectionFont) * 1.3)
  readonly property int shadowOffset: pt(sp.shadowOffset)
  readonly property int shadowBlur: pt(sp.shadowBlur)
  readonly property int shadowSpread: pt(sp.shadowSpread)
  readonly property int emptyStateHeight: pt(72)
  // How much of the first hidden row stays visible at the fold — enough to
  // read as a cut-off row rather than a bottom edge.
  readonly property int rowPeek: Math.round(rowHeight * 0.55)
  readonly property int rowSpacing: 0
  property int layoutSerial: 0
  readonly property bool isAppsGrid: root.activeMenu === "apps" && !root.dmenuActive && !root.fileSearchActive && root.category === ""
  property int gridCellMinWidth: pt(108)
  readonly property int gridIconSize: pt(46)
  readonly property int gridLabelHeight: Math.round(rowFontSize * 2.7)
  readonly property int gridCellPadTop: pt(11)
  readonly property int gridCellPadBottom: pt(9)
  readonly property int gridIconGap: pt(7)
  property int gridCellHeight: root.gridCellPadTop + root.gridIconSize
    + root.gridIconGap + root.gridLabelHeight + root.gridCellPadBottom
  readonly property int gridContentWidth: Math.max(0, resultsViewport.width)
  property int gridColumns: Math.max(1, Math.floor(root.gridContentWidth / root.gridCellMinWidth))
  function gridRowsHeight() {
    var cols = Math.max(1, root.gridColumns)
    var rows = Math.max(1, Math.ceil(displayModel.count / cols))
    var full = rows * root.gridCellHeight
    return Math.min(full, root.availableRowsHeight())
  }

  // -------------------------------------------------------------- categories
  //
  // ⌃1–⌃4 or the round buttons beside the field narrow the search to one
  // kind (spec §5.2). Super+1–4 would be Hyprland's workspace keys, so the
  // control key stands in for ⌘ here. The active one shows as a chip in the
  // field; ⌫ on an empty field removes it, the same key again toggles it off.
  property string category: ""
  property bool buttonsPinned: false
  readonly property var categories: [
    { id: "apps", label: "Applications", glyph: Apple.sf(0x1001F7), key: "1" },     // square.grid.2x2
    { id: "files", label: "Files", glyph: Apple.sf(0x100237), key: "2" },           // doc
    { id: "actions", label: "Actions", glyph: Apple.sf(0x1002E5), key: "3" },       // bolt
    { id: "clipboard", label: "Clipboard", glyph: Apple.sf(0x100243), key: "4" }    // doc.on.clipboard
  ]
  function categoryLabel(id) {
    for (var i = 0; i < root.categories.length; i++) if (root.categories[i].id === id) return root.categories[i].label
    return ""
  }
  function setCategory(id) {
    if (root.dmenuActive) return
    var next = (id && id !== root.category) ? id : ""
    if (next === root.category) return
    root.category = next
    root.buttonsPinned = root.category !== ""
    root.querySelected = false
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    if (root.fileSearchActive) root.requestFileScan()
    else if (root.fileRows.length > 0) root.fileRows = []
    if (root.category === "apps") root.loadProviderForMenu("apps")
    else if (root.category !== "" && root.filterText.trim()) root.loadProvidersForSearch()
    root.scheduleRebuild()
  }

  // ------------------------------------------------------ last query / top row
  property string lastQuery: ""
  // The restored query is drawn selected; the first keystroke replaces it.
  property bool querySelected: false
  property string topLabel: ""
  property string topKind: ""
  property string topItemId: ""
  property string firstSection: ""
  function updateTopRow() {
    if (displayModel.count === 0) { root.topLabel = ""; root.topKind = ""; root.topItemId = ""; root.firstSection = ""; return }
    var r = displayModel.get(0)
    root.topLabel = String(r.label || "")
    root.topKind = String(r.kind || "")
    root.topItemId = String(r.itemId || "")
    root.firstSection = String(r.section || "")
  }
  // Inline completion (spec §8): the rest of the top hit's name, in tertiary,
  // followed by " — <kind>"; Tab or → takes it.
  readonly property string completionQuery: root.fileSearchActive ? root.fileQuery : root.filterText
  readonly property string completionRest: {
    var q = root.completionQuery
    if (!q || root.dmenuActive || root.fileSearchActive || root.category === "clipboard") return ""
    if (root.topKind === "calc" || root.topItemId === "search.web" || !root.topLabel) return ""
    var l = root.topLabel
    if (l.length <= q.length) return ""
    if (l.toLowerCase().indexOf(q.toLowerCase()) !== 0) return ""
    return l.slice(q.length)
  }
  readonly property string completionSuffix: root.completionRest ? " — " + root.kindName(root.topKind, false) : ""
  function acceptCompletion() {
    if (!root.completionRest) return false
    root.setFilter(root.filterText + root.completionRest)
    return true
  }
  function kindName(kind, isDir) {
    switch (kind) {
      case "app": return "Application"
      case "menu": case "link": return "Menu"
      case "action": return "Action"
      case "file": return isDir ? "Folder" : "Document"
      case "calc": return "Calculator"
      case "clip": return "Clipboard"
      default: return ""
    }
  }
  function sectionLabel(section) {
    switch (section) {
      case "top": return "Top Hit"
      case "apps": return "Applications"
      case "actions": return "Actions"
      case "files": return "Files"
      case "clipboard": return "Clipboard"
      case "web": return "Web"
      case "drilldown": return "Elsewhere"
      default: return ""
    }
  }

  // --------------------------------------------------------------- clipboard
  //
  // The Clipboard category lists what omarchy.clipboard captured (its history
  // file is watched); Enter copies the entry back to the clipboard.
  property var clipHistory: []
  readonly property string clipHistoryPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
  FileView {
    id: clipHistoryFile
    path: root.clipHistoryPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadClipHistory(text())
    onFileChanged: clipHistoryFile.reload()
    onLoadFailed: root.clipHistory = []
  }
  function loadClipHistory(raw) {
    var next = []
    try {
      var parsed = JSON.parse(String(raw || "[]"))
      if (Array.isArray(parsed)) {
        for (var i = 0; i < parsed.length; i++) {
          var e = parsed[i]
          if (typeof e === "string") { if (e.trim()) next.push({ type: "text", text: e }); continue }
          if (!e || typeof e !== "object") continue
          if (e.type === "image" && e.path) next.push({ type: "image", path: String(e.path), mime: String(e.mime || "image/png"), capturedAt: String(e.capturedAt || "") })
          else if (String(e.text || "").trim()) next.push({ type: "text", text: String(e.text) })
        }
      }
    } catch (err) { next = [] }
    root.clipHistory = next
    if (root.opened && root.category === "clipboard") root.scheduleRebuild()
  }
  function clipRows(query) {
    var terms = String(query || "").toLowerCase().trim().split(/\s+/).filter(function(t) { return t.length > 0 })
    var rows = []
    for (var i = 0; i < root.clipHistory.length && rows.length < 60; i++) {
      var e = root.clipHistory[i]
      var label, detail, hay, target, mime = ""
      if (e.type === "image") {
        label = "Image"
        detail = e.capturedAt || root.baseNameOf(e.path)
        hay = ("image " + root.baseNameOf(e.path)).toLowerCase()
        target = e.path
        mime = e.mime
      } else {
        var lines = e.text.split("\n").filter(function(l) { return l.trim().length > 0 })
        label = (lines[0] || e.text).trim().replace(/\s+/g, " ")
        if (label.length > 120) label = label.slice(0, 119) + "…"
        detail = lines.length > 1 ? lines.length + " lines" : ""
        hay = e.text.toLowerCase()
        target = e.text
      }
      var ok = true
      for (var t = 0; t < terms.length; t++) if (hay.indexOf(terms[t]) < 0) { ok = false; break }
      if (!ok) continue
      rows.push({
        itemId: "clip." + i,
        kind: "clip",
        icon: e.type === "image" ? Apple.sf(0x1003C5) : Apple.sf(0x100243),
        iconFont: Apple.symbolFont,
        appIcon: "",
        appId: mime,
        isDir: false,
        label: label,
        target: target,
        detail: detail,
        path: "",
        childCount: 0,
        action: "",
        provider: "",
        score: i,
        section: "clipboard"
      })
    }
    return rows
  }
  function copyToClipboard(text) {
    if (!text) return
    Quickshell.execDetached(["bash", "-c", "printf '%s' \"$1\" | wl-copy", "bash", String(text)])
  }
  function copyImageToClipboard(path, mime) {
    if (!path) return
    Quickshell.execDetached(["bash", "-c", "wl-copy --type \"$1\" < \"$2\"", "bash", String(mime || "image/png"), String(path)])
  }
  function copySelected() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) {
      if (root.filterText.trim()) root.copyToClipboard(root.filterText.trim())
      return
    }
    var row = displayModel.get(root.selectedIndex)
    if (row.kind === "calc") root.copyToClipboard(String(row.label || "").replace(/^=\s*/, ""))
    else if (row.kind === "file") root.copyToClipboard(row.target)
    else if (row.kind === "clip") { if (row.appId) root.copyImageToClipboard(row.target, row.appId); else root.copyToClipboard(row.target) }
    else root.copyToClipboard(row.label)
  }
  function webSearch(query) {
    var q = String(query || "").trim()
    if (!q) return
    applySerial = requestSerial
    opened = false
    filterText = ""
    root.runAction("omarchy-launch-webapp '" + root.searchEngineUrl(q) + "'")
  }

  // Spotlight opens as the search line alone: with nothing typed and no
  // category the root menu shows no results panel at all. Everything is one
  // keystroke away, and a submenu, category or dmenu prompt lists its rows.
  readonly property bool blankRoot: !root.dmenuActive && !root.fileSearchActive
    && root.activeMenu === "root" && root.filterText.trim().length === 0 && root.category === ""
  readonly property bool resultsShown: root.opened && !root.blankRoot && !(root.dmenuActive && root.mode === "input")

  readonly property string emptyStateText: {
    if (root.fileSearchActive)
      return root.fileQuery ? "No files matching “" + root.fileQuery + "”" : "Searching…"
    if (root.category === "clipboard")
      return root.filterText.trim() ? "Nothing on the clipboard matches “" + root.filterText.trim() + "”" : "Clipboard is empty"
    return root.filterText ? "No matches for “" + root.filterText + "”" : "Nothing here yet"
  }
  // Blinking caret. Restarted on every edit so the caret is solid while typing.
  property bool caretOn: true
  readonly property string searchPlaceholder: {
    if (root.dmenuActive) return root.dmenuPrompt
    if (root.category === "files") return "Search Files"
    if (root.fileSearchActive) return "Search files and folders"
    if (root.category === "apps") return "Search Applications"
    if (root.category === "actions") return "Search Actions"
    if (root.category === "clipboard") return "Search Clipboard"
    if (root.activeMenu === "root") return "Spotlight Search"
    var entry = root.item(root.activeMenu)
    if (entry && (entry.title || entry.label)) return entry.title || entry.label
    return "Spotlight Search"
  }
  // A dmenu caller may ask for more width than Spotlight's; never less.
  property int cardWidth: Math.min(root.dmenuActive
    ? Math.max(root.pt(root.dmenuWidth), root.spotWidth) : root.spotWidth, panel.width - Style.gapsOut * 2)
  property int visibleRowsHeight: root.blankRoot ? 0 : (root.dmenuActive ? dmenuRowListHeight(layoutSerial, displayModel.count, filterText) : (root.isAppsGrid ? root.gridRowsHeight() : rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)))
  property bool searchDivider: false

  function finishRequest(selection) {
    if (!root.requestActive || !root.doneFile) {
      root.opened = false
      return
    }

    var activeSelectionFile = root.selectionFile
    var activeDoneFile = root.doneFile
    root.requestActive = false
    root.selectionFile = ""
    root.doneFile = ""

    if (selection === null || selection === undefined) {
      resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(activeDoneFile)]
    } else {
      resultProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(selection) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)]
    }
    resultProc.running = true
  }

  function runAction(action) {
    var command = String(action || "")
    if (!command) return

    Util.execDetached(command)
  }

  // Row heights (spec §7): 36 pt rows, the Top Hit 48 pt with a subtitle;
  // a dmenu row with caller subtext needs the two-line height as well.
  function rowHeightFor(row) {
    if (!row) return root.rowHeight
    if (row.section === "top") return root.topHeight
    if (row.kind === "dmenu" && row.detail) return root.topHeight
    return root.rowHeight
  }
  function sectionHeaderHeight(first) {
    return root.pt(first ? root.sp.sectionTopFirst : root.sp.sectionTop) + root.sectionLine + root.pt(root.sp.sectionBottom)
  }

  // Height the results panel can devote to rows: below the field, above the
  // bottom gap, and never more than the spec's 480 pt panel.
  function availableRowsHeight() {
    var top = panel.fieldTop + root.fieldHeight + root.resultsGap + root.resultsPadding * 2
    var available = panel.height - top - Style.gapsOut
    return Math.min(available, root.resultsMaxHeight - root.resultsPadding * 2)
  }

  // When every row fits, the list gets its full height. When they don't,
  // the panel must end mid-row: a clipped row is what tells the eye there is
  // more below the fold, so never come out even on a row boundary.
  function foldedListHeight(totals, available, heads) {
    var count = totals.length
    if (count === 0) return root.rowHeight
    if (totals[count - 1] <= available) return totals[count - 1]

    var full = 0
    while (full < count && totals[full] <= available) full++
    // The peeking row shows together with the section header above it, so
    // the fold never lands on a lone header.
    var peekFor = function(i) { return root.rowPeek + (heads && i < heads.length ? heads[i] : 0) }
    while (full > 1 && totals[full - 1] + root.rowSpacing + peekFor(full) > available) full--
    if (full < 1) return Math.max(available, root.rowHeight)

    return totals[full - 1] + root.rowSpacing + peekFor(full)
  }

  function rowListHeight(_serial, _count, _filter, _divider) {
    if (displayModel.count === 0) return root.emptyStateHeight

    var totals = []
    var heads = []
    var total = 0
    var previousSection = null
    var available = availableRowsHeight()

    for (var i = 0; i < displayModel.count; i++) {
      var row = displayModel.get(i)
      if (i > 0) total += root.rowSpacing
      var head = (row.section && row.section !== previousSection) ? root.sectionHeaderHeight(i === 0) : 0
      total += head + root.rowHeightFor(row)
      previousSection = row.section
      totals.push(total)
      heads.push(head)
      // Rows past the first one that overflows cannot change the fold.
      if (total > available) break
    }

    return foldedListHeight(totals, available, heads)
  }

  function dmenuRowListHeight(_serial, _count, _filter) {
    if (root.mode === "input") return 0
    if (displayModel.count === 0) return root.emptyStateHeight

    var available = availableRowsHeight()
    if (root.dmenuMaxHeight > 0) available = Math.min(available, root.pt(root.dmenuMaxHeight))

    var totals = []
    var total = 0
    for (var i = 0; i < displayModel.count; i++) {
      if (i > 0) total += root.rowSpacing
      total += root.rowHeightFor(displayModel.get(i))
      totals.push(total)
      if (total > available) break
    }

    return foldedListHeight(totals, available)
  }

  function item(id) {
    return root.items[id] || null
  }

  // ------------------------------------------------------------------
  // JSONC → normalized item array. Mirrors the bash bin's jq pipeline so
  // the on-disk authoring format stays untouched.
  // ------------------------------------------------------------------

  function stripJsonc(raw) {
    return MenuModel.stripJsonc(raw)
  }

  function normalizeAliases(value) {
    return MenuModel.normalizeAliases(value)
  }

  function normalizeItem(id, raw) {
    return MenuModel.normalizeItem(id, raw)
  }

  function parseMenuJsonc(raw) {
    return MenuModel.parseMenuJsonc(raw)
  }

  // Merge defaults + user extension. Later entries override earlier ones
  // on a per-key basis (so the user can tweak label/icon/action without
  // re-declaring the whole row).
  function rebuildItemsFromSources() {
    var mergedMenu = MenuModel.mergeMenuSources(root.defaultMenuItems, root.userMenuItems)
    root.providerRevision += 1
    root.providersLoaded = ({})
    root.providerQueue = []
    root.items = mergedMenu.items
    root.itemOrder = mergedMenu.itemOrder
    root.rowsLoaded = true
    root.evaluateGuards()
    if (root.opened) {
      root.rebuildDisplay()
      if (!root.dmenuActive) {
        if (root.filterText.trim()) root.loadProvidersForSearch()
        else root.loadProviderForMenu(root.activeMenu)
      }
    }
  }

  // Each known provider is a tiny bash one-liner that enumerates a list and
  // emits one tab-delimited row per item: `label\tvalue\tcurrent`. The shell
  // turns those into menu items children of `menuId`. A `volatile` provider
  // re-runs every time its submenu is entered, so a font installed since the
  // shell started shows up without restarting it.
  readonly property var providers: ({
    "fonts": {
      script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
      icon: "",
      volatile: true,
      actionFor: function(value) { return "omarchy-font-set " + Util.shellQuote(value) }
    },
    "power-profiles": {
      script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
      icon: "\udb81\udc0b",
      actionFor: function(value) { return "omarchy-powerprofiles-set autodetect " + Util.shellQuote(value) }
    }
  })

  function slugify(value) {
    return MenuModel.slugify(value)
  }

  // The apps provider is QML-native: rows come from the shared AppLibrary
  // (DesktopEntries) instead of a bash enumeration, so they carry image
  // icons, launch feedback, and uninstall support like the launcher.
  function mergeAppRows() {
    var useLib = !!root.appLibrary
    var rows = useLib ? root.appLibrary.sortedEntries("") : root.fallbackEntries("")
    var appRows = []
    for (var j = 0; j < rows.length; j++) {
      var entry = rows[j].entry
      var appId = String(entry.id || "")
      if (!appId) continue
      var subtext = useLib ? root.appLibrary.entrySubtext(entry) : root.fallbackSubtext(entry)
      var label = useLib ? root.appLibrary.entryName(entry) : root.fallbackName(entry)
      var aliases = subtext ? [subtext] : []
      try {
        if (entry.keywords && typeof entry.keywords.join === "function") aliases = aliases.concat(entry.keywords)
      } catch (e) { }
      // Most .desktop files ship no Keywords at all, so words nobody would
      // guess from the name ("notes" for Omawrite, "photoshop" for Pinta)
      // come from AppAliases plus the user's own file.
      aliases = AppAliases.dedupe(aliases.concat(AppAliases.aliasesFor(root.appAliasTable, appId, label)))
      appRows.push({
        id: "apps." + appId,
        parent: "apps",
        kind: "app",
        icon: "",
        appIcon: String(entry.icon || ""),
        appId: appId,
        label: label,
        title: "",
        target: "",
        description: subtext,
        action: "",
        provider: "",
        aliases: aliases,
        when: "",
        checked: "",
        order: 0
      })
    }

    var merged = MenuModel.mergeAppRows(root.items, root.itemOrder, appRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.scheduleRebuild()
  }

  function startProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return
    if (entry.provider === "apps") {
      root.providersLoaded[id] = true
      root.mergeAppRows()
      return
    }
    var spec = root.providers[entry.provider]
    if (!spec) return

    root.providersLoaded[id] = true
    providerProc.menuId = id
    providerProc.providerKey = entry.provider
    providerProc.revision = root.providerRevision
    providerProc.collected = ""
    providerProc.command = ["bash", "-lc", spec.script]
    providerProc.running = true
  }

  function mergeProviderRows(rows, menuId, providerKey) {
    var spec = root.providers[providerKey]
    if (!spec) return
    var lines = String(rows || "").split("\n")
    var providerRows = []
    var takenIds = ({})
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var parts = line.split("\t")
      var label = parts[0] || ""
      var value = parts[1] || parts[0] || ""
      var current = parts[2] || ""
      if (!label) continue
      // Distinct values can slugify alike — Fira Code and Fira-Code both give
      // fira-code — and a repeated id is dropped, which would silently lose a
      // row from the list. Nudge it until it is the row's own.
      var rowId = menuId + "." + root.slugify(value)
      while (takenIds[rowId]) rowId += "-"
      takenIds[rowId] = true

      providerRows.push({
        id: rowId,
        parent: menuId,
        kind: "action",
        icon: (value === current) ? "✓" : (spec.icon || ""),
        label: label,
        title: "",
        target: "",
        description: "",
        action: spec.actionFor(value),
        provider: "",
        aliases: [],
        when: "",
        checked: "",
        order: 0
      })
    }
    var merged = MenuModel.swapProviderRows(root.items, root.itemOrder, menuId, providerRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.scheduleRebuild()
  }

  function startNextProvider() {
    if (providerProc.running) return

    while (root.providerQueue.length > 0) {
      var id = root.providerQueue.shift()
      var entry = root.item(id)
      if (!entry || !entry.provider || root.providersLoaded[id]) continue

      root.startProviderForMenu(id)
      return
    }
  }

  // Entering a submenu is the one moment a volatile list is worth paying for
  // again: it may have been reshaped by the last pick from it. Search doesn't
  // invalidate, or every keystroke would restart the same enumeration.
  function invalidateVolatileProvider(id) {
    var entry = root.item(id)
    var spec = entry && entry.provider ? root.providers[entry.provider] : null
    if (spec && spec.volatile) root.providersLoaded[id] = false
  }

  function loadProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return

    // Native providers don't touch providerProc, so they never need to queue.
    if (entry.provider === "apps") {
      root.startProviderForMenu(id)
      return
    }

    if (providerProc.running) {
      if (root.providerQueue.indexOf(id) < 0) root.providerQueue = root.providerQueue.concat([id])
      return
    }

    root.startProviderForMenu(id)
  }

  function loadProvidersForSearch() {
    var active = root.item(root.activeMenu) ? root.activeMenu : "root"

    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue
      if (active !== "root" && entry.id !== active && !root.isDescendantOf(entry.id, active)) continue

      root.loadProviderForMenu(entry.id)
    }
  }

  function depthFor(id) {
    return MenuModel.depthFor(root.items, id)
  }

  function pathFor(id) {
    return MenuModel.pathFor(root.items, id)
  }

  function parentPathFor(id) {
    return MenuModel.parentPathFor(root.items, id)
  }

  function isDescendantOf(id, ancestorId) {
    return MenuModel.isDescendantOf(root.items, id, ancestorId)
  }

  function childCount(id) {
    return MenuModel.childCount(root.items, root.itemOrder, id)
  }

  // Guarded items are hidden when their `when:` evaluates false. Static
  // submenus are also hidden when none of their descendants are visible;
  // provider-backed menus stay visible because their rows load on demand.
  function isVisible(entry) {
    return MenuModel.isVisible(root.items, root.itemOrder, root.whenResults, entry)
  }

  // Label with the ✓ marker baked in when `checked:` evaluated truthy.
  function labelFor(entry) {
    return MenuModel.labelFor(entry, root.checkedResults)
  }

  function searchableToken(value) {
    return MenuModel.searchableToken(value)
  }

  function leafIdFor(id) {
    return MenuModel.leafIdFor(id)
  }

  function nameSearchText(entry) {
    return MenuModel.nameSearchText(entry)
  }

  function termInSearchWords(term, text) {
    return MenuModel.termInSearchWords(term, text)
  }

  function descriptionTextMatches(query, text) {
    return MenuModel.descriptionTextMatches(query, text)
  }

  function fuzzyBookmark(entry) {
    return {
      title: MenuModel.labelFor(entry, root.checkedResults),
      domain: "",
      tags: [entry.description || "", entry.appId || ""],
      link: entry.id,
      // One field per alias instead of one joined string, so a synonym that
      // is exactly the query ("notes" for Omawrite) earns the exact-match
      // bonus and lifts its app to the top.
      aliases: entry.aliases || []
    }
  }
  function fuzzyScore(entry, query) {
    try { return FuzzySearch.scoreBookmark(String(query || ""), root.fuzzyBookmark(entry)) } catch (e) { return -1 }
  }
  function matchesQuery(entry, query) {
    if (!entry || entry.id === "root") return false
    if (!root.isVisible(entry)) return false
    return root.fuzzyScore(entry, query) >= 0
  }

  function searchScore(entry, query) {
    var fuzzy = root.fuzzyScore(entry, query)
    if (fuzzy < 0) return 1e15
    return -fuzzy * 1000 + MenuModel.depthFor(root.items, entry.id) * 25 + entry.order
  }

  function displayRow(entry, detail, score, section, index) {
    return MenuModel.displayRow(root.items, root.itemOrder, root.checkedResults, entry, detail, score, section, index)
  }

  function rebuildDmenuDisplay() {
    displayModel.clear()
    root.searchDivider = false

    if (root.mode === "input") {
      layoutSerial += 1
      root.updateTopRow()
      return
    }

    var query = root.filterText.trim().toLowerCase()
    for (var i = 0; i < root.dmenuOptions.length; i++) {
      // An option is "<label>", "<glyph>\t<label>", or
      // "<glyph>\t<label>\t<subtext>". The glyph never comes back with the
      // selection; the subtext renders under the label, filters alongside it,
      // and returns with the selection as a stable key for same-named rows.
      var parts = String(root.dmenuOptions[i] || "").split("\t")
      var icon = parts.length > 1 ? parts.shift() : ""
      var label = parts.shift() || ""
      var detail = parts.join("\t")
      if (query && label.toLowerCase().indexOf(query) < 0
          && detail.toLowerCase().indexOf(query) < 0) continue
      displayModel.append({
        itemId: "dmenu." + i,
        kind: "dmenu",
        icon: icon,
        iconFont: "",
        appIcon: "",
        appId: "",
        isDir: false,
        label: label,
        target: "",
        detail: detail,
        path: "",
        childCount: 0,
        action: "",
        provider: "",
        score: i,
        section: ""
      })
    }

    layoutSerial += 1
    root.updateTopRow()

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  // Typing and async provider/guard results schedule a rebuild instead of
  // running one each: keystrokes that queue up while a pass runs then
  // collapse into a single pass. Anything that reads displayModel for the
  // selection flushes first, so it never acts on stale rows.
  property bool displayDirty: false

  Timer {
    id: rebuildTimer
    interval: 0
    onTriggered: root.flushRebuild()
  }

  function scheduleRebuild() {
    root.displayDirty = true
    if (!rebuildTimer.running) rebuildTimer.start()
  }

  function flushRebuild() {
    rebuildTimer.stop()
    if (!root.displayDirty) return
    root.rebuildDisplay()
  }

  function rebuildDisplay() {
    root.displayDirty = false
    rebuildTimer.stop()
    if (root.dmenuActive) {
      root.rebuildDmenuDisplay()
      return
    }

    if (root.fileSearchActive) {
      root.rebuildFileDisplay()
      return
    }

    displayModel.clear()

    if (!root.rowsLoaded) return

    var active = root.item(root.activeMenu) ? root.activeMenu : "root"
    root.activeMenu = active
    var rows = []
    var query = root.filterText.trim()
    root.searchDivider = false

    if (root.category === "clipboard") {
      rows = root.clipRows(query)
    } else if (query) {
      var currentRows = []
      var drilldownRows = []
      // One pass per keystroke: children and visibility are indexed once,
      // and each row is fuzzy-scored once rather than to match and again
      // to rank.
      var index = MenuModel.childIndex(root.items, root.itemOrder)
      var visibleMemo = ({})

      for (var i = 0; i < root.itemOrder.length; i++) {
        var entry = root.item(root.itemOrder[i])
        if (!entry || entry.id === "root") continue
        if (root.category === "apps" && entry.kind !== "app") continue
        if (root.category === "actions" && entry.kind === "app") continue
        if (!root.isDescendantOf(entry.id, active)) continue
        var fuzzy = root.fuzzyScore(entry, query)
        if (fuzzy < 0) continue
        if (!MenuModel.isVisibleIndexed(index, root.whenResults, entry, visibleMemo)) continue

        var detail = entry.kind === "app" ? String(entry.description || "") : root.parentPathFor(entry.id)
        var row = root.displayRow(entry, detail, -fuzzy * 1000 + MenuModel.depthFor(root.items, entry.id) * 25 + entry.order, "", index)
        if (entry.parent === active) currentRows.push(row)
        else drilldownRows.push(row)
      }

      var searchSort = function(a, b) {
        if (a.score !== b.score) return a.score - b.score
        return a.path.localeCompare(b.path)
      }

      if (active === "root") {
        // At the root every hit competes on score alone: the best one is the
        // Top Hit, the rest sit under their kind (spec §5.3, §7).
        rows = currentRows.concat(drilldownRows)
        rows.sort(searchSort)
        var calcResult = root.category === "" ? MenuModel.calcEvaluate(query) : null
        if (calcResult !== null) {
          rows.unshift({
            itemId: "calc.result",
            kind: "calc",
            icon: Apple.sf(0x100180),
            iconFont: Apple.symbolFont,
            appIcon: "",
            appId: "",
            isDir: false,
            label: "= " + String(calcResult),
            target: "",
            detail: "Calculator · ↩ copies the result",
            path: "",
            childCount: 0,
            action: "",
            provider: "",
            score: -1e15,
            section: ""
          })
        }
        // The best hit stays on top; everything else regroups under its kind
        // in a fixed order, keeping the score order inside each group.
        var grouped = rows.length > 0 ? [rows[0]] : []
        grouped[0] && (grouped[0].section = "top")
        var groupOrder = ["apps", "actions"]
        for (var g = 0; g < groupOrder.length; g++) {
          for (var s = 1; s < rows.length; s++) {
            var sectionFor = rows[s].kind === "app" ? "apps" : "actions"
            if (sectionFor !== groupOrder[g]) continue
            rows[s].section = sectionFor
            grouped.push(rows[s])
          }
        }
        rows = grouped
        if (root.category === "") {
          var engine = root.searchEngineTemplate()
          var engineHost = engine.url.split("/")[2] || engine.name
          rows.push({
            itemId: "search.web",
            kind: "action",
            icon: Apple.sf(0x1002AB),
            iconFont: Apple.symbolFont,
            appIcon: "",
            appId: "",
            isDir: false,
            label: "Search " + engine.name + " for “" + query + "”",
            target: "",
            detail: engineHost,
            path: "",
            childCount: 0,
            action: "omarchy-launch-webapp '" + root.searchEngineUrl(query) + "'",
            provider: "",
            score: 1e15,
            section: rows.length === 0 ? "top" : "web"
          })
        }
      } else {
        currentRows.sort(searchSort)
        drilldownRows.sort(searchSort)
        root.searchDivider = currentRows.length > 0 && drilldownRows.length > 0
        if (root.searchDivider) {
          for (var d = 0; d < drilldownRows.length; d++) drilldownRows[d].section = "drilldown"
        }
        rows = currentRows.concat(drilldownRows)
      }
    } else if (!root.blankRoot) {
      // A category with nothing typed lists everything of its kind; the
      // Actions category lists the root menu, Applications every app.
      var listMenu = root.category === "apps" ? "apps" : active
      for (var j = 0; j < root.itemOrder.length; j++) {
        var child = root.item(root.itemOrder[j])
        if (!child || child.parent !== listMenu) continue
        if (root.category === "actions" && child.kind === "app") continue
        if (!root.isVisible(child)) continue
        rows.push(root.displayRow(child, child.description, child.order))
      }

      // DesktopEntries can reorder its values when an application starts.
      // Keep the Apps list alphabetical independently of provider refreshes.
      if (listMenu === "apps") {
        rows.sort(function(a, b) {
          var aLabel = String(a.label || "").toLowerCase()
          var bLabel = String(b.label || "").toLowerCase()
          if (aLabel < bLabel) return -1
          if (aLabel > bLabel) return 1
          var aId = String(a.itemId || "")
          var bId = String(b.itemId || "")
          if (aId < bId) return -1
          if (aId > bId) return 1
          return 0
        })
      }
    }

    for (var k = 0; k < rows.length; k++) displayModel.append(rows[k])
    layoutSerial += 1
    root.updateTopRow()

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  // Contain alone parks the cursor row flush with the viewport edge, hiding
  // the neighbor entirely and losing the fold affordance. Keep the next
  // hidden row peeking past the cursor in the direction of travel.
  function revealCursor() {
    if (displayModel.count === 0) return
    if (root.isAppsGrid) {
      appGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
      return
    }
    if (root.selectedIndex === 0) { resultList.positionViewAtBeginning(); return }
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)

    var item = resultList.itemAtIndex(root.selectedIndex)
    if (!item) return

    var reach = root.rowPeek + root.rowSpacing
    if (root.selectedIndex < displayModel.count - 1) {
      var maxY = Math.max(resultList.originY, resultList.originY + resultList.contentHeight - resultList.height)
      var overhang = item.y + item.height + reach - (resultList.contentY + resultList.height)
      if (overhang > 0) resultList.contentY = Math.min(resultList.contentY + overhang, maxY)
    }
    if (root.selectedIndex > 0) {
      var underhang = resultList.contentY - (item.y - reach)
      if (underhang > 0) resultList.contentY = Math.max(resultList.contentY - underhang, resultList.originY)
    }
  }

  function select(delta) {
    if (displayModel.count === 0) return

    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      // Stops at either end, no cycling (spec §9).
      selectedIndex = Math.max(0, Math.min(displayModel.count - 1, selectedIndex + delta))
    }
    revealCursor()
  }

  function setFilter(nextFilter) {
    root.querySelected = false
    root.caretOn = true
    caretTimer.restart()
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = root.mode !== "input"
    root.disarmPointer()
    if (root.fileSearchActive) root.requestFileScan()
    else {
      // Leaving file mode drops its candidates: they would otherwise be
      // ranked against the next file query before its own scan lands.
      if (root.fileRows.length > 0) root.fileRows = []
      if (!root.dmenuActive && root.filterText.trim()) root.loadProvidersForSearch()
    }
    root.scheduleRebuild()
  }

  // The filter is a plain string driven by keyCatcher, not a TextInput, so Qt
  // gives us no paste of its own — Ctrl+V has to fetch the clipboard itself.
  // wl-paste asks the compositor and is always current; Qt's own copy only
  // sees the selection while the surface holds keyboard focus and otherwise
  // hands back an empty (or stale) string, so it is the fallback, not the
  // source.
  function pasteFromClipboard() {
    if (clipboardPasteProc.running) return
    clipboardPasteProc.running = true
  }

  // Pasting appends at the caret, which always sits at the end of the filter.
  // Newlines and tabs would read as blanks in a single-line field, and a
  // leading blank switches the menu into file search, so collapse and trim.
  function appendPastedText(text) {
    if (!text) return
    var flat = text.replace(/[\r\n\t\f\v]+/g, " ").trim()
    if (!flat) return
    if (flat.length > root.maxPasteLength) flat = flat.slice(0, root.maxPasteLength)
    root.setFilter(root.filterText + flat)
  }

  Process {
    id: clipboardPasteProc
    property bool delivered: false
    command: ["wl-paste", "--no-newline", "--type", "text/plain"]
    onStarted: clipboardPasteProc.delivered = false
    stdout: StdioCollector {
      onStreamFinished: {
        clipboardPasteProc.delivered = true
        root.appendPastedText(clipboardPasteProc.stdout.text)
      }
    }
    onExited: function(exitCode) {
      // wl-paste missing, or an image-only / empty clipboard: try Qt's copy
      // rather than swallow the keystroke.
      if (exitCode !== 0 && !clipboardPasteProc.delivered)
        root.appendPastedText(Quickshell.clipboardText)
    }
  }

  function setActiveMenu(id, pushHistory, fromPointer) {
    root.querySelected = false
    root.category = ""
    if (!root.item(id)) id = "root"
    if (pushHistory && id !== root.activeMenu) root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = id
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    if (fromPointer) pointerGate.allowInitialSample()
    else root.disarmPointer()
    root.rebuildDisplay()
    root.invalidateVolatileProvider(id)
    root.loadProviderForMenu(id)
  }

  function goBack() {
    if (root.activeMenu === "root") return false

    if (root.navStack.length > 0) {
      var previous = root.navStack[root.navStack.length - 1]
      root.navStack = root.navStack.slice(0, root.navStack.length - 1)
      root.setActiveMenu(previous, false)
      return true
    }

    var active = root.item(root.activeMenu)
    root.setActiveMenu((active && active.parent) ? active.parent : "root", false)
    return true
  }

  function activateIndex(index, fromPointer, reveal) {
    if (root.deleteConfirmOpen) return
    if (!fromPointer) root.flushRebuild()
    if (root.dmenuActive) {
      if (root.mode === "input") {
        root.applyDmenuSelection(root.filterText)
        return
      }
      if (index < 0 || index >= displayModel.count) return
      var picked = displayModel.get(index)
      root.applyDmenuSelection(picked.detail ? picked.label + "\t" + picked.detail : picked.label)
      return
    }

    if (index < 0 || index >= displayModel.count) return

    var row = displayModel.get(index)
    if (row.kind === "calc") {
      var result = String(row.label || "").replace(/^=\s*/, "")
      applySerial = requestSerial
      opened = false
      filterText = ""
      if (result) root.copyToClipboard(result)
    } else if (row.kind === "menu" || row.kind === "link") {
      root.setActiveMenu(row.target || row.itemId, true, fromPointer)
    } else if (row.kind === "file") {
      var path = row.target
      applySerial = requestSerial
      opened = false
      filterText = ""
      // ⌃↩ shows the item in its folder (spec §9 „Im Finder zeigen“).
      root.openPath(reveal ? (root.dirNameOf(path) || "/") : path)
    } else if (row.kind === "clip") {
      var clipTarget = row.target
      var clipMime = row.appId
      applySerial = requestSerial
      opened = false
      filterText = ""
      if (clipMime) root.copyImageToClipboard(clipTarget, clipMime)
      else root.copyToClipboard(clipTarget)
    } else if (row.kind === "app") {
      var appId = row.appId
      var label = row.label
      applySerial = requestSerial
      opened = false
      filterText = ""
      if (root.appLibrary) root.appLibrary.launch(appId, label)
      else root.fallbackLaunch(appId)
    } else {
      root.applySelected(row.itemId, row.action)
    }
  }

  function requestDeleteSelected() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.kind !== "app") return
    root.deleteTarget = { appId: row.appId, label: row.label }
    deleteConfirm.selectedIndex = 1
    root.deleteConfirmOpen = true
  }

  function cancelDelete() {
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    deleteConfirm.selectedIndex = 1
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmDelete() {
    var target = root.deleteTarget
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    if (!target) return
    root.cancel()
    if (root.appLibrary) root.appLibrary.remove(target.appId, target.label)
    else root.fallbackRemove(target.appId, target.label)
  }

  function applyDmenuSelection(value) {
    applySerial = requestSerial
    opened = false
    filterText = ""
    root.finishRequest(value)
  }

  function applySelected(id, action) {
    if (!id) { cancel(); return }

    applySerial = requestSerial
    opened = false
    filterText = ""
    root.runAction(action)
  }

  function cancel() {
    if (root.dmenuActive) root.finishRequest(null)
    opened = false
    filterText = ""
  }

  function openExistingMenu(initialMenu) {
    requestSerial += 1
    mode = "menu"
    requestActive = false
    selectionFile = ""
    doneFile = ""
    activeMenu = root.item(initialMenu) ? initialMenu : "root"
    navStack = []
    category = ""
    // The last query comes back fully selected, so typing replaces it (spec §8).
    filterText = activeMenu === "root" ? lastQuery : ""
    querySelected = filterText.length > 0
    selectedIndex = 0
    cursorActive = true
    root.disarmPointer()
    opened = true
    rebuildDisplay()
    if (filterText.trim()) loadProvidersForSearch()
    invalidateVolatileProvider(activeMenu)
    loadProviderForMenu(activeMenu)
    // Guards and the icon rescan both fork (the guard batch is one `bash -lc`
    // that runs ~150 `when:` commands). Starting them here put that fork into
    // the first frames of the open animation; they answer asynchronously
    // anyway, so they wait until the card is settled.
    settleWork.restart()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Timer {
    id: settleWork
    interval: Motion.settleDelay
    onTriggered: {
      if (!root.opened) return
      root.evaluateGuards()
      // Nothing is listed until the first keystroke, so the app rows are built
      // now rather than on that keystroke. This one is native (no fork), so it
      // does not queue behind the guard batch.
      root.loadProviderForMenu("apps")
      // The shell may start before first-install packages have finished placing
      // their icons. Refresh here even when the desktop entry list did not change.
      if (root.appLibrary) root.appLibrary.refreshIcons()
    }
  }

  function openDmenu(payload) {
    requestSerial += 1
    mode = payload.mode === "input" ? "input" : "select"
    dmenuPrompt = String(payload.prompt || (mode === "input" ? "Input" : "Select"))
    dmenuOptions = Array.isArray(payload.options) ? payload.options : []
    selectionFile = String(payload.selectionFile || "")
    doneFile = String(payload.doneFile || "")
    requestActive = !!doneFile
    dmenuWidth = Math.max(1, Number(payload.width || 300))
    dmenuMaxHeight = Math.max(0, Number(payload.maxHeight || 0))
    activeMenu = "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = mode !== "input"
    root.disarmPointer()
    opened = true
    rebuildDisplay()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  ListModel { id: displayModel }

  // ----------------------------------------------------------- route surface
  //
  // The menu is opened through the standard plugin lifecycle:
  // `omarchy-shell shell summon omarchy.menu '{"menu":"system"}'`.
  // Callers may pass a real id (`system`, `setup.power`) or an alias declared
  // in JSONC (`power`, `reminder-set`). Unknown strings fall through to the
  // id-as-route behavior so misspellings still attempt to open the literal id.
  function resolveRoute(input) {
    return MenuModel.resolveRoute(root.items, root.itemOrder, input)
  }

  function openRoute(initialMenu) {
    var id = root.resolveRoute(initialMenu)
    var entry = root.items[id]
    // If the resolved id is an action (i.e. the user invoked an alias for
    // a leaf, e.g. `omarchy menu summon screenrecord-stop`), run it directly
    // instead of opening an action with no children.
    if (entry && entry.kind === "action" && entry.action) {
      root.cancel()
      root.runAction(entry.action)
      return "ok"
    }
    // If it's a link (a redirect to another menu), follow the link.
    if (entry && entry.kind === "link" && entry.target) id = entry.target
    root.pendingInitialMenu = id
    root.openExistingMenu(id)
    return "ok"
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  Process {
    id: providerProc
    property string menuId: ""
    property string providerKey: ""
    property string collected: ""
    property int revision: 0
    stdout: SplitParser {
      onRead: function(data) { providerProc.collected += data + "\n" }
    }
    onExited: {
      if (providerProc.revision === root.providerRevision) {
        root.mergeProviderRows(providerProc.collected, providerProc.menuId, providerProc.providerKey)
        if (root.filterText.trim()) root.loadProvidersForSearch()
      }
      root.startNextProvider()
    }
  }

  Process {
    id: resultProc
    onExited: {
      if (root.applySerial === root.requestSerial)
        root.opened = false
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.providersLoaded["apps"]) root.mergeAppRows()
    }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      if (root.opened && !root.appLibrary) {
        root.refreshFallbackHides()
        if (root.providersLoaded["apps"]) root.mergeAppRows()
      }
    }
  }

  onAppLibraryChanged: {
    if (root.providersLoaded["apps"]) root.mergeAppRows()
  }

  // The JSONC sources are watched so live edits to the default file (or the
  // user extension at ~/.config/omarchy/extensions/omarchy-menu.jsonc) take
  // effect without restarting the shell.
  FileView {
    id: defaultMenuFile
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.defaultMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.userMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onLoadFailed: { root.userMenuItems = []; root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  // ---------------------------------------------------------------- guards
  //
  // `when:` (visibility) and `checked:` (✓ marker) are bash expressions the
  // shell wasn't allowed to evaluate before the perf rewrite. Now the shell
  // batches them into one bash subprocess per (re)load so the open path
  // never has to wait on them.

  property var whenResults: ({})       // id → true|false (allow visibility)
  property var checkedResults: ({})    // id → true|false (show ✓)
  property bool guardsPending: false

  function evaluateGuards() {
    // Process ignores a command change while it is running, and `collected`
    // belongs to the run in flight, so a second evaluation cannot overwrite
    // the first: it would throw away the lines already read and never start.
    // The surviving tail then lands as the whole answer, and every id lost
    // with it goes back to showing, since a `when:` only hides on an explicit
    // false. Wait for the run in flight and evaluate once it lands instead.
    if (guardProc.running) {
      root.guardsPending = true
      return
    }
    root.guardsPending = false

    var script = MenuModel.guardScript(root.items)
    if (!script) {
      root.whenResults = ({})
      root.checkedResults = ({})
      return
    }
    guardProc.collected = ""
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { guardProc.collected += data + "\n" }
    }
    onExited: function(exitCode, exitStatus) {
      // A batch that was killed rather than finished has only told us about
      // the rows it reached, and a row whose `when:` went unanswered shows.
      // Keep the last complete set rather than let a half-read one through.
      // A signal leaves the exit code at 0, so the status is what tells us.
      if (exitCode !== 0 || exitStatus !== 0) {
        if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
        return
      }

      var nextWhen = ({})
      var nextChecked = ({})
      var lines = guardProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        var colon = line.lastIndexOf(":")
        if (colon < 0) continue
        var value = line.substring(colon + 1) === "1"
        var rest = line.substring(0, colon)
        var tagAt = rest.lastIndexOf(":")
        if (tagAt < 0) continue
        var id = rest.substring(0, tagAt)
        var tag = rest.substring(tagAt + 1)
        if (tag === "w") nextWhen[id] = value
        else if (tag === "c") nextChecked[id] = value
      }
      root.whenResults = nextWhen
      root.checkedResults = nextChecked
      if (root.opened) root.scheduleRebuild()
      // Run the evaluation that had to stand aside. Deferred by a turn so the
      // process is settled before its command is set again.
      if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
    }
  }
  PanelWindow {
    id: panel
    // The layer surface is never torn down, only resized: one pixel in the
    // top-left corner while closed, full screen while Spotlight is on screen.
    // Creating it from scratch cost ~60 ms of every open -- ten times the QML
    // work behind it -- and that was the whole of the felt delay. Leaving it
    // full screen instead would swallow Hyprland's focus grab and break
    // click-outside-to-close for every other popup.
    //
    // Closed it takes neither keyboard nor pointer input, so the app just
    // launched has focus and accepts clicks in the same frame; the fade-out
    // runs on a click-through surface.
    readonly property bool showing: root.opened || spot.opacity > 0.001
    visible: root.rowsLoaded
    anchors { top: true; left: true; bottom: panel.showing; right: panel.showing }
    implicitWidth: 1
    implicitHeight: 1
    color: "transparent"
    WlrLayershell.namespace: "omarchy-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: root.opened ? null : closingMask
    Region { id: closingMask }

    // The field's top edge sits at 23 % of the screen and never moves; the
    // results panel grows downward from under it (spec §2).
    readonly property int fieldTop: Math.max(Style.gapsOut, Math.round(height * root.sp.topFraction))

    // The query as it looked while open, kept because closing clears
    // filterText and the search line must not blank out during the fade.
    property string shownFilter: ""
    Binding {
      target: panel
      property: "shownFilter"
      value: root.filterText
      when: root.opened
      restoreMode: Binding.RestoreNone
    }

    // No scrim (spec §2): the desktop stays as it is, a click on it closes.
    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    // ---------------------------------------------------------------- field
    //
    // Open: fade + a small scale from 0.98 (`fast`, easeOut); close: fade only,
    // faster (spec §10). Reduce Motion keeps the fade alone.
    Item {
      id: spot
      x: Math.round((panel.width - root.cardWidth) / 2)
      y: panel.fieldTop
      width: root.cardWidth
      height: root.fieldHeight
      transformOrigin: Item.Top
      opacity: root.opened ? 1 : 0
      Behavior on opacity {
        NumberAnimation {
          duration: root.opened ? Motion.fast : Motion.exit(Motion.fast)
          easing.type: Easing.BezierSpline
          easing.bezierCurve: root.opened ? Motion.easeOut : Motion.easeExit
        }
      }
      NumberAnimation {
        id: enterScale
        target: spot
        property: "scale"
        from: Motion.launcherFromScale
        to: 1
        duration: Motion.fast
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.easeOut
      }
      Connections {
        target: root
        function onOpenedChanged() {
          if (!root.opened) return
          if (!Motion.reduceMotion && spot.opacity < 0.01) enterScale.restart()
          if (spot.opacity < 0.01) resultsHeight.snap(results.targetHeight)
          Qt.callLater(function() { keyCatcher.forceActiveFocus() })
        }
      }

      // The four category buttons appear while the pointer is over Spotlight
      // (or once a category was chosen by key), sliding in from the field.
      HoverHandler { id: spotHover }
      readonly property bool buttonsShown: root.opened && !root.dmenuActive
        && (spotHover.hovered || root.category !== "" || root.buttonsPinned)

      RectangularShadow {
        anchors.fill: field
        radius: field.radius
        blur: root.shadowBlur
        spread: root.shadowSpread
        offset.y: root.shadowOffset
        color: Qt.rgba(0, 0, 0, root.shadowAlpha * 0.6)
      }
      RectangularShadow {
        anchors.fill: field
        radius: field.radius
        blur: root.pt(root.sp.contactBlur)
        offset.y: root.pt(root.sp.contactOffset)
        color: Qt.rgba(0, 0, 0, root.sp.contactAlpha)
      }

      Rectangle {
        id: field
        anchors.fill: parent
        radius: height / 2
        color: root.glassFill
        border.width: 1
        border.color: root.glassBorder
        Accessible.role: Accessible.EditableText
        Accessible.name: root.searchPlaceholder

        // Glass light edge: a soft sheen from the top (spec §5.1).
        Rectangle {
          anchors.fill: parent
          anchors.margins: 1
          radius: parent.radius
          gradient: Gradient {
            GradientStop { position: 0.0; color: Util.alpha(root.glassHighlight, root.glassHighlight.a * 0.6) }
            GradientStop { position: 0.45; color: Util.alpha(root.glassHighlight, 0) }
          }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Text {
          id: searchGlyph
          textFormat: Text.PlainText
          text: Apple.sf(0x1002AB)   // SF magnifyingglass
          color: root.inkSecondary
          font.family: root.symbolFont
          font.pixelSize: root.fieldIconSize
          anchors.left: parent.left
          anchors.leftMargin: root.fieldInset
          anchors.verticalCenter: parent.verticalCenter
        }

        // Category chip (spec §5.2): a capsule with the category's name, in
        // front of the query; ⌫ on an empty field or a click removes it.
        Rectangle {
          id: chip
          readonly property bool shown: root.category !== ""
          anchors.left: searchGlyph.right
          anchors.leftMargin: root.fieldGap
          anchors.verticalCenter: parent.verticalCenter
          height: root.chipHeight
          width: shown ? chipLabel.implicitWidth + root.chipPadX * 2 : 0
          radius: height / 2
          color: root.hoverFill
          opacity: shown ? 1 : 0
          visible: opacity > 0
          clip: true
          Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
          Text {
            id: chipLabel
            anchors.centerIn: parent
            text: root.categoryLabel(root.category)
            color: root.ink
            font.family: root.uiFont
            font.pixelSize: root.chipFontSize
            font.weight: Font.Medium
          }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setCategory("") }
        }

        Item {
          id: queryRow
          height: Math.round(root.fieldFontSize * root.sp.fieldLine)
          anchors.left: chip.shown ? chip.right : searchGlyph.right
          anchors.leftMargin: root.fieldGap
          anchors.right: parent.right
          anchors.rightMargin: root.fieldInset
          anchors.verticalCenter: parent.verticalCenter
          clip: true

          readonly property int caretGap: root.pt(2)
          readonly property string shownQuery: root.fileSearchActive && root.category !== "files"
            ? panel.shownFilter.slice(1) : panel.shownFilter
          readonly property bool hasQuery: shownQuery.length > 0

          // The restored query is drawn selected (spec §8).
          Rectangle {
            visible: root.querySelected && queryRow.hasQuery
            x: queryText.x - root.pt(1)
            width: queryText.width + root.pt(2)
            height: parent.height
            radius: root.pt(3)
            color: Util.alpha(root.selection, 0.35)
          }

          Text {
            id: queryText
            textFormat: Text.PlainText
            visible: queryRow.hasQuery
            text: queryRow.shownQuery
            // Elide from the left so the tail of a long query — the part
            // still being typed — stays next to the caret.
            width: Math.min(implicitWidth, Math.max(0, queryRow.width - caret.width - queryRow.caretGap))
            elide: Text.ElideLeft
            color: root.ink
            font.family: root.uiFont
            font.pixelSize: root.fieldFontSize
            font.weight: Font.Light
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Rectangle {
            id: caret
            width: Math.max(1, root.pt(root.sp.caret))
            height: Math.round(root.fieldFontSize * 1.15)
            radius: width / 2
            color: root.selection
            opacity: root.caretOn && !root.querySelected ? 1 : 0
            x: queryRow.hasQuery ? queryText.width + queryRow.caretGap : 0
            anchors.verticalCenter: parent.verticalCenter
            Behavior on opacity { NumberAnimation { duration: Motion.instant; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
          }

          // Inline completion: the rest of the Top Hit's name plus " — Kind".
          Text {
            id: completionText
            textFormat: Text.PlainText
            visible: queryRow.hasQuery && root.opened && text.length > 0
            text: root.completionRest ? root.completionRest + root.completionSuffix : ""
            color: root.inkTertiary
            font.family: root.uiFont
            font.pixelSize: root.fieldFontSize
            font.weight: Font.Light
            elide: Text.ElideRight
            x: caret.x + caret.width + queryRow.caretGap
            width: Math.max(0, queryRow.width - x)
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            id: placeholderText
            textFormat: Text.PlainText
            visible: !queryRow.hasQuery
            text: root.searchPlaceholder
            width: parent.width - caret.width - queryRow.caretGap
            x: caret.width + queryRow.caretGap
            color: root.inkTertiary
            font.family: root.uiFont
            font.pixelSize: root.fieldFontSize
            font.weight: Font.Light
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Timer {
          id: caretTimer
          interval: 540
          running: panel.showing
          repeat: true
          onTriggered: root.caretOn = !root.caretOn
        }
      }

      // ------------------------------------------------------ category buttons
      Row {
        id: buttons
        anchors.left: field.right
        anchors.leftMargin: root.buttonOffset
        anchors.verticalCenter: field.verticalCenter
        spacing: root.buttonGap
        // Pointer over the buttons counts as "over Spotlight" as well.
        HoverHandler { id: buttonsHover }
        Repeater {
          model: root.categories
          delegate: Item {
            id: catButton
            required property int index
            required property var modelData
            readonly property bool active: root.category === modelData.id
            readonly property bool shown: spot.buttonsShown || buttonsHover.hovered
            width: root.buttonSize
            height: root.buttonSize
            opacity: 0
            visible: opacity > 0
            enabled: shown
            transform: Translate { x: slide.value }
            // In: fade + slide from the field, staggered; out: all together, faster.
            onShownChanged: {
              if (shown) { if (Motion.stagger(index) === 0) catButton.opacity = 1; else inDelay.restart() }
              else { inDelay.stop(); catButton.opacity = 0 }
            }
            Timer { id: inDelay; interval: Motion.stagger(catButton.index); onTriggered: catButton.opacity = 1 }
            Behavior on opacity {
              NumberAnimation {
                duration: catButton.shown ? Motion.fast : Motion.exit(Motion.fast)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: catButton.shown ? Motion.easeOut : Motion.easeExit
              }
            }
            HUi.SpringValue { id: slide; epsilon: 0.1; to: (catButton.shown || Motion.reduceMotion) ? 0 : -root.buttonSlide }

            RectangularShadow {
              anchors.fill: glass
              radius: glass.radius
              blur: root.pt(root.sp.contactBlur)
              offset.y: root.pt(root.sp.contactOffset)
              color: Qt.rgba(0, 0, 0, root.sp.contactAlpha)
            }
            Rectangle {
              id: glass
              anchors.fill: parent
              radius: width / 2
              color: root.glassFill
              border.width: 1
              border.color: root.glassBorder
            }
            HUi.Pressable {
              id: press
              anchors.fill: parent
              radius: width / 2
              tint: root.ink
              selected: catButton.active
              Accessible.role: Accessible.Button
              Accessible.name: catButton.modelData.label + " (Ctrl+" + catButton.modelData.key + ")"
              onClicked: root.setCategory(catButton.modelData.id)
              Text {
                anchors.centerIn: parent
                text: catButton.modelData.glyph
                color: press.contentColor
                font.family: root.symbolFont
                font.pixelSize: root.buttonIconSize
              }
            }
          }
        }
      }

      // --------------------------------------------------------------- results
      //
      // A separate glass panel 8 pt under the field, same width, strongly
      // rounded (spec §5.3). Its height follows the rows with the `smooth`
      // spring inside a clipping container (no per-frame layout animation of
      // the rows themselves); it fades with `fast`.
      Item {
        id: results
        anchors.top: field.bottom
        anchors.topMargin: root.resultsGap
        width: parent.width
        height: resultsHeight.value
        readonly property int targetHeight: root.resultsShown ? root.visibleRowsHeight + root.resultsPadding * 2 : 0
        opacity: root.resultsShown ? 1 : 0
        visible: opacity > 0 && height > 1
        Behavior on opacity {
          NumberAnimation {
            duration: root.resultsShown ? Motion.fast : Motion.exit(Motion.fast)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.resultsShown ? Motion.easeOut : Motion.easeExit
          }
        }
        HUi.SpringValue {
          id: resultsHeight
          epsilon: 0.5
          preset: Motion.smooth
          // Collapsing to nothing happens behind the fade, so it may snap.
          to: results.targetHeight
        }

        RectangularShadow {
          anchors.fill: card
          radius: card.radius
          blur: root.shadowBlur
          spread: root.shadowSpread
          offset.y: root.shadowOffset
          color: Qt.rgba(0, 0, 0, root.shadowAlpha)
        }
        RectangularShadow {
          anchors.fill: card
          radius: card.radius
          blur: root.pt(root.sp.contactBlur)
          offset.y: root.pt(root.sp.contactOffset)
          color: Qt.rgba(0, 0, 0, root.sp.contactAlpha)
        }

        Rectangle {
          id: card
          anchors.fill: parent
          radius: root.resultsRadius
          color: root.glassFill
          border.width: 1
          border.color: root.glassBorder
          clip: true

          MouseArea { anchors.fill: parent; onClicked: {} }

          Item {
            id: resultsViewport
            x: root.resultsPadding
            y: root.resultsPadding
            width: parent.width - root.resultsPadding * 2
            height: root.visibleRowsHeight

            ListView {
              id: resultList
              anchors.fill: parent
              visible: !root.isAppsGrid
              model: displayModel
              clip: true
              spacing: root.rowSpacing
              boundsBehavior: Flickable.DragAndOvershootBounds
              flickDeceleration: Motion.flickDeceleration
              maximumFlickVelocity: Motion.maximumFlickVelocity
              Accessible.role: Accessible.List

              section.property: "section"
              section.criteria: ViewSection.FullString
              section.delegate: Item {
                required property string section
                readonly property bool first: section === root.firstSection
                width: ListView.view.width
                height: section ? root.sectionHeaderHeight(first) : 0
                visible: section !== ""
                Text {
                  textFormat: Text.PlainText
                  x: root.sectionInset
                  y: root.pt(parent.first ? root.sp.sectionTopFirst : root.sp.sectionTop)
                  height: root.sectionLine
                  verticalAlignment: Text.AlignVCenter
                  text: root.sectionLabel(parent.section)
                  color: root.inkSecondary
                  font.family: root.uiFont
                  font.pixelSize: root.sectionFontSize
                  font.weight: Font.DemiBold
                }
              }

              delegate: Rectangle {
                id: row
                required property int index
                required property string itemId
                required property string kind
                required property string icon
                required property string iconFont
                required property string appIcon
                required property string appId
                required property bool isDir
                required property string label
                required property string target
                required property string detail
                required property string path
                required property string action
                required property int childCount
                required property string section

                readonly property bool hasCursor: root.cursorActive && row.index === root.selectedIndex
                readonly property bool isApp: row.kind === "app"
                readonly property bool isTop: row.section === "top"
                readonly property bool isCalc: row.kind === "calc"
                readonly property bool twoLine: isTop || (row.kind === "dmenu" && row.detail.length > 0)
                readonly property bool hasIcon: row.icon.length > 0 || row.isApp
                readonly property int glyphSize: isTop ? root.topIcon : root.rowIcon
                readonly property bool isMenu: row.kind === "menu" || row.kind === "link" || row.isDir
                readonly property color textColor: hasCursor ? root.selectionText : root.ink
                readonly property color metaColor: hasCursor ? Util.alpha(root.selectionText, 0.75) : root.inkSecondary
                readonly property string subtitle: row.detail.length > 0 ? row.detail : root.kindName(row.kind, row.isDir)

                width: ListView.view.width
                height: root.rowHeightFor(row)
                radius: root.rowRadius
                // Selection switches instantly (spec §10: 0 ms), like NSMenu.
                color: hasCursor ? root.selection : mouseArea.containsMouse ? root.hoverFill : Util.alpha(root.hoverFill, 0)
                Accessible.role: Accessible.ListItem
                Accessible.name: row.label

                Text {
                  id: iconText
                  textFormat: Text.PlainText
                  visible: row.hasIcon && !row.isApp
                  text: row.icon
                  color: row.textColor
                  font.family: row.iconFont.length > 0 ? row.iconFont : root.fontFamily
                  font.pixelSize: Math.round(row.glyphSize * 0.78)
                  width: row.glyphSize
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  anchors.left: parent.left
                  anchors.leftMargin: root.rowInset
                  anchors.verticalCenter: parent.verticalCenter
                }

                Image {
                  id: appIconImage
                  visible: row.isApp
                  width: row.glyphSize
                  height: row.glyphSize
                  fillMode: Image.PreserveAspectFit
                  // Decode at physical pixels — a logical-size decode leaves
                  // PNG icons upscaled and blurry on HiDPI displays.
                  sourceSize.width: width * Screen.devicePixelRatio
                  sourceSize.height: height * Screen.devicePixelRatio
                  source: row.isApp ? (root.appLibrary ? root.appLibrary.iconSource(row.appIcon) : root.fallbackIcon(row.appIcon)) : ""
                  asynchronous: true
                  anchors.left: parent.left
                  anchors.leftMargin: root.rowInset
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  id: contentColumn
                  anchors.left: parent.left
                  anchors.leftMargin: root.rowInset + (row.hasIcon ? row.glyphSize + (row.isTop ? root.topGap : root.rowGap) : 0)
                  anchors.right: trail.left
                  anchors.rightMargin: root.pt(6)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: root.pt(1)

                  Text {
                    id: labelText
                    textFormat: Text.PlainText
                    width: parent.width
                    text: row.label
                    color: row.textColor
                    font.family: root.uiFont
                    font.pixelSize: row.isCalc ? root.calcFontSize : row.isTop ? root.topFontSize : root.rowFontSize
                    font.weight: row.isTop ? Font.Medium : Font.Normal
                    elide: Text.ElideRight
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    visible: row.twoLine && text.length > 0
                    text: row.subtitle
                    color: row.metaColor
                    font.family: root.uiFont
                    font.pixelSize: root.metaFontSize
                    elide: Text.ElideRight
                  }
                }

                Row {
                  id: trail
                  anchors.right: parent.right
                  anchors.rightMargin: root.rowInset
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: root.pt(8)

                  // Single-line rows carry their path or kind on the right.
                  Text {
                    textFormat: Text.PlainText
                    visible: !row.twoLine && text.length > 0
                    text: row.detail.length > 0 ? row.detail : (row.kind === "app" || row.kind === "file" ? root.kindName(row.kind, row.isDir) : "")
                    color: row.metaColor
                    font.family: root.uiFont
                    font.pixelSize: root.metaFontSize
                    elide: Text.ElideMiddle
                    width: Math.min(implicitWidth, Math.round(row.width * 0.4))
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  // The selected row hints at Return; menus show their chevron.
                  Text {
                    textFormat: Text.PlainText
                    visible: text.length > 0
                    text: row.isMenu ? "›" : row.hasCursor ? "↩" : ""
                    color: Util.alpha(row.textColor, root.metaAlpha)
                    font.family: root.uiFont
                    font.pixelSize: row.isMenu ? root.rowFontSize : root.metaFontSize
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  id: mouseArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.selectFromPointer(row.index, row, {
                    x: mouseArea.mouseX,
                    y: mouseArea.mouseY
                  })
                  onPositionChanged: function(mouse) {
                    root.selectFromPointer(row.index, row, mouse)
                  }
                  onClicked: {
                    root.cursorActive = true
                    root.selectedIndex = row.index
                    root.activateIndex(row.index, true)
                  }
                }
              }
            }

            GridView {
              id: appGrid
              anchors.fill: parent
              visible: root.isAppsGrid
              model: displayModel
              clip: true
              cellWidth: Math.floor(appGrid.width / Math.max(1, root.gridColumns))
              cellHeight: root.gridCellHeight
              boundsBehavior: Flickable.DragAndOvershootBounds
              flickDeceleration: Motion.flickDeceleration
              maximumFlickVelocity: Motion.maximumFlickVelocity

              delegate: Item {
                id: cell
                required property int index
                required property string kind
                required property string label
                required property string appIcon
                required property string appId
                width: GridView.view.cellWidth
                height: root.gridCellHeight

                readonly property bool hasCursor: root.cursorActive && cell.index === root.selectedIndex
                readonly property bool isApp: cell.kind === "app"

                Rectangle {
                  anchors.fill: parent
                  anchors.margins: root.pt(3)
                  radius: root.rowRadius
                  color: cell.hasCursor ? root.selection : cellMouse.containsMouse ? root.hoverFill : Util.alpha(root.hoverFill, 0)

                  Column {
                    anchors.top: parent.top
                    anchors.topMargin: root.gridCellPadTop
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - root.pt(12)
                    spacing: root.gridIconGap

                    Image {
                      anchors.horizontalCenter: parent.horizontalCenter
                      width: root.gridIconSize
                      height: root.gridIconSize
                      visible: cell.isApp
                      fillMode: Image.PreserveAspectFit
                      sourceSize.width: width * Screen.devicePixelRatio
                      sourceSize.height: height * Screen.devicePixelRatio
                      source: cell.isApp ? (root.appLibrary ? root.appLibrary.iconSource(cell.appIcon) : root.fallbackIcon(cell.appIcon)) : ""
                      asynchronous: true
                    }

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      height: root.gridLabelHeight
                      text: cell.label
                      color: cell.hasCursor ? root.selectionText : root.ink
                      font.family: root.uiFont
                      font.pixelSize: root.metaFontSize
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignTop
                      elide: Text.ElideRight
                      maximumLineCount: 2
                      wrapMode: Text.WordWrap
                    }
                  }
                }

                MouseArea {
                  id: cellMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.selectFromPointer(cell.index, cell, {
                    x: cellMouse.mouseX,
                    y: cellMouse.mouseY
                  })
                  onPositionChanged: function(mouse) {
                    root.selectFromPointer(cell.index, cell, mouse)
                  }
                  onClicked: {
                    root.cursorActive = true
                    root.selectedIndex = cell.index
                    root.activateIndex(cell.index, true)
                  }
                }
              }
            }

            // Scroll scrims: the clipped row already marks the fold at rest;
            // these keep both edges honest once the list has been scrolled.
            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: Math.min(root.pt(20), parent.height / 2)
              visible: opacity > 0
              opacity: resultList.contentHeight > resultList.height
                ? Math.max(0, Math.min(1, (resultList.contentY - resultList.originY) / height))
                : 0
              gradient: Gradient {
                GradientStop { position: 0; color: root.glassFill }
                GradientStop { position: 1; color: Util.alpha(root.glassFill, 0) }
              }
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: Math.min(root.pt(20), parent.height / 2)
              visible: opacity > 0
              opacity: resultList.contentHeight > resultList.height
                ? Math.max(0, Math.min(1, (resultList.originY + resultList.contentHeight - resultList.height - resultList.contentY) / height))
                : 0
              gradient: Gradient {
                GradientStop { position: 0; color: Util.alpha(root.glassFill, 0) }
                GradientStop { position: 1; color: root.glassFill }
              }
            }

            Text {
              anchors.centerIn: parent
              visible: displayModel.count === 0 && root.mode !== "input" && !root.blankRoot
              textFormat: Text.PlainText
              text: root.emptyStateText
              color: root.inkSecondary
              font.family: root.uiFont
              font.pixelSize: root.rowFontSize
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              width: parent.width - root.rowInset * 2
            }
          }
        }
      }
    }

    // ------------------------------------------------------------------ keys
    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        // Only typing may leave a rebuild pending; every other key acts on
        // the rows, so bring them up to date first.
        var printable = event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
          && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)
        var typing = Util.editsFilter(event, root.filterText) || printable
        if (!typing) root.flushRebuild()

        if (root.deleteConfirmOpen) {
          if (deleteConfirm.handleKey(event)) event.accepted = true
          return
        }

        var ctrl = event.modifiers === Qt.ControlModifier
        var arrowLeft = event.key === Qt.Key_Left || (event.key === Qt.Key_H && ctrl)
        var arrowRight = event.key === Qt.Key_Right || (event.key === Qt.Key_L && ctrl)

        if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_4 && !root.dmenuActive) {
          // ⌃1–⌃4 stand in for ⌘1–⌘4 (spec §9): Super+digits are workspaces.
          root.setCategory(root.categories[event.key - Qt.Key_1].id)
          event.accepted = true
        } else if (event.key === Qt.Key_Delete) {
          root.requestDeleteSelected()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          if (root.filterText) root.setFilter("")
          else root.cancel()
          event.accepted = true
        } else if (ctrl && event.key === Qt.Key_B && !root.dmenuActive) {
          root.webSearch(root.completionQuery)
          event.accepted = true
        } else if (ctrl && event.key === Qt.Key_C) {
          root.copySelected()
          event.accepted = true
        } else if ((event.key === Qt.Key_J || event.key === Qt.Key_N) && ctrl) {
          root.select(root.isAppsGrid ? root.gridColumns : 1)
          event.accepted = true
        } else if ((event.key === Qt.Key_K || event.key === Qt.Key_P) && ctrl) {
          root.select(root.isAppsGrid ? -root.gridColumns : -1)
          event.accepted = true
        } else if (event.key === Qt.Key_Tab) {
          // Tab takes the inline completion; in file mode it descends instead.
          if (root.fileSearchActive) root.completeFileSelection()
          else root.acceptCompletion()
          event.accepted = true
        } else if ((event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier) && !(event.modifiers & (Qt.AltModifier | Qt.MetaModifier)))
                   || (event.key === Qt.Key_Insert && event.modifiers === Qt.ShiftModifier)) {
          if (root.querySelected) root.setFilter("")
          root.pasteFromClipboard()
          event.accepted = true
        } else if (event.key === Qt.Key_Home) {
          if (displayModel.count > 0) {
            root.disarmPointer()
            root.cursorActive = true
            root.selectedIndex = 0
            root.revealCursor()
          }
          event.accepted = true
        } else if (event.key === Qt.Key_End) {
          if (displayModel.count > 0) {
            root.disarmPointer()
            root.cursorActive = true
            root.selectedIndex = displayModel.count - 1
            root.revealCursor()
          }
          event.accepted = true
        } else if ((arrowLeft || arrowRight) && root.querySelected && root.filterText.length > 0) {
          root.querySelected = false
          event.accepted = true
        } else if (Util.editsFilter(event, root.filterText)) {
          // Any edit of a selected query replaces the whole of it.
          root.setFilter(root.querySelected ? "" : Util.editedFilter(event, root.filterText))
          event.accepted = true
        } else if ((event.key === Qt.Key_Backspace || (arrowLeft && !root.isAppsGrid)) && !root.filterText) {
          if (root.category !== "") root.setCategory("")
          else root.goBack()
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          root.select(root.isAppsGrid ? -root.gridColumns : -1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          root.select(root.isAppsGrid ? root.gridColumns : 1)
          event.accepted = true
        } else if (arrowLeft && root.isAppsGrid) {
          root.select(-1)
          event.accepted = true
        } else if (arrowRight && root.isAppsGrid) {
          root.select(1)
          event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
          root.select(root.isAppsGrid ? -root.gridColumns * 3 : -6)
          event.accepted = true
        } else if (event.key === Qt.Key_PageDown) {
          root.select(root.isAppsGrid ? root.gridColumns * 3 : 6)
          event.accepted = true
        } else if (arrowRight && !root.isAppsGrid && root.acceptCompletion()) {
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || (arrowRight && !root.isAppsGrid)) {
          var reveal = (event.modifiers & Qt.ControlModifier) !== 0
          if (root.dmenuActive) {
            if (root.mode === "input") root.applyDmenuSelection(root.filterText)
            else if (displayModel.count > 0) root.activateIndex(root.cursorActive ? root.selectedIndex : 0)
          } else if (root.cursorActive) root.activateIndex(root.selectedIndex, false, reveal)
          else if (displayModel.count > 0) root.cursorActive = true
          event.accepted = true
        } else if (printable) {
          root.setFilter((root.querySelected ? "" : root.filterText) + event.text)
          event.accepted = true
        }
      }

      ConfirmDialog {
        id: deleteConfirm

        anchors.fill: parent
        opened: root.deleteConfirmOpen
        z: 10
        message: "Do you want to uninstall " + ((root.deleteTarget && root.deleteTarget.label) || "") + "?"
        confirmText: "Uninstall"
        background: root.background
        foreground: root.foreground
        scrim: root.scrim
        selectedBackground: root.selectedBackground
        selectedText: root.selectedText
        fontFamily: root.uiFont
        cornerRadius: Style.space(Motion.radiusPopover)
        onCanceled: root.cancelDelete()
        onConfirmed: root.confirmDelete()
      }
    }
  }
}
