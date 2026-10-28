import QtQuick
import QtQuick.Effects
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
  function preset(r, d) { return { response: r / 1000 * (Theme.reduceMotion ? 0 : 1), dampingRatio: d } }
  readonly property var backPreset: preset(cfg.backResponse, cfg.backDamping)
  readonly property var switcherPreset: preset(cfg.switcherResponse, cfg.switcherDamping)
  readonly property var flyInPreset: preset(cfg.flyInResponse, cfg.flyInDamping)
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
  property var cardRep: null        // the Repeater of the gesture screen's cards
  property string settleTo: "idle"
  readonly property bool covering: mode === "drag" || mode === "switcher" || mode === "settle"

  // The backdrop, as SpringBoard layers it: the home screen's icons (homeV) only appear when the
  // card goes home; behind a dragged card and in the switcher lies the blurred wallpaper (blurV);
  // the dock slides up when a gesture starts and stays through the switcher (dockV).
  Spring { id: homeV; preset: home.preset(home.cfg.homeScreenResponse, home.cfg.homeScreenDamping); reduced: Theme.reduceMotion }
  Spring { id: blurV; preset: home.preset(home.cfg.blurResponse, home.cfg.blurDamping); reduced: Theme.reduceMotion }
  Spring { id: dockV; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion }
  // a spring sits at v and stays there: Spring.snap() keeps the old target, so the next same
  // target would not move it (the dock stayed down after a gesture that had snapped it)
  function jumpTo(sp, v) { sp.target = v; sp.snap(v) }
  function backdrop(grid, blur, dock, now) {
    if (now) { jumpTo(homeV, grid); jumpTo(blurV, blur); jumpTo(dockV, dock) }
    else { homeV.target = grid; blurV.target = blur; dockV.target = dock }
  }
  Spring { id: dimV; preset: Theme.spring("smooth"); reduced: Theme.reduceMotion }
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
      console.warn("henri.tablet-v3 Home: " + name + ": " + e)
      note("error " + name)
      abort()
    }
  }

  // ---- a finger landed in the home zone
  // the finger did something else (a tap, a long press, a slide): nothing to draw
  function other(kind) {
    if (mode === "ready") { mode = "idle"; endStat(kind) }
    else if (fromHome && stat.t0) endStat(kind)
  }
  // drop whatever the overlay is doing (a new finger always wins over a stuck animation)
  function abort() {
    settleTick.stop(); letGo.stop(); enterLater.stop(); openLater.stop(); closeLater.stop(); relayoutLater.stop()
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
    if (blurV.target !== 1) backdrop(0, 1, 1, false)
  }
  // on the home screen the switcher's cards come up under the finger (as on an iPad), and sink back
  // if it lets go low
  // on the home screen, as on an iPad: while the finger pulls up only the home screen gives way —
  // its icons fade and the wallpaper blurs with the travel; the cards come in when it lets go
  function liftFromHome(up) {
    if (mode !== "home" && mode !== "homeDrag") return
    var p = Math.max(0, Math.min(1, up / (2 * tt.holdTravel)))
    if (mode === "home") { mode = "homeDrag"; backdrop(1, 0, 1, true); jumpTo(dimV, 0); jumpTo(labelV, 0) }
    jumpTo(homeV, 1 - p); jumpTo(blurV, p)
  }
  function sinkBack() {
    note("sink back")
    for (var i = 0; i < cards.length; i++) { var o = card(i); if (o) { o.to("o", 0, "snappy"); o.to("y", o.value("y") + areaH * cfg.enterFrom, "snappy") } }
    labelV.target = 0
    backdrop(1, 0, 1, false)
    sinkDone.restart()
  }
  Timer { id: sinkDone; interval: Theme.dur("normal"); onTriggered: if (home.mode === "homeDrag") home.mode = "home" }
  function arm() {
    if (armed) return
    armed = true
    note("armed")
    if (fromHome) return                       // from the home screen the cards come when the finger lets go
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
    if (to === "home") toHome(hand, info.velocity || 0)
    else if (to === "switcher") toSwitcher(hand)
    else if (to === "next" || to === "prev") openCard(cur + (to === "next" ? 1 : -1), hand)
    else back(hand)
  }

  // ---- what each gesture did, for tuning on the device (IPC homeStats): how long the snapshot
  // took, how many finger events came and the largest gap between them
  property var stat: ({})
  property var stats: []
  function startStat() { stat = { t0: Date.now(), shot: -1, lifts: 0, last: 0, maxGap: 0, sumGap: 0, release: "", travel: 0, fromHome: fromHome, frames: 0, sumFrame: 0, maxFrame: 0, slow: 0 } }
  // the overlay's own frames while it moves (QML frame clock): is the drawing smooth?
  FrameAnimation {
    running: home.mode === "drag" || home.mode === "settle" || home.mode === "switcher" || home.mode === "homeDrag"
    onTriggered: {
      if (!home.stat.t0 || frameTime <= 0) return
      var ms = frameTime * 1000
      home.stat.frames++; home.stat.sumFrame += ms; home.stat.maxFrame = Math.max(home.stat.maxFrame, ms)
      if (ms > 25) home.stat.slow++
    }
  }
  function endStat(to) {
    if (!stat.t0) return
    var l = stats.slice(-29)
    l.push({ ms: Date.now() - stat.t0, shotMs: stat.shot, lifts: stat.lifts, maxGap: stat.maxGap,
             avgGap: stat.lifts > 1 ? Math.round(stat.sumGap / (stat.lifts - 1)) : 0,
             frames: stat.frames, avgFrame: stat.frames ? +(stat.sumFrame / stat.frames).toFixed(1) : 0, maxFrame: Math.round(stat.maxFrame), slowFrames: stat.slow,
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
      var bp = home.backPreset
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
  function toHome(hand, vUp) {
    note("home")
    var c = card(cur), e = cards[cur]
    var r = homeScreenItem ? homeScreenItem.iconRect(e.appId, coverItem || homeScreenItem) : null
    // no icon on screen (another page): it shrinks in the middle and fades
    var tx = r ? r.x + r.w / 2 - areaW / 2 : 0, ty = r ? r.y + r.w / 2 - areaH / 2 : 0
    var size = r ? r.w : HM.grid(areaW, areaH, cfg).icon
    // SpringBoard's flight into the icon: the position on its own spring with half the finger's
    // vertical speed (it carries on up, then arcs to the icon); the window turns into the icon
    // quickly on faster springs (the iPad video: an icon after ~0.12 s, landed after ~0.35 s)
    var fly = preset(cfg.flyResponse, cfg.flyDamping)
    var shrink = preset(cfg.scaleResponse, cfg.scaleDamping)
    var morph = preset(cfg.morphResponse, cfg.morphDamping)
    // the scale is handed the finger's speed (SpringBoard: 1.5 × vy / H, capped)
    var sv = -Math.min(cfg.scaleVelocityCap, cfg.scaleVelocity * Math.max(0, vUp || 0) / areaH)
    c.to("x", tx, fly, hand.x); c.to("y", ty, fly, hand.y * cfg.flyVelocity); c.to("s", size / areaH, shrink, sv)
    c.to("m", 1, morph); c.z = 2
    if (!r) c.to("o", 0, shrink)
    for (var i = 0; i < cards.length; i++) if (i !== cur && card(i)) card(i).to("o", 0, "snappy")
    backdrop(1, 0, 1, false); dimV.target = 0; labelV.target = 0
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
      // the dragged card on SpringBoard's app-to-switcher spring, the others fly in
      var sp = here ? switcherPreset : flyInPreset
      o.to("x", p.x, sp, here && hand ? hand.x : undefined)
      o.to("y", p.y, sp, here && hand ? hand.y : undefined)
      o.to("s", g.s, sp, here && hand ? hand.s : undefined)
      o.to("m", 0, sp); o.to("o", 1, sp); o.to("l", 0, sp)
      o.z = 1
    }
    backdrop(0, 1, 1, false); dimV.target = 1; labelV.target = 1
  }
  function enterSwitcherFromHome() {
    if (mode === "switcher") return
    var list = scanWindows(screenName)      // fresh: the refresh prepare() asked for has arrived by now
    if (!list.length) { if (mode === "homeDrag") sinkBack(); return }
    note("switcher from home")
    sinkDone.stop()
    if (mode !== "homeDrag") { backdrop(1, 0, 1, true); jumpTo(dimV, 0); jumpTo(labelV, 0) }
    cards = list
    cur = list.length - 1
    mode = "switcher"
    backdrop(0, 1, 1, false)
    enterLater.restart()                     // the cards exist (Repeater) on the next turn
  }
  // the cards slide in from the left, beside the screen, the leftmost first (the iPad, Henri 2026-10-28)
  Timer {
    id: enterLater
    interval: 0
    onTriggered: home.guard("enterLater", function () {
      var n = home.cards.length, g = HM.switcherGeo(n, home.areaW, home.areaH, home.cfg)
      home.swX = g.lo
      for (var i = 0; i < n; i++) {
        var o = home.card(i)
        if (!o) continue
        var p = HM.switcherPos(i, n, g.lo, g, home.cfg)
        var col = Math.floor((n - 1 - i) / g.rows), cols = Math.ceil(n / g.rows)
        var order = cols - 1 - col                                    // 0 = the leftmost column
        var fly = home.preset(home.cfg.flyInResponse + order * home.cfg.flyInStagger, home.cfg.flyInDamping)
        o.capture = true
        o.set("x", p.x - home.areaW * home.cfg.enterFromLeft); o.set("y", p.y)
        o.set("s", g.s); o.set("m", 0); o.set("o", 0); o.set("l", 0)
        o.to("x", p.x, fly); o.to("y", p.y, fly); o.to("s", g.s, fly); o.to("o", 1, fly)
      }
      dimV.target = 1; labelV.target = 1
    })
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
    backdrop(1, 0, 1, false); dimV.target = 0; labelV.target = 0
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
    backdrop(1, 0, 1, true); jumpTo(dimV, 0); jumpTo(labelV, 0)
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
    onTriggered: home.guard("openLater", function () {
      var c = home.card(home.cur), e = home.cards[home.cur], r = home.openFrom
      if (!c) return
      c.capture = true
      for (var i = 0; i < home.cards.length; i++) if (i !== home.cur && home.card(i)) home.card(i).set("o", 0)
      c.set("x", r ? r.x + r.w / 2 - home.areaW / 2 : 0); c.set("y", r ? r.y + r.w / 2 - home.areaH / 2 : 0)
      c.set("s", (r ? r.w : home.areaH * home.cfg.splashIcon) / home.areaH); c.set("m", 1); c.set("o", 1); c.set("l", 0)
      c.z = 2
      c.to("x", 0, "smooth"); c.to("y", 0, "smooth"); c.to("s", 1, "smooth"); c.to("m", 0, "smooth")
      backdrop(0, 0, 0, false)
      if (e.address) home.dispatch("hl.dsp.focus({ window = \"address:" + e.address + "\" })", "focuswindow address:" + e.address)
      home.settleWhen(function () {
        if (!c.settled(["x", "y", "s"])) return false
        if (!home.launchedId) return true
        // a launched app: wait for a new window, or give up after launchTimeout
        return home.launchOpened || Date.now() - home.launchStart > home.cfg.launchTimeout
      }, "idle", false)
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
  // the pages follow the finger 1:1, give way past the first and last (rubber band), and settle on
  // a spring that keeps the finger's speed (Spring.from() would drop it)
  property int pageCount: 1
  function pageMoved(dx, t) {
    var x = -page * areaW + dx, lo = -(pageCount - 1) * areaW
    if (x > 0) x = HM.rubber(x, areaW * cfg.pageRubber)
    else if (x < lo) x = lo - HM.rubber(lo - x, areaW * cfg.pageRubber)
    pageV.snap(x)
  }
  function pageReleased(v, pages) {
    pageCount = pages
    var i = Math.round(-pageV.value / Math.max(1, areaW))
    if (Math.abs(v) > cfg.pageFlick) i = page + (v < 0 ? 1 : -1)
    page = Math.max(0, Math.min(pages - 1, i))
    var t = -page * areaW
    pageV.velocity = v
    if (pageV.target === t) pageV.target = t + (pageV.value < t ? -0.01 : 0.01)   // a change, so it runs
    pageV.velocity = v
    pageV.target = t
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
  Component.onCompleted: { wallpaperProbe.running = true; scanApps(); Hyprland.refreshMonitors(); rescan.restart() }
  onModeChanged: if (mode === "ready") wallpaperProbe.running = true

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
          running: home.runningApps
          wallSource: home.wallpaperSource
          wallRect: Qt.rect(0, -per.reserved[1], per.modelData.width, per.modelData.height)
          onTapped: function (id) { home.screenName = per.name; home.guard("openApp", function () { home.openApp(id) }) }
          onPageMoved: function (dx, t) { home.pageCount = pages; home.pageMoved(dx, t) }
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
        // mapped for as long as tablet mode is on: unmapping dropped every texture (wallpaper, blur,
        // snapshots), and building them again stalled the first frames of each gesture ~200 ms
        visible: mine
        readonly property bool shown: home.mode !== "idle" && home.mode !== "home" && home.mode !== "ready"
        WlrLayershell.namespace: "velum-home-overlay"
        // overlay layer: the top layer is hidden under a fullscreen app
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region { item: home.mode === "switcher" ? all : none }
        // the app area's size (a surface being mapped reports 0 for a moment: keep the last real one)
        function measure() { if (width > 0 && height > 0) { home.areaW = width; home.areaH = height } }
        onWidthChanged: if (mine || home.areaW === 0) measure()
        onHeightChanged: if (mine || home.areaH === 0) measure()
        onMineChanged: if (mine) { measure(); home.homeScreenItem = shadowHome; home.coverItem = cover; home.cardRep = cardRepeater }
        Component.onCompleted: if (mine || !home.homeScreenItem) { measure(); home.homeScreenItem = shadowHome; home.coverItem = cover; home.cardRep = cardRepeater }

        Item { id: all; anchors.fill: parent }
        Item { id: none; width: 0; height: 0 }

        Item {
          id: cover
          anchors.fill: parent
          opacity: overlay.shown ? 1 : 0              // clear at rest and until the snapshot is there
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
          // the blurred wallpaper: a small copy blurred once into a cached layer, so it costs nothing per frame
          Item {
            anchors.fill: parent
            opacity: Math.max(0, Math.min(1, blurV.value))
            visible: opacity > 0.002
            layer.enabled: true
            Image {
              id: wallSmall
              anchors.fill: parent
              source: "file://" + home.wallpaperLink + (home.wallpaperTarget ? "?v=" + encodeURIComponent(home.wallpaperTarget) : "")
              fillMode: Image.PreserveAspectCrop
              sourceSize.width: per.modelData.width / home.cfg.blurDownscale
              sourceSize.height: per.modelData.height / home.cfg.blurDownscale
              visible: false
              cache: true
            }
            MultiEffect {
              anchors.fill: parent
              source: wallSmall
              blurEnabled: true
              blur: 1
              blurMax: home.cfg.blurMax
              saturation: home.cfg.blurSaturation
            }
          }
          HomeScreen {
            id: shadowHome
            running: home.runningApps
            wallSource: home.wallpaperSource
            wallRect: Qt.rect(0, -per.reserved[1], per.modelData.width, per.modelData.height)
            x: 0
            y: per.reserved[1]
            width: overlay.width
            height: overlay.height - per.reserved[1] - per.reserved[3]
            apps: home.gridApps
            dockApps: home.dockApps
            recentApps: home.recentApps
            page: home.page
            pageX: pageV.value
            gridOpacity: Math.max(0, Math.min(1, homeV.value))
            gridScale: home.cfg.homeZoom - (home.cfg.homeZoom - 1) * Math.max(0, Math.min(1, homeV.value))
            dockShift: (1 - Math.max(0, Math.min(1, dockV.value))) * (g.dockH + 2 * g.dockGap)
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
            id: cardRepeater
            model: ScriptModel { values: overlay.mine ? home.cards : []; objectProp: "key" }
            Card {
              required property var modelData
              entry: modelData
              areaW: overlay.width
              areaH: overlay.height
              labelOn: Math.max(0, labelV.value)
              capture: true
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
          onPositionChanged: function (m) { home.guard("switcher onPositionChanged", function () {
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
          }) }
          onReleased: function (m) { home.guard("switcher onReleased", function () {
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
          onCanceled: { if (axis === "x") home.layoutSwitcher(home.swX, false) }
        }
      }
    }
  }
}
