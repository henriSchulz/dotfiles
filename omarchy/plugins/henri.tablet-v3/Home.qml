import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "file:///home/henri/.local/share/velum/qml/Velum"
import "HomeModel.js" as HM

// Tablet mode's home screen and home gesture, as on an iPad (design: lab/web/home.html).
//
// The home screen is an empty workspace: a bottom-layer surface draws the app grid and the dock
// (HomeScreen.qml) wherever the focused workspace has no window. The home gesture runs on an
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
  readonly property bool inRig: Quickshell.env("VELUM_SHELL_RIG") !== ""

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
      map[id] = { id: id, name: String(e.name || id), icon: home.iconOf(e.icon) }
      list.push(id)
    }
    list.sort(function (a, b) { return map[a].name.localeCompare(map[b].name) })
    home.entries = map
    home.appIds = list
  }
  Connections { target: DesktopEntries.applications; function onValuesChanged() { appsDebounce.restart() } }
  Timer { id: appsDebounce; interval: Theme.delay("settle"); onTriggered: home.scanApps() }
  readonly property var dockApps: pinnedIds.map(function (id) { return entries[id] }).filter(Boolean)
  readonly property var gridApps: appIds.filter(function (id) { return pinnedIds.indexOf(id) < 0 }).map(function (id) { return entries[id] })
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
      if (!o || !o.workspace || o.workspace.id <= 0 || o.floating || !o.mapped) continue
      if (mon && o.monitor !== mon.id) continue
      var id = appIdOf(o.class), e = entries[id]
      out.push({ key: String(o.address), address: String(o.address), toplevel: t, workspace: o.workspace.id, appId: id,
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
  readonly property var followPreset: ({ response: cfg.followResponse / 1000 * (Theme.reduceMotion ? 0 : 1), dampingRatio: cfg.followDamping })
  property string screenName: ""
  property var cards: []            // the entries shown as cards, oldest first
  property int cur: -1              // the card that was on screen
  property bool fromHome: false
  // a finger of the home zone is down (Tablet.qml): the switcher that finger opened takes no touch
  // until it lifts, or its own release would land on the new surface as a tap
  property bool zoneFinger: false
  property bool armed: false
  property real areaW: 0
  property real areaH: 0
  property var cardItems: ({})      // key → Card
  property string settleTo: "idle"
  readonly property bool covering: mode === "drag" || mode === "switcher" || mode === "settle"

  Spring { id: homeV; preset: Theme.spring("smooth"); reduced: Theme.reduceMotion }
  Spring { id: dimV; preset: Theme.spring("smooth"); reduced: Theme.reduceMotion }
  Spring { id: labelV; preset: Theme.spring("smooth"); reduced: Theme.reduceMotion }
  Spring { id: pageV; preset: Theme.spring("smooth"); reduced: Theme.reduceMotion }
  property int page: 0
  property real swX: 0              // the switcher's scroll: where the newest column's centre sits

  function card(i) { var c = cards[i]; return c ? cardItems[c.key] : null }
  function register(key, item) { var o = Object.assign({}, cardItems); if (item) o[key] = item; else delete o[key]; cardItems = o }

  // ---- a finger landed in the home zone
  // the finger did something else (a tap, a long press, a slide): nothing to draw
  function other(kind) {
    if (mode === "ready") { mode = "idle"; endStat(kind) }
    else if (fromHome && stat.t0) endStat(kind)
  }
  // drop whatever the overlay is doing (a new finger always wins over a stuck animation)
  function abort() {
    settleTick.stop(); letGo.stop(); enterLater.stop(); openLater.stop(); closeLater.stop()
    settleCheck = null; launchedId = ""; armed = false
    mode = emptyOn(screenName) ? "home" : "idle"
    note("abort")
    endStat("abort")
  }
  function prepare(screenName) {
    if (!active) return
    if (mode === "settle" || mode === "ready" || mode === "drag" || mode === "homeDrag") abort()
    if (mode !== "idle" && mode !== "home") return
    home.screenName = screenName
    // the monitor's active workspace can lag behind a change the overlay made (Quickshell updates
    // it on the next refresh); our own "home" counts as well
    Hyprland.refreshMonitors()
    Hyprland.refreshWorkspaces()
    fromHome = mode === "home" || emptyOn(screenName)
    armed = false
    Hyprland.refreshToplevels()
    var list = scanWindows(screenName)
    var m = monitorOf(screenName), at = -1
    for (var i = 0; i < list.length; i++) if (m && m.activeWorkspace && list[i].workspace === m.activeWorkspace.id) at = i
    if (fromHome) { cur = list.length - 1; cards = list; mode = "home"; return }
    startStat()
    if (at < 0) return
    cards = list
    cur = at
    homeV.snap(0); dimV.snap(0); labelV.snap(0)
    for (var j = 0; j < list.length; j++) {
      var o = cardItems[list[j].key]
      if (!o) continue
      o.set("x", HM.besideX(j, at, 1, 0, areaW, cfg)); o.set("y", 0); o.set("s", 1); o.set("m", 0); o.set("l", 0); o.set("o", 1)
      o.z = j === at ? 2 : 1
    }
    var c = cardItems[list[at].key]
    if (c) c.refresh()
    stat.shot = c && c.hasShot ? 0 : -1
    mode = "ready"
    note("ready " + list[at].appId)
  }

  // ---- the finger moves up (lift) — or keeps moving while the switcher is armed
  function lift(up, dx, vy) {
    if (fromHome) { liftFromHome(up); return }
    if (mode !== "ready" && mode !== "drag") return
    var c = card(cur)
    var now = Date.now()
    if (stat.last) { var gap = now - stat.last; stat.maxGap = Math.max(stat.maxGap, gap); stat.sumGap += gap }
    stat.last = now; stat.lifts++
    if (!c || !c.hasShot) return               // the overlay stays clear until the snapshot is there
    if (stat.shot < 0) stat.shot = now - stat.t0
    mode = "drag"
    var f = HM.follow(up, dx, areaW, areaH, cfg, { left: cur <= 0, right: cur >= cards.length - 1 }, vy || 0)
    // a very fast spring instead of a jump: finger events from a cast come unevenly, the card glides
    var fp = followPreset
    c.to("x", f.x, fp); c.to("y", f.y, fp); c.to("s", f.s, fp)
    for (var i = 0; i < cards.length; i++) {
      if (i === cur) continue
      var o = card(i)
      if (o) { o.to("x", HM.besideX(i, cur, f.s, f.x, areaW, cfg), fp); o.to("y", f.y, fp); o.to("s", f.s, fp); o.set("o", 1) }
    }
    homeV.snap(f.home)
  }
  // on the home screen the switcher's cards come up under the finger (as on an iPad), and sink back
  // if it lets go low
  function liftFromHome(up) {
    if (mode !== "home" && mode !== "homeDrag") return
    if (!cards.length) cards = scanWindows(screenName)
    if (!cards.length) return
    var p = Math.max(0, Math.min(1, up / (2 * tt.holdTravel)))
    if (mode === "home") { mode = "homeDrag"; homeV.snap(1); dimV.snap(0) }
    labelV.snap(p)
    var g = HM.switcherGeo(cards.length, areaW, areaH, cfg)
    swX = g.lo
    for (var i = 0; i < cards.length; i++) {
      var o = card(i)
      if (!o) continue
      var pos = HM.switcherPos(i, cards.length, g.lo, g, cfg)
      o.set("x", pos.x); o.set("m", 0); o.set("l", 0); o.set("o", p)
      o.to("y", pos.y + (1 - p) * areaH * cfg.enterFrom, followPreset)
      o.to("s", g.s * (cfg.dockIcon + (1 - cfg.dockIcon) * p), followPreset)
      o.capture = true
    }
  }
  function sinkBack() {
    note("sink back")
    for (var i = 0; i < cards.length; i++) { var o = card(i); if (o) { o.to("o", 0, "snappy"); o.to("y", o.value("y") + areaH * cfg.enterFrom, "snappy") } }
    labelV.target = 0
    sinkDone.restart()
  }
  Timer { id: sinkDone; interval: Theme.dur("normal"); onTriggered: if (home.mode === "homeDrag") home.mode = "home" }
  function arm() {
    if (armed) return
    armed = true
    note("armed")
    if (fromHome) { enterSwitcherFromHome(); return }
    for (var i = 0; i < cards.length; i++) { var o = card(i); if (o) o.capture = true }
    dimV.target = 1; labelV.target = 1
  }

  // ---- the finger let go: "home" (far / fast), "switcher" (after a pause), "end" (short), "cancel"
  function release(kind, info) {
    info = info || {}
    stat.release = kind
    stat.travel = Math.round(info.travel || 0)
    if (fromHome) {
      if (kind !== "cancel" && (armed || kind === "home" || kind === "switcher" || (info.travel || 0) > tt.holdTravel)) enterSwitcherFromHome()
      else if (mode === "homeDrag") sinkBack()
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
    if (to === "home") toHome(hand)
    else if (to === "switcher") toSwitcher(hand)
    else if (to === "next" || to === "prev") openCard(cur + (to === "next" ? 1 : -1), hand)
    else back(hand)
  }

  // ---- what each gesture did, for tuning on the device (IPC homeStats): how long the snapshot
  // took, how many finger events came and the largest gap between them
  property var stat: ({})
  property var stats: []
  function startStat() { stat = { t0: Date.now(), shot: -1, lifts: 0, last: 0, maxGap: 0, sumGap: 0, release: "", travel: 0, fromHome: fromHome } }
  function endStat(to) {
    if (!stat.t0) return
    var l = stats.slice(-29)
    l.push({ ms: Date.now() - stat.t0, shotMs: stat.shot, lifts: stat.lifts, maxGap: stat.maxGap,
             avgGap: stat.lifts > 1 ? Math.round(stat.sumGap / (stat.lifts - 1)) : 0,
             release: stat.release, decided: stat.decided || "", travel: stat.travel, fromHome: stat.fromHome, to: to })
    stats = l
    stat = {}
  }

  // ---- outcomes
  function layoutApp(at, hand) {
    for (var i = 0; i < cards.length; i++) {
      var o = card(i)
      if (!o) continue
      var here = i === at
      o.to("x", HM.besideX(i, at, 1, 0, areaW, cfg), "snappy", here && hand ? hand.x : undefined)
      o.to("y", 0, "snappy", here && hand ? hand.y : undefined)
      o.to("s", 1, "snappy", here && hand ? hand.s : undefined)
      o.to("m", 0, "snappy"); o.to("l", 0, "snappy"); if (here) o.to("o", 1, "snappy")
      o.z = here ? 2 : 1
    }
    homeV.target = 0; dimV.target = 0; labelV.target = 0
  }
  function back(hand) {
    note("back")
    layoutApp(cur, hand)
    settleWhen(function () { var c = card(cur); return !c || c.settled(["x", "y", "s"]) }, "idle", false)
  }
  function toHome(hand) {
    note("home")
    var c = card(cur), e = cards[cur]
    var r = homeScreenItem ? homeScreenItem.iconRect(e.appId, coverItem || homeScreenItem) : null
    var tx = r ? r.x + r.w / 2 - areaW / 2 : 0, ty = r ? r.y + r.w / 2 - areaH / 2 : areaH * cfg.enterFrom
    var size = r ? r.w : HM.grid(areaW, areaH, cfg).icon
    // SpringBoard's flight into the icon: its own spring, half the finger's vertical speed
    var fly = { response: cfg.flyResponse / 1000, dampingRatio: cfg.flyDamping }
    c.to("x", tx, fly, hand.x); c.to("y", ty, fly, hand.y * cfg.flyVelocity); c.to("s", size / areaH, fly, hand.s)
    c.to("m", 1, fly); c.z = 2
    for (var i = 0; i < cards.length; i++) if (i !== cur && card(i)) card(i).to("o", 0, "snappy")
    homeV.target = 1; dimV.target = 0; labelV.target = 0
    settleWhen(function () { return c.settled(["x", "y", "s"]) }, "home", true)
  }
  // the first empty workspace on the gesture's screen (not just any empty one: another monitor's
  // would leave this screen on its app)
  function goHomeNow() {
    var mon = String(screenName).replace(/[^A-Za-z0-9_-]/g, "")
    dispatch("function() hl.dispatch(hl.dsp.focus({ monitor = \"" + mon + "\" })) hl.dispatch(hl.dsp.focus({ workspace = \"emptynm\" })) end",
             "workspace emptynm")
  }
  function toSwitcher(hand) {
    note("switcher")
    mode = "switcher"
    var g = HM.switcherGeo(cards.length, areaW, areaH, cfg)
    swX = g.lo
    for (var i = 0; i < cards.length; i++) {
      var o = card(i)
      if (!o) continue
      var p = HM.switcherPos(i, cards.length, swX, g, cfg), here = i === cur
      o.capture = true
      o.to("x", p.x, "snappy", here && hand ? hand.x : undefined)
      o.to("y", p.y, "snappy", here && hand ? hand.y : undefined)
      o.to("s", g.s, "snappy", here && hand ? hand.s : undefined)
      o.to("m", 0, "snappy"); o.to("o", 1, "snappy"); o.to("l", 0, "snappy")
      o.z = 1
    }
    homeV.target = 1; dimV.target = 1; labelV.target = 1
  }
  function enterSwitcherFromHome() {
    if (mode === "switcher") return
    if (mode === "homeDrag") {
      note("switcher from home")
      sinkDone.stop()
      mode = "switcher"
      var g = HM.switcherGeo(cards.length, areaW, areaH, cfg)
      swX = g.lo
      for (var i = 0; i < cards.length; i++) {
        var o = card(i)
        if (!o) continue
        var p = HM.switcherPos(i, cards.length, g.lo, g, cfg)
        o.to("x", p.x, "snappy"); o.to("y", p.y, "snappy"); o.to("s", g.s, "snappy"); o.to("o", 1, "snappy")
      }
      labelV.target = 1
      return
    }
    var list = scanWindows(screenName)      // fresh: the refresh prepare() asked for has arrived by now
    if (!list.length) return
    note("switcher from home")
    cards = list
    cur = list.length - 1
    homeV.snap(1); dimV.snap(0); labelV.snap(0)
    mode = "switcher"
    // the cards come up from below once they exist (Repeater): placeAndEnter runs on the next frame
    enterLater.restart()
  }
  Timer {
    id: enterLater
    interval: 0
    onTriggered: {
      var g = HM.switcherGeo(home.cards.length, home.areaW, home.areaH, home.cfg)
      home.swX = g.lo
      for (var i = 0; i < home.cards.length; i++) {
        var o = home.card(i)
        if (!o) continue
        var p = HM.switcherPos(i, home.cards.length, g.lo, g, home.cfg)
        o.capture = true
        o.set("x", p.x); o.set("y", p.y + home.areaH * home.cfg.enterFrom); o.set("s", g.s * home.cfg.dockIcon); o.set("m", 0); o.set("o", 0); o.set("l", 0)
        o.to("y", p.y, "snappy"); o.to("s", g.s, "snappy"); o.to("o", 1, "snappy")
      }
      homeV.target = 1; dimV.target = 1; labelV.target = 1
    }
  }
  // an app from the switcher, or the neighbour a sideways finger brought: full size, then its workspace
  function openCard(i, hand) {
    note("open " + (cards[i] ? cards[i].appId : ""))
    var was = cur
    cur = i
    layoutApp(i, i === was ? hand : null)
    for (var j = 0; j < cards.length; j++) if (j !== i && card(j) && Math.abs(j - i) > 1) card(j).to("o", 0, "snappy")
    var e = cards[i]
    dispatch("hl.dsp.focus({ window = \"address:" + e.address + "\" })", "focuswindow address:" + e.address)
    var c = card(i)
    settleWhen(function () { return !c || c.settled(["x", "y", "s"]) }, "idle", false)
  }
  function switcherHome() {
    note("switcher home")
    for (var i = 0; i < cards.length; i++) { var o = card(i); if (o) { o.to("o", 0, "snappy"); o.to("s", o.value("s") * cfg.dockIcon, "snappy") } }
    homeV.target = 1; dimV.target = 0; labelV.target = 0
    settleWhen(function () { return true }, "home", true)
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
    onTriggered: {
      var list = home.cards.filter(function (c) { return c.key !== key })
      home.cards = list
      if (!list.length) { home.switcherHome(); return }
      home.cur = list.length - 1
      var g = HM.switcherGeo(list.length, home.areaW, home.areaH, home.cfg)
      home.swX = Math.max(g.lo, Math.min(g.hi, home.swX))
      relayoutLater.restart()
    }
  }
  Timer { id: relayoutLater; interval: 0; onTriggered: home.layoutSwitcher(home.swX, false) }
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
  function openApp(id) {
    if (!active) return
    var e = entries[id]
    if (!e) return
    var list = scanWindows(screenName || (Quickshell.screens[0] ? Quickshell.screens[0].name : ""))
    var at = -1
    for (var i = list.length - 1; i >= 0; i--) if (list[i].appId === id) { at = i; break }
    note("tap " + id + (at >= 0 ? " (running)" : ""))
    var r = homeScreenItem ? homeScreenItem.iconRect(id, coverItem || homeScreenItem) : null
    if (at >= 0) {
      cards = list
      cur = at
    } else {
      cards = [{ key: "launch:" + id, address: "", toplevel: null, workspace: 0, appId: id, icon: e.icon, name: e.name, focus: 0 }]
      cur = 0
      if (!inRig || Quickshell.env("VELUM_TABLET_LAUNCH") !== "") Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", id + ".desktop"])
      launchedId = id
      launchOpened = false
      launchStart = Date.now()
    }
    homeV.snap(1); dimV.snap(0); labelV.snap(0)
    mode = "settle"
    openFrom = r
    openLater.restart()
  }
  property var openFrom: null
  property string launchedId: ""
  property bool launchOpened: false
  property real launchStart: 0
  Timer {
    id: openLater
    interval: 0
    onTriggered: {
      var c = home.card(home.cur), e = home.cards[home.cur], r = home.openFrom
      if (!c) return
      c.capture = true
      for (var i = 0; i < home.cards.length; i++) if (i !== home.cur && home.card(i)) home.card(i).set("o", 0)
      c.set("x", r ? r.x + r.w / 2 - home.areaW / 2 : 0); c.set("y", r ? r.y + r.w / 2 - home.areaH / 2 : 0)
      c.set("s", (r ? r.w : home.areaH * home.cfg.splashIcon) / home.areaH); c.set("m", 1); c.set("o", 1); c.set("l", 0)
      c.z = 2
      c.to("x", 0, "smooth"); c.to("y", 0, "smooth"); c.to("s", 1, "smooth"); c.to("m", 0, "smooth")
      homeV.target = 0
      if (e.address) home.dispatch("hl.dsp.focus({ window = \"address:" + e.address + "\" })", "focuswindow address:" + e.address)
      home.settleWhen(function () {
        if (!c.settled(["x", "y", "s"])) return false
        if (!home.launchedId) return true
        // a launched app: wait for a new window, or give up after launchTimeout
        return home.launchOpened || Date.now() - home.launchStart > home.cfg.launchTimeout
      }, "idle", false)
    }
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
      if (home.settleCheck && !late && !home.settleCheck()) return
      stop()
      home.settleCheck = null
      if (home.settleTo === "home") {
        home.goHomeNow()
        letGo.to = "home"
      } else letGo.to = "idle"
      letGo.interval = home.settleWait || home.settleTo === "home" ? home.cfg.settle : (home.launchedId ? home.cfg.settle : Theme.dur("fast"))
      letGo.restart()
    }
  }
  Timer {
    id: letGo
    property string to: "idle"
    onTriggered: {
      home.mode = to
      home.launchedId = ""
      home.armed = false
      home.cards = home.scanWindows(home.screenName)
      home.note("→ " + to)
      home.endStat(to)
    }
  }

  // ---- home screen pages
  function pageMoved(dx, t) { pageV.snap(-page * areaW + dx) }
  function pageReleased(v, pages) {
    var i = Math.round(-pageV.value / Math.max(1, areaW))
    if (Math.abs(v) > cfg.pageFlick) i = page + (v < 0 ? 1 : -1)
    page = Math.max(0, Math.min(pages - 1, i))
    pageV.velocity = v
    pageV.target = -page * areaW
    if (pageV.value !== pageV.target) pageV.from(pageV.value)
  }
  onActiveChanged: { if (!active) { mode = "idle"; cards = [] } else rescan.restart() }

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
  Component.onCompleted: { wallpaperProbe.running = true; scanApps() }
  onModeChanged: if (mode === "ready") wallpaperProbe.running = true

  Variants {
    model: home.active ? Quickshell.screens : []

    Scope {
      id: per
      required property var modelData
      readonly property string name: modelData.name

      property real homeH: 0
      // the home screen itself, under the windows of an empty workspace
      PanelWindow {
        screen: per.modelData
        onHeightChanged: if (height > 0) per.homeH = height
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        color: "transparent"
        visible: home.emptyOn(per.name) || (home.mode === "home" && home.screenName === per.name)
        WlrLayershell.namespace: "velum-home-screen"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // no input while a home-zone finger is down: a pointer standing in for it would otherwise
        // move its focus here halfway up
        mask: Region { item: home.zoneFinger ? homeNone : homeAll }
        Item { id: homeAll; anchors.fill: parent }
        Item { id: homeNone; width: 0; height: 0 }
        HomeScreen {
          anchors.fill: parent
          apps: home.gridApps
          dockApps: home.dockApps
          recentApps: home.recentApps
          page: home.page
          pageX: pageV.value
          interactive: true
          onTapped: function (id) { home.screenName = per.name; home.openApp(id) }
          onPageMoved: function (dx, t) { home.pageMoved(dx, t) }
          onPageReleased: function (v) { home.pageReleased(v, pages) }
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
        visible: mine && home.mode !== "idle" && home.mode !== "home"
        WlrLayershell.namespace: "velum-home-overlay"
        // overlay layer: the top layer is hidden under a fullscreen app
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region { item: home.mode === "switcher" ? all : none }
        // the app area's size (a surface being mapped reports 0 for a moment: keep the last real one)
        function measure() { if (width > 0 && height > 0) { home.areaW = width; home.areaH = height } }
        onWidthChanged: if (mine || home.areaW === 0) measure()
        onHeightChanged: if (mine || home.areaH === 0) measure()
        onMineChanged: if (mine) { measure(); home.homeScreenItem = shadowHome; home.coverItem = cover }
        Component.onCompleted: if (mine || !home.homeScreenItem) { measure(); home.homeScreenItem = shadowHome; home.coverItem = cover }

        Item { id: all; anchors.fill: parent }
        Item { id: none; width: 0; height: 0 }

        Item {
          id: cover
          anchors.fill: parent
          opacity: home.mode === "ready" ? 0 : 1      // clear until the snapshot is there
          clip: true

          // the wallpaper, as the compositor draws it under the whole screen
          Image {
            width: per.modelData.width
            height: per.modelData.height
            source: "file://" + home.wallpaperLink + (home.wallpaperTarget ? "?v=" + encodeURIComponent(home.wallpaperTarget) : "")
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: per.modelData.width
            sourceSize.height: per.modelData.height
            asynchronous: false
            cache: true
          }
          // the same home screen as the bottom layer's, on the same spot (below the bar, above the home zone)
          HomeScreen {
            id: shadowHome
            x: 0
            y: Math.max(0, overlay.height - per.homeH - home.tt.homeZone)
            width: overlay.width
            height: per.homeH > 0 ? per.homeH : overlay.height
            apps: home.gridApps
            dockApps: home.dockApps
            recentApps: home.recentApps
            page: home.page
            pageX: pageV.value
            opacity: Math.max(0, Math.min(1, homeV.value))
            scale: home.cfg.homeZoom - (home.cfg.homeZoom - 1) * Math.max(0, Math.min(1, homeV.value))
            visible: opacity > 0.002
          }
          Rectangle {
            anchors.fill: parent
            color: home.cfg.dimColor
            opacity: home.cfg.dim * Math.max(0, dimV.value)   // 0 since 2026-10-28 (Henri: no grey veil)
            visible: opacity > 0.002
          }
          // the cards stay between gestures (kept by window), and so do their snapshots: a gesture
          // starts on the last one at once and only asks for a fresh one
          Repeater {
            model: ScriptModel { values: overlay.mine ? home.cards : []; objectProp: "key" }
            Card {
              required property var modelData
              entry: modelData
              areaW: overlay.width
              areaH: overlay.height
              labelOn: Math.max(0, labelV.value)
              capture: true
              Component.onCompleted: home.register(modelData.key, this)
              Component.onDestruction: home.register(modelData.key, null)
            }
          }
        }

        // the App Switcher's fingers: scroll sideways, swipe a card up to close it, tap to open
        MouseArea {
          anchors.fill: parent
          enabled: home.mode === "switcher" && !home.zoneFinger
          preventStealing: true
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
          onPressed: function (m) { x0 = m.x; y0 = m.y; sx0 = home.swX; axis = ""; hit = cardAt(m.x, m.y); samples = [[Date.now(), m.x, m.y]] }
          onPositionChanged: function (m) {
            var t = Date.now(), list = samples.concat([[t, m.x, m.y]])
            while (list.length > 2 && t - list[0][0] > home.tt.sampleWindow) list.shift()
            samples = list
            var dx = m.x - x0, dy = m.y - y0
            if (!axis && Math.hypot(dx, dy) > home.tt.slop) axis = Math.abs(dy) > Math.abs(dx) && hit >= 0 ? "y" : "x"
            if (axis === "x") {
              var g = HM.switcherGeo(home.cards.length, overlay.width, overlay.height, home.cfg)
              home.swX = HM.switcherClamp(sx0 + dx, g, home.cfg.edgeInset * 3)
              home.layoutSwitcher(home.swX, true)
            } else if (axis === "y") {
              var c = home.card(hit)
              if (c) c.set("l", dy < 0 ? dy : HM.rubber(dy, home.cfg.pushDown))
            }
          }
          onReleased: function (m) {
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
          }
          onCanceled: { if (axis === "x") home.layoutSwitcher(home.swX, false) }
        }
      }
    }
  }
}
