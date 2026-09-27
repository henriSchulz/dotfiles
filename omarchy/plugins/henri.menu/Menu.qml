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
  onOpenedChanged: if (!opened) {
    // Nothing carries over: every open starts blank (Henri's call, replacing
    // spec §8's restored query).
    lastQuery = ""
    deleteConfirmOpen = false
    confirmSpec = null
    fileScanProc.running = false
    fileRows = []
    category = ""
    querySelected = false
    buttonsPinned = false
    buttonFocus = -1
    closePages()
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
  // The selection is a light tint with the text left as it is (measured on
  // Apple's screenshot), not an accent bar; the accent only marks the caret.
  readonly property color selection: pal.selectionFill
  readonly property color selectionBorder: pal.selectionBorder
  readonly property color selectionText: root.ink
  readonly property color capsuleFill: pal.capsule
  readonly property color capsuleSelectedFill: pal.capsuleSelected
  readonly property color shortcutFill: pal.shortcut
  readonly property color hoverFill: pal.hover
  readonly property real shadowAlpha: pal.shadowAlpha

  // The ConfirmDialog (uninstall) still takes the old colour roles.
  readonly property color background: pal.opaqueFill
  readonly property color foreground: root.ink
  readonly property color scrim: Util.alpha(pal.opaqueFill, 0.5)
  readonly property color selectedBackground: Color.accent
  readonly property color selectedText: Motion.onColor(Color.accent)

  readonly property int compactWidth: pt(sp.compactWidth)
  readonly property int compactHeight: pt(sp.compactHeight)
  readonly property int spotWidth: pt(sp.width)
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
  readonly property int panelRadius: pt(sp.radius)
  readonly property int fieldRow: pt(sp.fieldRow)
  readonly property int panelInset: pt(sp.panelInset)
  readonly property int capsuleTop: pt(sp.capsuleTop)
  readonly property int capsuleHeight: pt(sp.capsuleHeight)
  readonly property int capsuleGap: pt(sp.capsuleGap)
  readonly property int capsuleFontSize: pt(sp.capsuleFont)
  // Filter capsules only outside a dmenu prompt; rows start right under the field then.
  readonly property bool showCapsules: !root.dmenuActive && !root.pageOpen
  readonly property int rowsTop: root.showCapsules ? pt(sp.rowsTop) : root.fieldRow + pt(sp.rowInset)
  readonly property int rowInset: pt(sp.rowInset)
  readonly property int rowHeight: pt(sp.rowHeight)
  readonly property int rowIcon: pt(sp.rowIcon)
  readonly property int rowIconInset: pt(sp.rowIconInset)
  readonly property int rowTextX: pt(sp.rowTextX)
  readonly property int rowRadius: pt(sp.rowRadius)
  readonly property int titleFontSize: pt(sp.titleFont)
  readonly property int subtitleFontSize: pt(sp.subtitleFont)
  readonly property int metaFontSize: pt(sp.metaFont)
  readonly property int metaInset: pt(sp.metaInset)
  readonly property int calcFontSize: pt(sp.calcFont)
  readonly property int shortcutW: pt(sp.shortcutW)
  readonly property int shortcutH: pt(sp.shortcutH)
  readonly property int shortcutRadius: pt(sp.shortcutRadius)
  readonly property int shortcutFontSize: pt(sp.shortcutFont)
  readonly property int bottomPad: pt(sp.bottomPad)
  readonly property int resultsMaxHeight: pt(sp.resultsMaxHeight)
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
  readonly property int gridLabelHeight: Math.round(subtitleFontSize * 2.7)
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
    { id: "files", label: "Files", glyph: Apple.sf(0x100215), key: "2" },           // folder
    { id: "actions", label: "Actions", glyph: Apple.sf(0x10041E), key: "3" },       // square.stack.3d.up
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
  readonly property bool resultsShown: root.opened && (root.pageOpen || (!root.blankRoot && !(root.dmenuActive && root.mode === "input")))

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
  // The compact capsule widens into the results panel; a dmenu caller may
  // ask for more width than Spotlight's, never less.
  property int cardWidth: Math.min(root.dmenuActive
    ? Math.max(root.pt(root.dmenuWidth), root.spotWidth)
    : (root.blankRoot ? root.compactWidth : root.spotWidth), panel.width - Style.gapsOut * 2)
  property int visibleRowsHeight: root.pageOpen ? pageRowListHeight(layoutSerial, pageModel.count, pageFilter)
    : root.blankRoot ? 0 : (root.dmenuActive ? dmenuRowListHeight(layoutSerial, displayModel.count, filterText) : (root.isAppsGrid ? root.gridRowsHeight() : rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)))
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

  // Every row is the measured 49-pt two-line row; section headers are not
  // drawn (Apple's list runs continuously), the grouping only orders rows.
  function rowHeightFor(row) { return root.rowHeight }
  function sectionHeaderHeight(first) { return 0 }

  // Height the results panel can devote to rows: below the field, above the
  // bottom gap, and never more than the spec's 480 pt panel.
  function availableRowsHeight() {
    var top = panel.fieldTop + root.rowsTop + root.bottomPad
    var available = panel.height - top - Style.gapsOut
    return Math.min(available, root.resultsMaxHeight - root.rowsTop - root.bottomPad)
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

  // The action page: header, then grouped 36-pt rows.
  readonly property int actionHeader: pt(sp.actionHeader)
  readonly property int actionRowHeight: pt(sp.actionRowHeight)
  readonly property int actionFontSize: pt(sp.actionFont)
  readonly property int sectionFontSize: pt(sp.sectionFont)
  readonly property int sectionLine: Math.round(pt(sp.sectionFont) * 1.3)
  function pageSectionHeight(first) {
    return pt(first ? sp.sectionTopFirst : sp.sectionTop) + sectionLine + pt(sp.sectionBottom)
  }
  property string firstPageSection: ""
  function pageRowListHeight(_serial, _count, _filter) {
    var available = availableRowsHeight() - root.actionHeader
    if (pageModel.count === 0) return root.actionHeader + root.emptyStateHeight
    var totals = []
    var heads = []
    var total = 0
    var previous = null
    for (var i = 0; i < pageModel.count; i++) {
      var r = pageModel.get(i)
      var head = (r.section && r.section !== previous) ? root.pageSectionHeight(i === 0) : 0
      total += head + root.actionRowHeight
      previous = r.section
      totals.push(total)
      heads.push(head)
      if (total > available) break
    }
    return root.actionHeader + foldedListHeight(totals, available, heads)
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
            label: String(calcResult),
            target: "",
            detail: "Calculator",
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
    root.buttonFocus = -1
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
    root.closePages()
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

  // Anything destructive asks first through the one ConfirmDialog: the
  // spec names what it asks and what runs on "yes".
  property var confirmSpec: null
  function askConfirm(spec) {
    root.confirmSpec = spec
    deleteConfirm.selectedIndex = 1
    root.deleteConfirmOpen = true
  }
  function requestDeleteSelected() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.kind !== "app") return
    root.requestUninstall(row.appId, row.label)
  }
  function requestUninstall(appId, label) {
    root.askConfirm({
      message: "Do you want to uninstall " + label + "?",
      confirmText: "Uninstall",
      run: function() {
        root.cancel()
        if (root.appLibrary) root.appLibrary.remove(appId, label)
        else root.fallbackRemove(appId, label)
      }
    })
  }

  function cancelDelete() {
    root.deleteConfirmOpen = false
    root.confirmSpec = null
    deleteConfirm.selectedIndex = 1
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmDelete() {
    var spec = root.confirmSpec
    root.deleteConfirmOpen = false
    root.confirmSpec = null
    if (spec && spec.run) spec.run()
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
    // Every open starts blank — no query, no category, no page from last time.
    filterText = ""
    querySelected = false
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

  // ------------------------------------------------------------ item actions
  //
  // → on a result opens a page of actions for that item (Raycast-style): the
  // list slides out to the left, the actions come in from the right (henri-ui
  // drill-in). Typing filters the actions, ↩ runs one, → or Tab descends into
  // a sub-page (Open With…, Copy To…, Move To…, Get Info), ← / Esc / ⌫ on an
  // empty filter go back. Rows carry their `run` in `pages`; the ListModel
  // only holds what is drawn plus the index back into the page.
  // While the field is empty the arrow keys walk the four category buttons
  // (they show as if hovered); ↩ picks the focused one, Esc lets go.
  property int buttonFocus: -1
  function moveButtonFocus(delta) {
    if (!root.blankRoot || root.dmenuActive) return false
    var next = root.buttonFocus < 0 ? (delta > 0 ? 0 : -1) : root.buttonFocus + delta
    if (next >= root.categories.length) next = root.categories.length - 1
    if (next < 0) { root.buttonFocus = -1; root.buttonsPinned = false; return true }
    root.buttonFocus = next
    root.buttonsPinned = true
    return true
  }
  function clearButtonFocus() {
    if (root.buttonFocus < 0) return false
    root.buttonFocus = -1
    root.buttonsPinned = false
    return true
  }
  function activateButtonFocus() {
    if (root.buttonFocus < 0) return false
    var id = root.categories[root.buttonFocus].id
    root.buttonFocus = -1
    root.setCategory(id)
    return true
  }

  property var pages: []
  readonly property bool pageOpen: root.pages.length > 0
  readonly property var page: root.pageOpen ? root.pages[root.pages.length - 1] : null
  property string pageFilter: ""
  property int pageSelected: 0
  ListModel { id: pageModel }
  readonly property string pagePlaceholder: !root.page ? "" :
    root.page.kind === "apps" ? "Search applications"
    : root.page.kind === "folders" ? "Search folders"
    : root.page.kind === "info" ? "Info"
    : "Search actions"

  function rowCopy(row) {
    return {
      itemId: String(row.itemId || ""), kind: String(row.kind || ""), icon: String(row.icon || ""),
      iconFont: String(row.iconFont || ""), appIcon: String(row.appIcon || ""), appId: String(row.appId || ""),
      isDir: !!row.isDir, label: String(row.label || ""), target: String(row.target || ""),
      detail: String(row.detail || ""), action: String(row.action || "")
    }
  }
  function pushPage(p, replacing) {
    // The page being left remembers its selection for the way back; a page
    // replacing its sibling (folder picker browsing) leaves that memory alone.
    if (root.page && !replacing) root.page.selected = root.pageSelected
    root.pages = root.pages.concat([p])
    root.pageFilter = ""
    root.pageSelected = 0
    root.disarmPointer()
    root.rebuildPage()
    if (p.kind === "folders") root.scanPickerDir(p.dir)
    if (p.kind === "info") root.gatherInfo(p)
  }
  function replacePage(p) {
    root.pages = root.pages.slice(0, root.pages.length - 1)
    root.pushPage(p, true)
  }
  function popPage() {
    if (!root.pageOpen) return false
    root.pages = root.pages.slice(0, root.pages.length - 1)
    root.pageFilter = ""
    root.pageSelected = root.page && root.page.selected ? root.page.selected : 0
    root.disarmPointer()
    root.rebuildPage()
    return true
  }
  function closePages() {
    if (!root.pageOpen && root.pageFilter === "") return
    root.pages = []
    root.pageFilter = ""
    root.pageSelected = 0
    pageModel.clear()
    layoutSerial += 1
  }
  function setPageFilter(text) {
    root.pageFilter = text
    root.pageSelected = 0
    root.caretOn = true
    root.disarmPointer()
    root.rebuildPage()
  }
  function rebuildPage() {
    pageModel.clear()
    if (root.page) {
      var q = root.pageFilter.trim().toLowerCase()
      var rows = root.page.rows || []
      for (var i = 0; i < rows.length; i++) {
        var r = rows[i]
        if (q && (r.label + " " + (r.detail || "")).toLowerCase().indexOf(q) < 0) continue
        pageModel.append({
          label: String(r.label || ""), detail: String(r.detail || ""), icon: String(r.icon || ""),
          iconFont: String(r.iconFont || ""), appIcon: String(r.appIcon || ""),
          hasMore: !!r.more, danger: !!r.danger, section: String(r.section || ""), rowIndex: i
        })
      }
    }
    root.firstPageSection = pageModel.count > 0 ? String(pageModel.get(0).section || "") : ""
    layoutSerial += 1
    if (pageModel.count === 0) root.pageSelected = 0
    else if (root.pageSelected >= pageModel.count) root.pageSelected = pageModel.count - 1
    Qt.callLater(function() { if (pageModel.count > 0) pageList.positionViewAtIndex(root.pageSelected, ListView.Contain) })
  }
  function selectPage(delta) {
    if (pageModel.count === 0) return
    root.disarmPointer()
    root.pageSelected = Math.max(0, Math.min(pageModel.count - 1, root.pageSelected + delta))
    pageList.positionViewAtIndex(root.pageSelected, ListView.Contain)
  }
  function pageRowAt(index) {
    if (!root.page || index < 0 || index >= pageModel.count) return null
    return root.page.rows[pageModel.get(index).rowIndex] || null
  }
  // ↩ runs the row (a row that only leads on descends); → and Tab only
  // descend, so a stray → never fires an action.
  function activatePageRow(index, descend) {
    var r = root.pageRowAt(index)
    if (!r) return
    if (r.more && (descend || !r.run)) { r.more(); return }
    if (!descend && r.run) r.run()
  }
  function openActionsForSelected() {
    root.flushRebuild()
    if (root.dmenuActive || !root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return false
    var row = root.rowCopy(displayModel.get(root.selectedIndex))
    var rows = root.actionsFor(row)
    if (rows.length === 0) return false
    root.pushPage({ kind: "actions", title: row.label, target: row, rows: root.grouped(rows),
      headerIcon: row.icon, headerIconFont: row.iconFont, headerAppIcon: row.appIcon,
      headerTitle: row.label, headerSubtitle: row.detail || root.kindName(row.kind, row.isDir) })
    return true
  }

  // Closes Spotlight and runs the deed.
  function finishWith(fn) {
    applySerial = requestSerial
    opened = false
    filterText = ""
    if (fn) fn()
  }
  function isUrl(text) { return /^(https?:\/\/|www\.)\S+$/i.test(String(text || "").trim()) }
  function terminalAt(dir) {
    Util.execArgv(["uwsm-app", "--", "bash", "-c", 'cd "$1" && exec xdg-terminal-exec', "bash", String(dir)])
  }
  function copyFileToClipboard(path) {
    Quickshell.execDetached(["bash", "-c", "printf 'file://%s' \"$1\" | wl-copy --type text/uri-list", "bash", String(path)])
  }
  function openWith(appId, path) {
    var id = String(appId || "")
    if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
    Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", id + ".desktop", String(path)])
  }

  // Glyphs for the action rows (SF Symbols, see memory sf-symbols-codepoints).
  readonly property var glyph: ({
    open: Apple.sf(0x100202),      // square.and.arrow.up
    folder: Apple.sf(0x100215),    // folder
    doc: Apple.sf(0x100237),       // doc
    copy: Apple.sf(0x100241),      // doc.on.doc
    clipboard: Apple.sf(0x100243), // doc.on.clipboard
    trash: Apple.sf(0x100211),     // trash
    info: Apple.sf(0x1002F2),      // list.bullet
    web: Apple.sf(0x1002AB),       // magnifyingglass
    move: Apple.sf(0x100C13),      // arrow.right.circle.fill
    apps: Apple.sf(0x1001F7),      // square.grid.2x2
    remove: Apple.sf(0x100184),    // xmark
    terminal: Apple.sf(0x100194),  // command
    run: Apple.sf(0x1002E5)        // bolt
  })
  function act(label, glyphKey, run, detail, more, section, danger) {
    return { label: label, detail: detail || "", icon: root.glyph[glyphKey] || "", iconFont: Apple.symbolFont,
      run: run || null, more: more || null, section: section || "", danger: !!danger }
  }
  // Groups the rows of an actions page: what the row does decides its section.
  function grouped(rows) {
    var order = ["open", "copy", "move", "more"]
    var out = []
    for (var g = 0; g < order.length; g++)
      for (var i = 0; i < rows.length; i++) if (rows[i].section === order[g]) out.push(rows[i])
    for (var j = 0; j < rows.length; j++) if (order.indexOf(rows[j].section) < 0) out.push(rows[j])
    return out
  }
  function sectionTitle(section) {
    switch (section) { case "open": return "Open"; case "copy": return "Copy"; case "move": return "Move"; case "more": return "More"; default: return "" }
  }
  function webAction(text) {
    var q = String(text || "").trim()
    return root.act("Search the Web", "web", function() { root.webSearch(q) }, "“" + (q.length > 40 ? q.slice(0, 39) + "…" : q) + "”")
  }

  function sec(a, section, danger) { a.section = section; a.danger = !!danger; return a }
  function actionsFor(row) {
    var rows = []
    var path = row.target
    if (row.kind === "file") {
      var pretty = root.prettyPath(path)
      var parent = root.dirNameOf(path) || "/"
      if (row.isDir) {
        rows.push(root.sec(root.act("Browse Folder", "folder", function() { root.closePages(); root.setFilter(" " + pretty + "/") }, "in Spotlight"), "open"))
        rows.push(root.sec(root.act("Open", "open", function() { root.finishWith(function() { root.openPath(path) }) }, "in Files"), "open"))
        rows.push(root.sec(root.act("Open in Terminal", "terminal", function() { root.finishWith(function() { root.terminalAt(path) }) }), "open"))
      } else {
        rows.push(root.sec(root.act("Open", "open", function() { root.finishWith(function() { root.openPath(path) }) }), "open"))
        rows.push(root.sec(root.act("Open With…", "apps", null, "", function() { root.pushPage(root.openWithPage(path)) }), "open"))
      }
      rows.push(root.sec(root.act("Show in Files", "folder", function() { root.finishWith(function() { root.openPath(parent) }) }, root.prettyPath(parent)), "open"))
      rows.push(root.sec(root.act("Get Info", "info", null, "", function() { root.pushPage({ kind: "info", title: "Info", path: path, rows: [],
        headerIcon: root.glyph.info, headerIconFont: Apple.symbolFont, headerAppIcon: "", headerTitle: "Info", headerSubtitle: root.baseNameOf(path) }) }), "more"))
      rows.push(root.sec(root.act("Copy Path", "clipboard", function() { root.finishWith(function() { root.copyToClipboard(path) }) }, pretty), "copy"))
      rows.push(root.sec(root.act(row.isDir ? "Copy Folder" : "Copy File", "copy", function() { root.finishWith(function() { root.copyFileToClipboard(path) }) }, "for pasting in Files"), "copy"))
      rows.push(root.sec(root.act("Copy To…", "copy", null, "", function() { root.pushPage(root.folderPage("Copy To", parent, function(dest) {
        root.finishWith(function() { Quickshell.execDetached(["cp", "-r", "--", path, dest + "/"]) }) })) }), "copy"))
      rows.push(root.sec(root.act("Move To…", "move", null, "", function() { root.pushPage(root.folderPage("Move To", parent, function(dest) {
        root.finishWith(function() { Quickshell.execDetached(["mv", "--", path, dest + "/"]) }) })) }), "move"))
      rows.push(root.sec(root.act("Move to Trash", "trash", function() {
        root.askConfirm({ message: "Move “" + row.label + "” to the trash?", confirmText: "Move to Trash",
          run: function() { root.finishWith(function() { Quickshell.execDetached(["gio", "trash", path]) }) } })
      }), "move", true))
    } else if (row.kind === "app") {
      var appId = row.appId, label = row.label
      rows.push(root.sec(root.act("Open", "open", function() { root.finishWith(function() {
        if (root.appLibrary) root.appLibrary.launch(appId, label); else root.fallbackLaunch(appId) }) }), "open"))
      rows.push(root.sec(root.act("Copy Name", "clipboard", function() { root.finishWith(function() { root.copyToClipboard(label) }) }, label), "copy"))
      rows.push(root.sec(root.act("Copy App ID", "clipboard", function() { root.finishWith(function() { root.copyToClipboard(appId) }) }, appId), "copy"))
      rows.push(root.sec(root.webAction(label), "more"))
      rows.push(root.sec(root.act("Uninstall", "remove", function() { root.requestUninstall(appId, label) }), "more", true))
    } else if (row.kind === "menu" || row.kind === "link") {
      rows.push(root.sec(root.act("Open Menu", "open", function() { root.closePages(); root.setActiveMenu(row.target || row.itemId, true, false) }), "open"))
      rows.push(root.sec(root.act("Copy Name", "clipboard", function() { root.finishWith(function() { root.copyToClipboard(row.label) }) }, row.label), "copy"))
    } else if (row.kind === "action") {
      rows.push(root.sec(root.act("Run", "run", function() { root.finishWith(function() { root.runAction(row.action) }) }), "open"))
      if (row.action) rows.push(root.sec(root.act("Copy Command", "clipboard", function() { root.finishWith(function() { root.copyToClipboard(row.action) }) }, row.action), "copy"))
      rows.push(root.sec(root.act("Copy Name", "clipboard", function() { root.finishWith(function() { root.copyToClipboard(row.label) }) }, row.label), "copy"))
    } else if (row.kind === "calc") {
      var result = String(row.label || "").replace(/^=\s*/, "")
      rows.push(root.sec(root.act("Copy Result", "clipboard", function() { root.finishWith(function() { root.copyToClipboard(result) }) }, result), "copy"))
      rows.push(root.sec(root.act("Copy Expression", "clipboard", function() { root.finishWith(function() { root.copyToClipboard(root.filterText.trim()) }) }, root.filterText.trim()), "copy"))
      rows.push(root.sec(root.webAction(root.filterText.trim()), "more"))
    } else if (row.kind === "clip") {
      if (row.appId) {
        rows.push(root.sec(root.act("Copy Image", "copy", function() { root.finishWith(function() { root.copyImageToClipboard(row.target, row.appId) }) }), "copy"))
        rows.push(root.sec(root.act("Open Image", "open", function() { root.finishWith(function() { root.openPath(row.target) }) }), "open"))
        rows.push(root.sec(root.act("Copy Image Path", "clipboard", function() { root.finishWith(function() { root.copyToClipboard(row.target) }) }, root.prettyPath(row.target)), "copy"))
      } else {
        rows.push(root.sec(root.act("Copy", "copy", function() { root.finishWith(function() { root.copyToClipboard(row.target) }) }), "copy"))
        if (root.isUrl(row.target)) rows.push(root.sec(root.act("Open Link", "open", function() { root.finishWith(function() { root.runAction("omarchy-launch-webapp " + Util.shellQuote(row.target.trim())) }) }), "open"))
        rows.push(root.sec(root.webAction(row.target), "more"))
      }
    }
    return rows
  }

  // Sub-page: every application, ↩ opens the file with it.
  function openWithPage(path) {
    var rows = []
    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || entry.kind !== "app") continue
      rows.push((function(e) {
        return { label: e.label, detail: e.description || "", icon: "", iconFont: "", appIcon: e.appIcon || "",
          run: function() { root.finishWith(function() { root.openWith(e.appId, path) }) } }
      })(entry))
    }
    rows.sort(function(a, b) { return a.label.toLowerCase() < b.label.toLowerCase() ? -1 : 1 })
    return { kind: "apps", title: "Open With", rows: rows, headerIcon: root.glyph.apps, headerIconFont: Apple.symbolFont,
      headerAppIcon: "", headerTitle: "Open With", headerSubtitle: root.baseNameOf(path) }
  }

  // Sub-page: a folder picker. The first row takes the folder being shown,
  // the rest are its sub-folders: ↩ picks one, → or Tab browses into it.
  function folderPage(title, dir, choose) {
    return { kind: "folders", title: title, dir: dir, choose: choose, rows: root.folderRows(title, dir, [], choose),
      headerIcon: root.glyph.folder, headerIconFont: Apple.symbolFont, headerAppIcon: "", headerTitle: title, headerSubtitle: root.prettyPath(dir) }
  }
  function folderRows(title, dir, subdirs, choose) {
    var rows = [root.act("Here: " + root.prettyPath(dir), "folder", function() { choose(dir) }, "this folder")]
    var parent = root.dirNameOf(dir)
    if (parent && parent !== dir) rows.push(root.act("..", "folder", null, root.prettyPath(parent), function() {
      root.replacePage(root.folderPage(title, parent, choose)) }))
    for (var i = 0; i < subdirs.length; i++) {
      rows.push((function(sub) {
        return root.act(root.baseNameOf(sub), "folder", function() { choose(sub) }, "", function() {
          root.replacePage(root.folderPage(title, sub, choose)) })
      })(subdirs[i]))
    }
    return rows
  }
  function scanPickerDir(dir) {
    pickerProc.running = false
    pickerProc.collected = ""
    pickerProc.dir = dir
    pickerProc.command = ["bash", "-c", 'fd --max-depth 1 --type d --color never --absolute-path --exclude .git . "$1" 2>/dev/null | sort -f', "bash", String(dir)]
    pickerProc.running = true
  }
  Process {
    id: pickerProc
    property string dir: ""
    property string collected: ""
    stdout: SplitParser { onRead: function(line) { pickerProc.collected += line + "\n" } }
    onExited: {
      if (!root.page || root.page.kind !== "folders" || root.page.dir !== pickerProc.dir) return
      var subs = pickerProc.collected.split("\n").filter(function(l) { return l.length > 0 }).map(function(l) { return l.replace(/\/+$/, "") })
      root.page.rows = root.folderRows(root.page.title, root.page.dir, subs, root.page.choose)
      root.rebuildPage()
    }
  }

  // Sub-page: Get Info. Rows fill in once stat/file/du answer; ↩ copies a value.
  function gatherInfo(p) {
    infoProc.running = false
    infoProc.collected = ""
    infoProc.path = p.path
    infoProc.command = ["bash", "-c", 'stat -c "%s\t%y" -- "$1"; file -b --mime-type -- "$1"; du -sh -- "$1" 2>/dev/null | cut -f1', "bash", String(p.path)]
    infoProc.running = true
  }
  Process {
    id: infoProc
    property string path: ""
    property string collected: ""
    stdout: SplitParser { onRead: function(line) { infoProc.collected += line + "\n" } }
    onExited: {
      if (!root.page || root.page.kind !== "info" || root.page.path !== infoProc.path) return
      var lines = infoProc.collected.split("\n")
      var statParts = (lines[0] || "").split("\t")
      var modified = String(statParts[1] || "").replace(/\.\d+ .*$/, "")
      var path = infoProc.path
      var entries = [
        ["Name", root.baseNameOf(path), "doc"],
        ["Kind", String(lines[1] || ""), "info"],
        ["Size", String(lines[2] || statParts[0] || ""), "info"],
        ["Modified", modified, "info"],
        ["Where", root.prettyPath(root.dirNameOf(path) || "/"), "folder"]
      ]
      var rows = []
      for (var i = 0; i < entries.length; i++) {
        rows.push((function(e) {
          return root.act(e[0], e[2], function() { root.finishWith(function() { root.copyToClipboard(e[1]) }) }, e[1])
        })(entries[i]))
      }
      root.page.rows = rows
      root.rebuildPage()
    }
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
    referenceItem: panel.contentItem
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
    // panel grows downward from under it (spec §2).
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

    // ------------------------------------------------------------- the panel
    //
    // One glass surface (measured on Apple's Tahoe screenshots): a 330 × 48
    // capsule while nothing is typed, widening into a 560-pt panel with the
    // search row on top, a hairline, the filter capsules and 49-pt two-line
    // rows. Width, height and radius follow the `smooth` spring inside a
    // clipping rectangle; open is fade + 0.98→1 scale on `fast`, close a
    // plain fade (spec §10). Reduce Motion keeps the fades alone.
    Item {
      id: spot
      x: Math.round((panel.width - width) / 2)
      y: panel.fieldTop
      width: widthS.value
      height: heightS.value
      transformOrigin: Item.Top
      opacity: root.opened ? 1 : 0
      Behavior on opacity {
        NumberAnimation {
          duration: root.opened ? Motion.fast : Motion.exit(Motion.fast)
          easing.type: Easing.BezierSpline
          easing.bezierCurve: root.opened ? Motion.easeOut : Motion.easeExit
        }
      }

      readonly property bool expanded: root.resultsShown
      readonly property int targetWidth: root.cardWidth
      readonly property int targetHeight: expanded
        ? root.rowsTop + root.visibleRowsHeight + root.bottomPad
        : (root.dmenuActive ? root.fieldRow : root.compactHeight)
      readonly property real targetRadius: expanded ? root.panelRadius : targetHeight / 2
      HUi.SpringValue { id: widthS; epsilon: 0.5; preset: Motion.smooth; to: spot.targetWidth }
      HUi.SpringValue { id: heightS; epsilon: 0.5; preset: Motion.smooth; to: spot.targetHeight }
      HUi.SpringValue { id: radiusS; epsilon: 0.2; preset: Motion.smooth; to: spot.targetRadius }
      function snapGeometry() {
        widthS.snap(targetWidth); heightS.snap(targetHeight); radiusS.snap(targetRadius)
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
          if (spot.opacity < 0.01) {
            // A fresh open starts in its final pose; only the fade/scale runs.
            spot.snapGeometry()
            if (!Motion.reduceMotion) enterScale.restart()
          }
          Qt.callLater(function() { keyCatcher.forceActiveFocus() })
        }
      }
      Component.onCompleted: snapGeometry()

      // The round category buttons appear beside the compact capsule while
      // the pointer is over Spotlight (or after a category key), sliding in
      // from the field; inside the panel the filter capsules take over.
      // One hover zone spans the capsule, the gap and the four buttons, so
      // the pointer can travel to a button without the buttons folding away
      // in the gap. (A MouseArea, not a HoverHandler: the latter missed the
      // compositor-moved pointer on this layer surface.)
      readonly property bool buttonsShown: root.opened && !root.dmenuActive && !expanded
        && (hoverZone.containsMouse || root.buttonsPinned)
      // On top of everything, buttons excluded from its input: with no
      // accepted button it only watches hover and lets presses through.
      MouseArea {
        id: hoverZone
        z: 10
        x: 0
        y: 0
        width: card.width + root.buttonOffset + buttons.width
        height: root.compactHeight
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
      }

      RectangularShadow {
        anchors.fill: card
        radius: card.radius
        blur: root.shadowBlur
        spread: root.shadowSpread
        offset.y: root.shadowOffset
        color: Qt.rgba(0, 0, 0, root.shadowAlpha * (spot.expanded ? 1 : 0.6))
        Behavior on color { ColorAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
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
        radius: radiusS.value
        color: root.glassFill
        border.width: 1
        border.color: root.glassBorder
        clip: true
        Accessible.role: Accessible.EditableText
        Accessible.name: root.searchPlaceholder

        // Glass light edge: a soft sheen from the top (spec §5.1).
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 1
          height: root.compactHeight
          radius: parent.radius
          gradient: Gradient {
            GradientStop { position: 0.0; color: Util.alpha(root.glassHighlight, root.glassHighlight.a * 0.6) }
            GradientStop { position: 1.0; color: Util.alpha(root.glassHighlight, 0) }
          }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        // -------------------------------------------------------- search row
        Item {
          id: field
          width: parent.width
          height: spot.expanded || root.dmenuActive ? root.fieldRow : root.compactHeight
          readonly property int inset: spot.expanded ? root.panelInset : root.fieldInset

          Text {
            id: searchGlyph
            textFormat: Text.PlainText
            text: Apple.sf(0x1002AB)   // SF magnifyingglass
            color: root.inkSecondary
            font.family: root.symbolFont
            font.pixelSize: root.fieldIconSize
            anchors.left: parent.left
            anchors.leftMargin: field.inset
            anchors.verticalCenter: parent.verticalCenter
          }

          // Category chip (spec §5.2): a capsule with the category's name in
          // front of the query; ⌫ on an empty field or a click removes it.
          Rectangle {
            id: chip
            readonly property bool shown: root.pageOpen || root.category !== ""
            anchors.left: searchGlyph.right
            anchors.leftMargin: root.fieldGap
            anchors.verticalCenter: parent.verticalCenter
            height: root.chipHeight
            width: shown ? chipLabel.implicitWidth + root.chipPadX * 2 : 0
            radius: height / 2
            // Inside an action page the chip is the accent-tinted way back.
            color: root.pageOpen ? Util.alpha(Color.accent, 0.22) : root.capsuleFill
            border.width: 1
            border.color: root.pageOpen ? Util.alpha(Color.accent, 0.35) : root.glassBorder
            Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
            opacity: shown ? 1 : 0
            visible: opacity > 0
            clip: true
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
            Text {
              id: chipLabel
              anchors.centerIn: parent
              text: root.pageOpen ? "‹ " + root.page.title : root.categoryLabel(root.category)
              color: root.pageOpen ? Color.accent : root.ink
              font.family: root.uiFont
              font.pixelSize: root.chipFontSize
              font.weight: Font.Medium
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.pageOpen ? root.popPage() : root.setCategory("") }
          }

          Item {
            id: queryRow
            height: Math.round(root.fieldFontSize * root.sp.fieldLine)
            anchors.left: chip.shown ? chip.right : searchGlyph.right
            anchors.leftMargin: chip.shown ? root.pt(8) : root.fieldGap
            anchors.right: parent.right
            anchors.rightMargin: field.inset
            anchors.verticalCenter: parent.verticalCenter
            clip: true

            readonly property int caretGap: root.pt(2)
            readonly property string shownQuery: root.pageOpen ? root.pageFilter
              : root.fileSearchActive && root.category !== "files" ? panel.shownFilter.slice(1) : panel.shownFilter
            readonly property bool hasQuery: shownQuery.length > 0

            // The restored query is drawn selected (spec §8).
            Rectangle {
              visible: root.querySelected && queryRow.hasQuery
              x: queryText.x - root.pt(1)
              width: queryText.width + root.pt(2)
              height: parent.height
              radius: root.pt(3)
              color: Util.alpha(Color.accent, 0.35)
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
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
              id: caret
              width: Math.max(1, root.pt(root.sp.caret))
              height: Math.round(root.fieldFontSize * 1.15)
              radius: width / 2
              color: root.ink
              opacity: root.caretOn && !root.querySelected ? 1 : 0
              x: queryRow.hasQuery ? queryText.width + queryRow.caretGap : 0
              anchors.verticalCenter: parent.verticalCenter
              Behavior on opacity { NumberAnimation { duration: Motion.instant; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
            }

            // Inline completion: the rest of the top hit's name plus " — Kind".
            Text {
              id: completionText
              textFormat: Text.PlainText
              visible: queryRow.hasQuery && root.opened && !root.pageOpen && text.length > 0
              text: root.completionRest ? root.completionRest + root.completionSuffix : ""
              color: root.inkTertiary
              font.family: root.uiFont
              font.pixelSize: root.fieldFontSize
              elide: Text.ElideRight
              x: caret.x + caret.width + queryRow.caretGap
              width: Math.max(0, queryRow.width - x)
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: placeholderText
              textFormat: Text.PlainText
              visible: !queryRow.hasQuery
              text: root.pageOpen ? root.pagePlaceholder : root.searchPlaceholder
              width: parent.width - caret.width - queryRow.caretGap
              x: caret.width + queryRow.caretGap
              color: root.inkTertiary
              font.family: root.uiFont
              font.pixelSize: root.fieldFontSize
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

        // Hairline under the search row (measured: very faint, inset like the capsules).
        Rectangle {
          x: root.panelInset
          y: root.fieldRow
          width: parent.width - root.panelInset * 2
          height: 1
          color: root.separator
          opacity: spot.expanded ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
        }

        // ------------------------------------------------- filter capsules
        //
        // Four equal capsules under the search row (Apple: Photos · Actions ·
        // Help · Mail); here the categories, the active one filled stronger.
        Row {
          id: capsules
          x: root.panelInset
          y: root.capsuleTop
          width: parent.width - root.panelInset * 2
          height: root.capsuleHeight
          spacing: root.capsuleGap
          opacity: spot.expanded && root.showCapsules ? 1 : 0
          visible: opacity > 0
          Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
          Repeater {
            model: root.categories
            delegate: Item {
              id: capsule
              required property int index
              required property var modelData
              readonly property bool active: root.category === modelData.id
              width: Math.floor((capsules.width - root.capsuleGap * (root.categories.length - 1)) / root.categories.length)
              height: root.capsuleHeight
              Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: capsule.active ? root.capsuleSelectedFill : press.hovered ? root.capsuleSelectedFill : root.capsuleFill
                border.width: 1
                border.color: root.glassBorder
                Behavior on color { ColorAnimation { duration: press.hovered ? Motion.instant : Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
              }
              HUi.Pressable {
                id: press
                anchors.fill: parent
                radius: height / 2
                tint: root.ink
                showFill: false
                Accessible.role: Accessible.Button
                Accessible.name: capsule.modelData.label + " (Ctrl+" + capsule.modelData.key + ")"
                onClicked: root.setCategory(capsule.modelData.id)
                Text {
                  anchors.centerIn: parent
                  text: capsule.modelData.label
                  color: capsule.active ? root.ink : root.inkSecondary
                  font.family: root.uiFont
                  font.pixelSize: root.capsuleFontSize
                  font.weight: capsule.active ? Font.Medium : Font.Normal
                }
              }
            }
          }
        }

        // ------------------------------------------------------------ rows
        Item {
          id: resultsViewport
          x: root.rowInset
          y: root.rowsTop
          width: parent.width - root.rowInset * 2
          height: root.visibleRowsHeight
          clip: true
          opacity: spot.expanded ? 1 : 0
          visible: opacity > 0
          Behavior on y { NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut } }
          Behavior on opacity {
            NumberAnimation {
              duration: spot.expanded ? Motion.fast : Motion.exit(Motion.fast)
              easing.type: Easing.BezierSpline
              easing.bezierCurve: spot.expanded ? Motion.easeOut : Motion.easeExit
            }
          }

          // Drill-in (henri-ui §3b): the list moves 30 % left and fades while
          // the action page slides in from the right; back is the mirror.
          Item {
            id: mainPane
            width: parent.width
            height: parent.height
            x: root.pageOpen && !Motion.reduceMotion ? -Math.round(width * Motion.pageParallax) : 0
            opacity: root.pageOpen ? 0 : 1
            visible: opacity > 0
            Behavior on x { NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut } }
            Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut } }

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
              readonly property bool isCalc: row.kind === "calc"
              readonly property bool hasIcon: row.icon.length > 0 || row.isApp
              readonly property bool isMenu: row.kind === "menu" || row.kind === "link" || row.isDir
              readonly property string subtitle: row.detail.length > 0 ? row.detail : root.kindName(row.kind, row.isDir)
              readonly property bool twoLine: !isCalc && subtitle.length > 0

              width: ListView.view.width
              height: root.rowHeightFor(row)
              radius: root.rowRadius
              // A light tint, text unchanged, switching instantly (spec §10).
              color: hasCursor ? root.selection : mouseArea.containsMouse ? root.hoverFill : Util.alpha(root.hoverFill, 0)
              border.width: 1
              border.color: hasCursor ? root.selectionBorder : Util.alpha(root.selectionBorder, 0)
              Accessible.role: Accessible.ListItem
              Accessible.name: row.label

              Text {
                id: iconText
                textFormat: Text.PlainText
                visible: row.hasIcon && !row.isApp
                text: row.icon
                color: row.isMenu || row.kind === "action" ? root.ink : root.inkSecondary
                font.family: row.iconFont.length > 0 ? row.iconFont : root.fontFamily
                font.pixelSize: Math.round(root.rowIcon * 0.8)
                width: root.rowIcon
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                anchors.left: parent.left
                anchors.leftMargin: root.rowIconInset
                anchors.verticalCenter: parent.verticalCenter
              }

              Image {
                id: appIconImage
                visible: row.isApp
                width: root.rowIcon
                height: root.rowIcon
                fillMode: Image.PreserveAspectFit
                // Decode at physical pixels — a logical-size decode leaves
                // PNG icons upscaled and blurry on HiDPI displays.
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: row.isApp ? (root.appLibrary ? root.appLibrary.iconSource(row.appIcon) : root.fallbackIcon(row.appIcon)) : ""
                asynchronous: true
                anchors.left: parent.left
                anchors.leftMargin: root.rowIconInset
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                id: contentColumn
                anchors.left: parent.left
                anchors.leftMargin: row.hasIcon ? root.rowTextX : root.rowIconInset
                anchors.right: trail.left
                anchors.rightMargin: root.pt(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                  id: labelText
                  textFormat: Text.PlainText
                  width: parent.width
                  text: row.label
                  color: root.ink
                  font.family: root.uiFont
                  font.pixelSize: row.isCalc ? root.calcFontSize : root.titleFontSize
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: row.twoLine
                  text: row.subtitle
                  color: root.inkSecondary
                  font.family: root.uiFont
                  font.pixelSize: root.subtitleFontSize
                  elide: Text.ElideRight
                }
              }

              Row {
                id: trail
                anchors.right: parent.right
                anchors.rightMargin: root.metaInset
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.pt(8)

                // The calculator names itself on the right; menus show a chevron.
                Text {
                  textFormat: Text.PlainText
                  visible: text.length > 0
                  text: row.isCalc ? row.detail : row.isMenu ? "›" : ""
                  color: row.isMenu ? root.inkTertiary : root.inkSecondary
                  font.family: root.uiFont
                  font.pixelSize: row.isMenu ? root.titleFontSize : root.metaFontSize
                  anchors.verticalCenter: parent.verticalCenter
                }

                // Return hint as a small chip on the selected row (Apple's quick-key chip).
                Rectangle {
                  visible: row.hasCursor
                  width: root.shortcutW
                  height: root.shortcutH
                  radius: root.shortcutRadius
                  color: root.shortcutFill
                  border.width: 1
                  border.color: root.glassBorder
                  anchors.verticalCenter: parent.verticalCenter
                  Text {
                    anchors.centerIn: parent
                    text: "↩"
                    color: root.inkSecondary
                    font.family: root.uiFont
                    font.pixelSize: root.shortcutFontSize
                  }
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
                border.width: 1
                border.color: cell.hasCursor ? root.selectionBorder : Util.alpha(root.selectionBorder, 0)

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
                    color: root.ink
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
            font.pixelSize: root.subtitleFontSize
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            width: parent.width - root.rowInset * 2
          }
          }

          Item {
            id: pagePane
            width: parent.width
            height: parent.height
            x: root.pageOpen ? 0 : (Motion.reduceMotion ? 0 : width)
            opacity: root.pageOpen ? 1 : 0
            visible: opacity > 0
            Behavior on x { NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut } }
            Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut } }

            // Head of the page: the item the actions belong to (or the
            // sub-page's subject), over a hairline — what says "you are
            // inside", together with the accent chip in the field.
            Item {
              id: pageHeader
              width: parent.width
              height: root.actionHeader
              Text {
                id: headerGlyph
                textFormat: Text.PlainText
                visible: root.page && !root.page.headerAppIcon && !!root.page.headerIcon
                text: root.page ? String(root.page.headerIcon || "") : ""
                color: root.ink
                font.family: root.page && root.page.headerIconFont ? root.page.headerIconFont : root.fontFamily
                font.pixelSize: Math.round(root.rowIcon * 0.8)
                width: root.rowIcon
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                anchors.left: parent.left
                anchors.leftMargin: root.rowIconInset
                anchors.verticalCenter: parent.verticalCenter
              }
              Image {
                visible: root.page && !!root.page.headerAppIcon
                width: root.rowIcon
                height: root.rowIcon
                fillMode: Image.PreserveAspectFit
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: root.page && root.page.headerAppIcon ? (root.appLibrary ? root.appLibrary.iconSource(root.page.headerAppIcon) : root.fallbackIcon(root.page.headerAppIcon)) : ""
                asynchronous: true
                anchors.left: parent.left
                anchors.leftMargin: root.rowIconInset
                anchors.verticalCenter: parent.verticalCenter
              }
              Column {
                anchors.left: parent.left
                anchors.leftMargin: root.rowTextX
                anchors.right: parent.right
                anchors.rightMargin: root.metaInset
                anchors.verticalCenter: parent.verticalCenter
                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: root.page ? String(root.page.headerTitle || "") : ""
                  color: root.ink
                  font.family: root.uiFont
                  font.pixelSize: root.titleFontSize
                  font.weight: Font.DemiBold
                  elide: Text.ElideRight
                }
                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: text.length > 0
                  text: root.page ? String(root.page.headerSubtitle || "") : ""
                  color: root.inkSecondary
                  font.family: root.uiFont
                  font.pixelSize: root.subtitleFontSize
                  elide: Text.ElideMiddle
                }
              }
              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: root.rowIconInset
                anchors.rightMargin: root.metaInset
                height: 1
                color: root.separator
              }
            }

            ListView {
              id: pageList
              anchors.top: pageHeader.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              model: pageModel
              clip: true
              boundsBehavior: Flickable.DragAndOvershootBounds
              flickDeceleration: Motion.flickDeceleration
              maximumFlickVelocity: Motion.maximumFlickVelocity
              Accessible.role: Accessible.List

              section.property: "section"
              section.criteria: ViewSection.FullString
              section.delegate: Item {
                required property string section
                readonly property bool first: section === root.firstPageSection
                width: ListView.view.width
                height: section ? root.pageSectionHeight(first) : 0
                visible: section !== ""
                Text {
                  textFormat: Text.PlainText
                  x: root.rowIconInset
                  y: root.pt(parent.first ? root.sp.sectionTopFirst : root.sp.sectionTop)
                  height: root.sectionLine
                  verticalAlignment: Text.AlignVCenter
                  text: root.sectionTitle(parent.section)
                  color: root.inkSecondary
                  font.family: root.uiFont
                  font.pixelSize: root.sectionFontSize
                  font.weight: Font.DemiBold
                }
              }

              delegate: Rectangle {
                id: prow
                required property int index
                required property string label
                required property string detail
                required property string icon
                required property string iconFont
                required property string appIcon
                required property bool hasMore
                required property bool danger
                required property string section
                readonly property bool hasCursor: prow.index === root.pageSelected
                readonly property bool isApp: appIcon.length > 0
                readonly property color labelColor: danger ? Color.urgent : root.ink
                width: ListView.view.width
                height: root.actionRowHeight
                radius: root.rowRadius
                color: hasCursor ? root.selection : pmouse.containsMouse ? root.hoverFill : Util.alpha(root.hoverFill, 0)
                border.width: 1
                border.color: hasCursor ? root.selectionBorder : Util.alpha(root.selectionBorder, 0)
                Accessible.role: Accessible.ListItem
                Accessible.name: prow.label

                Text {
                  textFormat: Text.PlainText
                  visible: !prow.isApp && prow.icon.length > 0
                  text: prow.icon
                  color: prow.labelColor
                  font.family: prow.iconFont.length > 0 ? prow.iconFont : root.fontFamily
                  font.pixelSize: Math.round(root.actionRowHeight * 0.42)
                  width: root.rowIcon
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  anchors.left: parent.left
                  anchors.leftMargin: root.rowIconInset
                  anchors.verticalCenter: parent.verticalCenter
                }
                Image {
                  visible: prow.isApp
                  width: Math.round(root.actionRowHeight * 0.6)
                  height: width
                  fillMode: Image.PreserveAspectFit
                  sourceSize.width: width * Screen.devicePixelRatio
                  sourceSize.height: height * Screen.devicePixelRatio
                  source: prow.isApp ? (root.appLibrary ? root.appLibrary.iconSource(prow.appIcon) : root.fallbackIcon(prow.appIcon)) : ""
                  asynchronous: true
                  anchors.left: parent.left
                  anchors.leftMargin: root.rowIconInset + Math.round((root.rowIcon - width) / 2)
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  id: plabel
                  textFormat: Text.PlainText
                  anchors.left: parent.left
                  anchors.leftMargin: root.rowTextX
                  anchors.right: pdetail.left
                  anchors.rightMargin: root.pt(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: prow.label
                  color: prow.labelColor
                  font.family: root.uiFont
                  font.pixelSize: root.actionFontSize
                  elide: Text.ElideRight
                }
                Text {
                  id: pdetail
                  textFormat: Text.PlainText
                  anchors.right: ptrail.left
                  anchors.rightMargin: root.pt(8)
                  anchors.verticalCenter: parent.verticalCenter
                  visible: prow.detail.length > 0
                  text: prow.detail
                  color: root.inkSecondary
                  font.family: root.uiFont
                  font.pixelSize: root.metaFontSize
                  elide: Text.ElideMiddle
                  width: Math.min(implicitWidth, Math.round(prow.width * 0.45))
                }
                Row {
                  id: ptrail
                  anchors.right: parent.right
                  anchors.rightMargin: root.metaInset
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: root.pt(8)
                  Text {
                    textFormat: Text.PlainText
                    visible: prow.hasMore
                    text: "›"
                    color: root.inkTertiary
                    font.family: root.uiFont
                    font.pixelSize: root.titleFontSize
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Rectangle {
                    visible: prow.hasCursor && !prow.hasMore
                    width: root.shortcutW
                    height: root.shortcutH
                    radius: root.shortcutRadius
                    color: root.shortcutFill
                    border.width: 1
                    border.color: root.glassBorder
                    anchors.verticalCenter: parent.verticalCenter
                    Text { anchors.centerIn: parent; text: "↩"; color: root.inkSecondary; font.family: root.uiFont; font.pixelSize: root.shortcutFontSize }
                  }
                }
                MouseArea {
                  id: pmouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: if (pointerGate.moved(prow, { x: pmouse.mouseX, y: pmouse.mouseY })) root.pageSelected = prow.index
                  onPositionChanged: function(mouse) { if (pointerGate.moved(prow, mouse)) root.pageSelected = prow.index }
                  onClicked: { root.pageSelected = prow.index; root.activatePageRow(prow.index, false) }
                }
              }
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              y: pageHeader.height + Math.round((parent.height - pageHeader.height - height) / 2)
              visible: pageModel.count === 0
              textFormat: Text.PlainText
              text: root.page && root.page.kind === "info" && !root.pageFilter ? "Reading…" : "Nothing matches “" + root.pageFilter + "”"
              color: root.inkSecondary
              font.family: root.uiFont
              font.pixelSize: root.subtitleFontSize
              width: parent.width - root.rowInset * 2
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
            }
          }
        }
      }

      // ------------------------------------------------------ category buttons
      Item {
        id: buttonsArea
        anchors.left: card.right
        anchors.leftMargin: root.buttonOffset
        y: Math.round((root.compactHeight - root.buttonSize) / 2)
        width: buttons.width
        height: root.buttonSize
      Row {
        id: buttons
        spacing: root.buttonGap
        Repeater {
          model: root.categories
          delegate: Item {
            id: catButton
            required property int index
            required property var modelData
            readonly property bool active: root.category === modelData.id
            readonly property bool focused: root.buttonFocus === index
            readonly property bool shown: spot.buttonsShown
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
            // Keyboard focus: hover-strength fill plus the accent ring (henri-ui §3).
            Rectangle {
              anchors.fill: parent
              radius: width / 2
              color: Util.alpha(root.ink, catButton.focused ? Motion.hoverAlpha : 0)
              Behavior on color { ColorAnimation { duration: catButton.focused ? Motion.instant : Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
            }
            Rectangle {
              anchors.fill: parent
              anchors.margins: -Style.space(Motion.focusRing)
              radius: width / 2
              color: "transparent"
              border.width: Style.space(Motion.focusRing)
              border.color: Util.alpha(Color.accent, 0.6)
              opacity: catButton.focused ? 1 : 0
              Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
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

        if (root.pageOpen) {
          // Action page: ↑↓ move, ↩ runs, → / Tab descend, ← / Esc / ⌫ on an
          // empty filter go back, typing filters.
          event.accepted = true
          if (event.key === Qt.Key_Escape || (arrowLeft && !root.pageFilter) || (event.key === Qt.Key_Backspace && !root.pageFilter)) root.popPage()
          else if (event.key === Qt.Key_Up || ((event.key === Qt.Key_K || event.key === Qt.Key_P) && ctrl)) root.selectPage(-1)
          else if (event.key === Qt.Key_Down || ((event.key === Qt.Key_J || event.key === Qt.Key_N) && ctrl)) root.selectPage(1)
          else if (event.key === Qt.Key_Home) root.selectPage(-pageModel.count)
          else if (event.key === Qt.Key_End) root.selectPage(pageModel.count)
          else if (event.key === Qt.Key_PageUp) root.selectPage(-6)
          else if (event.key === Qt.Key_PageDown) root.selectPage(6)
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.activatePageRow(root.pageSelected, false)
          else if (arrowRight || event.key === Qt.Key_Tab) root.activatePageRow(root.pageSelected, true)
          else if (Util.editsFilter(event, root.pageFilter)) root.setPageFilter(Util.editedFilter(event, root.pageFilter))
          else if (printable) root.setPageFilter(root.pageFilter + event.text)
          else event.accepted = false
          return
        }

        if (root.blankRoot && !root.dmenuActive && (event.key === Qt.Key_Right || event.key === Qt.Key_Down
            || event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
          // Empty field: the arrows walk the category buttons.
          var forward = event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab
          root.moveButtonFocus(forward ? 1 : -1)
          event.accepted = true
        } else if (root.blankRoot && root.buttonFocus >= 0 && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
          root.activateButtonFocus()
          event.accepted = true
        } else if (root.blankRoot && root.buttonFocus >= 0 && event.key === Qt.Key_Escape) {
          root.clearButtonFocus()
          event.accepted = true
        } else if (event.key === Qt.Key_Right && event.modifiers === Qt.ControlModifier && root.isAppsGrid) {
          // In the grid → moves the cursor, so ⌃→ opens the actions there.
          root.openActionsForSelected()
          event.accepted = true
        } else if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_4 && !root.dmenuActive) {
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
        } else if (arrowRight && !root.isAppsGrid) {
          // → opens the actions for the selected result (Tab still takes the completion).
          if (!root.openActionsForSelected() && displayModel.count > 0) root.cursorActive = true
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
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
        message: root.confirmSpec ? root.confirmSpec.message : ""
        confirmText: root.confirmSpec ? root.confirmSpec.confirmText : "Confirm"
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
