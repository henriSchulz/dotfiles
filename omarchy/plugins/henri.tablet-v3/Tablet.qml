import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "file:///home/henri/.local/share/velum/qml/Velum"
import "Gesture.js" as Gesture

// Tablet mode (Theme.touch, settings key "tablet", switched by `tablet-mode`): the home zone
// along the bottom edge of every screen, with the home indicator, and what a finger does there
// (Gesture.js decides):
//   pull up a little          nothing (the dock is no longer pulled from here, 2026-10-28)
//   pull up far / flick        home: in tablet mode the home screen (Home.qml: the app follows the
//                              finger as a card into its icon); elsewhere Mission Control (hyprmc,
//                              or the QML one without it: mc())
//   pull up and pause          App Switcher: in tablet mode Home.qml's cards; elsewhere Mission
//                              Control under the finger (hyprmc.gesture, or "mission-control-gesture:…")
//   slide along the edge       next / previous app (one app per workspace in tablet mode)
//   tap                        the window bar above the indicator (WindowBar.qml)
//   double tap                 back to the previous app
//   press and hold             Spotlight (henri.menu-v3)
//   push down                  the app shrinks to a floating window in the middle, or grows back
// While a finger slides along it the indicator follows and stretches, and the neighbour apps'
// icons show beside it. Over a fullscreen app it fades after indicator.hideAfter; the next finger
// only wakes it. On the cast screen it steps aside while the dock is out (it would lie on it).
// The top edge belongs to henri.bar-v3 (Control Center, Notification Center).
// Beside it, in tablet mode or not: edge fingers from a cast screen (velum-edge, below).
// The zone reserves its height (exclusive zone), so it covers nothing, like a safe area.
// On the cast screen outside tablet mode the indicator is there only for the window bar: no
// reserved zone, input only on the indicator (ipadcast hands a tap on the edge through as a touch;
// pulls arrive as velum-edge, below).
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property var tt: Theme.core.surface.tablet
  readonly property bool active: Theme.touch
  // Mission Control counts touchpad units: gestureDistance (150) for a full open
  readonly property real mcUnits: 150 / tt.switcherTravel

  // for tests: what the last gestures did
  property var log: []
  function note(a) { var l = log.slice(-19); l.push(a); log = l }

  // Under the Lua config a dispatch string is a Lua expression (as in henri.missioncontrol-v3)
  function dispatch(luaExpr, legacy) { Hyprland.dispatch(Hyprland.usingLua ? luaExpr : legacy) }
  function event(text) { dispatch("hl.dsp.event(\"" + text + "\")", "event " + text) }
  // Mission Control is hyprmc (the compositor plugin, ~/Projects/hyprmc) when it is loaded, as for
  // the touchpad swipe and F8 in input.lua / bindings.lua; the QML henri.missioncontrol-v3 only
  // without it. hyprmc opens fully over its `distance` (300) units: finger px here, = switcherTravel.
  function mc(lua, legacy) {
    dispatch("function() if hl.plugin and hl.plugin.hyprmc then hl.plugin.hyprmc." + lua
             + " else hl.dispatch(hl.dsp.event(\"" + legacy + "\")) end end", "event " + legacy)
  }

  function run(actions, screenName) {
    for (var i = 0; i < actions.length; i++) {
      var a = actions[i]
      note(a.do + (a.phase ? ":" + a.phase : "") + (a.step ? ":" + a.step : ""))
      if (root.active && (a.do === "lift" || a.do === "home" || a.do === "switcher")) {
        // tablet mode: the home screen and App Switcher of Home.qml follow the finger
        if (a.do === "lift") {
          if (a.phase === "move") homeCtl.lift(a.up, a.dx)
          else homeCtl.release(a.phase === "cancel" ? "cancel" : "end", a)
        } else if (a.do === "home") homeCtl.release("home", a)
        else if (a.phase === "start") homeCtl.arm()
        else if (a.phase === "update") { if (a.up !== undefined) homeCtl.lift(a.up, a.dx) }
        else homeCtl.release(a.cancelled ? "cancel" : "switcher", a)
      } else if (a.do === "home") {
        mc("toggle()", "mission-control toggle mission")
      } else if (a.do === "switcher") {
        var t = Date.now()
        if (a.phase === "end") mc("gesture(\"end\", 0, " + t + ")", "mission-control-gesture:end:" + (a.cancelled ? 1 : 0) + ":" + t)
        else mc("gesture(\"" + a.phase + "\", " + a.delta.toFixed(3) + ", " + t + ")",
                "mission-control-gesture:" + a.phase + ":" + (a.delta * root.mcUnits).toFixed(3) + ":" + t)
      } else if (a.do === "app") {
        var ws = a.step > 0 ? "m+1" : "m-1"
        dispatch("hl.dsp.focus({ workspace = \"" + ws + "\" })", "workspace " + ws)
      } else if (a.do === "tap") {
        var now = Date.now()
        if (lastTap.screen === screenName && now - lastTap.t < tt.doubleTap) {
          lastTap = ({}); windowBar.openOn = ""; note("doubletap")
          dispatch("hl.dsp.focus({ workspace = \"previous\" })", "workspace previous")
        } else {
          lastTap = { screen: screenName, t: now }
          windowBar.toggle(screenName)
        }
      } else if (a.do === "longpress") {
        windowBar.openOn = ""
        event("menu toggle root")
      } else if (a.do === "down") {
        shrink(screenName)
      } else if (a.do === "slide") {
        slideScreen = a.phase === "end" ? "" : screenName
        slideDx = a.phase === "end" ? 0 : a.dx
      }
    }
  }

  property var lastTap: ({})

  // ---- push down: the active app as a floating window in the middle, and back
  property var shrunk: ({})               // address → true: floated by us, so the next push tiles it again
  function shrink(screenName) {
    var w = windowBar.ipc
    if (!w || !w.address || w.fullscreen > 0) return
    var sel = "address:" + w.address
    if (w.floating) {
      if (!shrunk[w.address]) return      // floating on its own (window mode "macos"): leave it
      var o = Object.assign({}, shrunk); delete o[w.address]; shrunk = o
      dispatch("hl.dsp.window.float({ action = \"disable\", window = \"" + sel + "\" })", "settiled " + sel)
      return
    }
    var sc = null, all = Quickshell.screens
    for (var i = 0; i < all.length; i++) if (all[i].name === screenName) sc = all[i]
    if (!sc) return
    var bw = Math.round(sc.width * tt.floatShare), bh = Math.round(sc.height * tt.floatShare)
    var bx = Math.round(sc.x + (sc.width - bw) / 2), by = Math.round(sc.y + (sc.height - bh) / 2)
    var n = Object.assign({}, shrunk); n[w.address] = true; shrunk = n
    dispatch("function() hl.dispatch(hl.dsp.window.float({ action = \"enable\", window = \"" + sel + "\" }))"
             + " hl.dispatch(hl.dsp.window.resize({ x = " + bw + ", y = " + bh + ", window = \"" + sel + "\" }))"
             + " hl.dispatch(hl.dsp.window.move({ x = " + bx + ", y = " + by + ", window = \"" + sel + "\" })) end",
             "setfloating " + sel)
  }

  // ---- a finger sliding along the indicator
  property string slideScreen: ""
  property real slideDx: 0
  property var neighbours: ({ prev: "", next: "" })   // icon paths of the apps before / after
  onSlideScreenChanged: if (slideScreen !== "") neighbours = neighboursOn(slideScreen)
  function appIcon(cls) {
    if (!cls) return ""
    var e = null
    try { e = DesktopEntries.byId(cls) || DesktopEntries.heuristicLookup(cls) } catch (err) {}
    return Quickshell.iconPath(e && e.icon ? e.icon : cls, true)
  }
  function neighboursOn(screenName) {
    var m = null, mons = Hyprland.monitors.values
    for (var i = 0; i < mons.length; i++) if (mons[i].name === screenName) m = mons[i]
    if (!m || !m.activeWorkspace) return { prev: "", next: "" }
    var list = Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor && w.monitor.id === m.id).sort((a, b) => a.id - b.id)
    var at = list.findIndex(w => w.id === m.activeWorkspace.id)
    function app(ws) {
      if (!ws) return ""
      var tl = Hyprland.toplevels.values
      for (var j = 0; j < tl.length; j++) { var o = tl[j].lastIpcObject; if (o && o.workspace && o.workspace.id === ws.id) return root.appIcon(o.class) }
      return ""
    }
    return { prev: at > 0 ? app(list[at - 1]) : "", next: at >= 0 ? app(list[at + 1]) : "" }
  }

  // ---- asleep over a fullscreen app (a video): the indicator fades, the next finger only wakes it
  readonly property string fullscreenOn: {
    var w = windowBar.ipc
    if (!w || w.fullscreen !== 2) return ""
    var mons = Hyprland.monitors.values
    for (var i = 0; i < mons.length; i++) if (mons[i].id === w.monitor) return mons[i].name
    return ""
  }
  property bool asleep: false
  // the home indicator and its gesture switched off for a while (IPC pauseHome, e.g. while trying
  // lab/web/home.html on the cast screen); the top edge stays. Not kept across a shell restart.
  property bool homePaused: false
  onFullscreenOnChanged: wake()
  function wake() { asleep = false; if (fullscreenOn !== "") sleepTimer.restart(); else sleepTimer.stop() }
  Timer { id: sleepTimer; interval: root.tt.indicator.hideAfter; onTriggered: root.asleep = root.fullscreenOn !== "" }
  function sleepingOn(screenName) { return asleep && fullscreenOn === screenName }

  Variants {
    model: root.homePaused ? [] : root.active ? Quickshell.screens : Array.from(Quickshell.screens).filter(s => s.name === windowBar.castScreen)

    PanelWindow {
      id: zone
      required property var modelData
      screen: modelData
      anchors { bottom: true; left: true; right: true }
      implicitHeight: root.tt.homeZone
      exclusionMode: root.active ? ExclusionMode.Normal : ExclusionMode.Ignore
      exclusiveZone: root.active ? root.tt.homeZone : 0
      // on the cast screen nothing takes a finger while the dock is out: it lies over the dock's icons
      mask: Region { item: root.active ? zoneArea : VGestures.isOut("dock", zone.modelData.name) ? noArea : indicatorArea }
      color: "transparent"
      WlrLayershell.namespace: "velum-home-indicator"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      property var gesture: Gesture.create(root.tt)
      property bool pressed: false

      property bool swallow: false        // this finger only woke the indicator
      readonly property bool sliding: root.slideScreen === modelData.name
      readonly property real slideMax: root.tt.slideMax
      // asleep over fullscreen, or (cast screen only: no room below the dock) the dock is out
      readonly property bool away: root.sleepingOn(modelData.name) || (!root.active && VGestures.isOut("dock", modelData.name))
      Spring { id: shift; preset: Theme.spring(zone.sliding ? "interactive" : "snappy"); reduced: Theme.reduceMotion
               target: zone.sliding ? Math.max(-zone.slideMax, Math.min(zone.slideMax, root.slideDx * root.tt.slideFollow)) : 0 }
      Spring { id: stretch; preset: Theme.spring(zone.sliding ? "interactive" : "snappy"); reduced: Theme.reduceMotion
               target: zone.sliding ? Math.min(zone.slideMax, Math.abs(root.slideDx) * root.tt.slideStretch) : 0 }

      // the neighbour apps beside the indicator while a finger slides (the one it goes to brighter)
      Repeater {
        model: ["prev", "next"]
        Image {
          required property string modelData
          readonly property bool toward: modelData === "next" ? root.slideDx < 0 : root.slideDx > 0
          source: root.neighbours[modelData] || ""
          visible: source != ""
          width: root.tt.neighbour.size; height: width
          sourceSize.width: width * 2; sourceSize.height: height * 2
          anchors.verticalCenter: parent.verticalCenter
          // beside the indicator's ends as they move and stretch
          x: modelData === "next" ? indicator.x + indicator.width + root.tt.neighbour.gap : indicator.x - root.tt.neighbour.gap - width
          opacity: zone.sliding ? (toward ? Math.min(1, Math.abs(root.slideDx) / root.tt.slideCommit) : root.tt.neighbour.rest) : 0
          Behavior on opacity { enabled: !zone.sliding; NumberAnimation { duration: Theme.exit(Theme.dur("fast")) } }
        }
      }

      Rectangle {
        id: indicator
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: shift.value
        width: root.tt.indicator.width + stretch.value
        height: root.tt.indicator.height
        radius: height / 2
        y: (zone.height - height) / 2 - lift.value
        opacity: zone.away ? root.tt.indicator.asleep : 1
        Behavior on opacity { NumberAnimation { duration: zone.away ? Theme.dur("slow") : Theme.dur("fast") } }
        color: Theme.dark ? root.tt.indicator.onDark : root.tt.indicator.onLight
        Rectangle {
          z: -1
          anchors.fill: parent
          anchors.margins: -root.tt.indicator.halo
          radius: height / 2
          color: Theme.dark ? root.tt.indicator.haloOnDark : root.tt.indicator.haloOnLight
        }
        Spring { id: lift; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: zone.pressed ? root.tt.indicator.lift : 0 }
      }

      // One finger (touch reaches a MouseArea as a synthesized mouse; a pointer works the same,
      // which is how the rig tests it). Coordinates stay in the zone; only differences count.
      // what takes the finger: the whole zone, or (cast screen only) the indicator with room around it
      Item { id: zoneArea; anchors.fill: parent }
      Item { id: noArea; width: 0; height: 0 }
      Item { id: indicatorArea; anchors.centerIn: parent; width: root.tt.indicator.width + 2 * root.tt.slop; height: parent.height }
      MouseArea {
        anchors.fill: root.active ? zoneArea : indicatorArea
        preventStealing: true
        onPressed: function (m) {
          zone.swallow = root.sleepingOn(zone.screen.name)
          root.wake()
          if (zone.swallow) return
          zone.pressed = true
          homeCtl.zoneFinger = true
          if (root.active) homeCtl.prepare(zone.screen.name)
          root.run(zone.gesture.down(Date.now(), m.x, m.y), zone.screen.name); ticker.start()
        }
        onPositionChanged: function (m) { if (zone.pressed) root.run(zone.gesture.move(Date.now(), m.x, m.y), zone.screen.name) }
        onReleased: function (m) { homeCtl.zoneFinger = false; if (zone.swallow) { zone.swallow = false; return } ticker.stop(); zone.pressed = false; root.run(zone.gesture.up(Date.now(), m.x, m.y), zone.screen.name) }
        onCanceled: { homeCtl.zoneFinger = false; if (zone.swallow) { zone.swallow = false; return } ticker.stop(); zone.pressed = false; root.run(zone.gesture.cancel(), zone.screen.name) }
      }
      // a resting finger sends no events: the pause that opens the App Switcher is seen here
      Timer {
        id: ticker
        interval: Theme.core.surface.tablet.holdTime / 4
        repeat: true
        onTriggered: root.run(zone.gesture.tick(Date.now()), zone.screen.name)
      }
    }
  }

  // ---- Edge fingers from a cast screen (ipadcast), in tablet mode or not. The server holds back a
  // finger that lands on the top or bottom edge of the picture and, once it is an edge gesture,
  // hands it in as the custom event
  //   "velum-edge <screen> top|bottom down|move|up|cancel <x> <y>"   (logical px of that screen)
  // so the surfaces follow it as they follow a finger in tablet mode: the top pulls Notification
  // Center, Control Center or only its workspace miniatures (surface.tablet.cast), the bottom is
  // the home zone's gesture (Gesture.js). Only numbers and fixed words are taken from it; a forged
  // event can at most pull a surface.
  property var castTop: null       // { surface, screen, y0, samples: [ms, travel] }
  property var castBottom: null    // { gesture, screen }
  function castSurface(screenName, x) {
    var w = 0, all = Quickshell.screens
    for (var i = 0; i < all.length; i++) if (all[i].name === screenName) w = all[i].width
    var z = VGestures.zoneAt(screenName, x)   // the menu-bar item above the finger (VPullZone)
    if (z !== "") return z
    var c = root.tt.cast, u = w > 0 ? x / w : c.spacesFrom
    return u < c.notificationsShare ? "notifications" : u >= c.spacesFrom && u < c.spacesTo ? "spaces" : "controlCenter"
  }
  function castEdge(screenName, edge, phase, x, y) {
    var t = Date.now()
    if (edge === "top") {
      if (phase === "down") {
        root.castTop = { surface: castSurface(screenName, x), screen: screenName, y0: y, samples: [[t, 0]] }
        note("cast:top:" + root.castTop.surface)
        return
      }
      var p = root.castTop
      if (!p) return
      if (phase === "cancel") { root.castTop = null; VGestures.pull(p.surface, p.screen, "cancel", 0, 0); return }
      var travel = y - p.y0, list = p.samples.concat([[t, travel]])
      while (list.length > 2 && t - list[0][0] > root.tt.sampleWindow) list.shift()
      p.samples = list
      if (phase === "move") { VGestures.pull(p.surface, p.screen, "move", travel, 0); return }
      var a = list[0], b = list[list.length - 1]
      root.castTop = null
      VGestures.pull(p.surface, p.screen, "end", travel, b[0] > a[0] ? (b[1] - a[1]) * 1000 / (b[0] - a[0]) : 0)
    } else if (edge === "bottom") {
      if (root.homePaused) { root.castBottom = null; castTicker.stop(); return }
      if (phase === "down") {
        var sleeping = root.sleepingOn(screenName)
        root.wake()
        if (sleeping) return               // this finger only wakes the indicator
        root.castBottom = { gesture: Gesture.create(root.tt), screen: screenName }
        if (root.active) homeCtl.prepare(screenName)
        root.run(root.castBottom.gesture.down(t, x, y), screenName)
        castTicker.start()
        return
      }
      var q = root.castBottom
      if (!q) return
      if (phase === "move") { root.run(q.gesture.move(t, x, y), q.screen); return }
      castTicker.stop()
      root.castBottom = null
      root.run(phase === "up" ? q.gesture.up(t, x, y) : q.gesture.cancel(), q.screen)
    }
  }
  // a resting finger sends no events (as in the home zone)
  Timer {
    id: castTicker
    interval: Theme.core.surface.tablet.holdTime / 4
    repeat: true
    onTriggered: if (root.castBottom) root.run(root.castBottom.gesture.tick(Date.now()), root.castBottom.screen)
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "custom") return
      var d = String(event.data)
      if (d.indexOf("velum-edge ") !== 0 || d.length > 96) return
      var f = d.split(" "), x = Number(f[4]), y = Number(f[5])
      if (f.length !== 6 || !isFinite(x) || !isFinite(y)) return
      if ((f[2] !== "top" && f[2] !== "bottom") || ["down", "move", "up", "cancel"].indexOf(f[3]) < 0) return
      root.castEdge(f[1], f[2], f[3], x, y)
    }
  }

  // tablet mode's home screen, home gesture and App Switcher
  Home { id: homeCtl; active: root.active; dispatch: root.dispatch }

  // keyboard, fullscreen and close for the active window, above the indicator (tablet mode, the cast screen)
  WindowBar { id: windowBar; tabletMode: root.active; dispatch: root.dispatch }

  IpcHandler {
    target: "henri.tablet"
    function state(): string { return JSON.stringify({ active: root.active, screens: root.active ? Quickshell.screens.length : 0, log: root.log, castScreen: windowBar.castScreen, window: windowBar.ipc ? windowBar.ipc.class : "", windowBarOpen: windowBar.open }) }
    function clearLog(): string { root.log = []; homeCtl.log = []; return "ok" }
    function home(): string { return JSON.stringify({ empty: homeCtl.emptyOn(homeCtl.screenName), mode: homeCtl.mode, screen: homeCtl.screenName, cards: homeCtl.cards.map(c => c.appId), at: homeCtl.cards.map((c, i) => { var k = homeCtl.card(i); return k ? [Math.round(k.px), Math.round(k.py), +k.ps.toFixed(2), +k.po.toFixed(2)] : null }), zoneFinger: homeCtl.zoneFinger,  cur: homeCtl.cur, armed: homeCtl.armed, fromHome: homeCtl.fromHome, area: [homeCtl.areaW, homeCtl.areaH], apps: homeCtl.gridApps.length, dock: homeCtl.dockApps.map(a => a.id), recent: homeCtl.recentApps.map(a => a.id), page: homeCtl.page, log: homeCtl.log }) }
    function homeOpen(id: string): string { homeCtl.openApp(id); return homeCtl.mode }
    function pauseHome(on: string): string { root.homePaused = on === "toggle" ? !root.homePaused : on === "on" || on === "true"; return String(root.homePaused) }
    function tap(screen: string): string { windowBar.toggle(screen); return windowBar.openOn }
    function view(): string { return JSON.stringify({ asleep: root.asleep, fullscreenOn: root.fullscreenOn, slideScreen: root.slideScreen, neighbours: root.neighbours, dockOut: VGestures.out, shrunk: Object.keys(root.shrunk).length, dictateOn: windowBar.dictateOn, voxState: windowBar.voxState, entered: windowBar.entered, zones: VGestures.zones }) }
  }
}
