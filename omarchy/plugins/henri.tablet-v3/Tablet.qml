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
//   pull up a little          the dock follows (VGestures "dock"; henri.dock-v3)
//   pull up far / flick        home: Mission Control (hyprmc, or the QML one without it: mc())
//   pull up and pause          App Switcher: Mission Control under the finger (hyprmc.gesture,
//                              or the QML one's "mission-control-gesture:…" events)
//   slide along the edge       next / previous app (one app per workspace in tablet mode)
//   tap                        the window bar above the indicator (WindowBar.qml)
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
      if (a.do === "dock") {
        VGestures.pull("dock", screenName, a.phase, a.travel || 0, a.velocity || 0)
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
        windowBar.toggle(screenName)
      }
    }
  }

  Variants {
    model: root.active ? Quickshell.screens : Array.from(Quickshell.screens).filter(s => s.name === windowBar.castScreen)

    PanelWindow {
      id: zone
      required property var modelData
      screen: modelData
      anchors { bottom: true; left: true; right: true }
      implicitHeight: root.tt.homeZone
      exclusionMode: root.active ? ExclusionMode.Normal : ExclusionMode.Ignore
      exclusiveZone: root.active ? root.tt.homeZone : 0
      mask: Region { item: root.active ? zoneArea : indicatorArea }
      color: "transparent"
      WlrLayershell.namespace: "velum-home-indicator"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      property var gesture: Gesture.create(root.tt)
      property bool pressed: false

      Rectangle {
        id: indicator
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.tt.indicator.width
        height: root.tt.indicator.height
        radius: height / 2
        y: (zone.height - height) / 2 - lift.value
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
      Item { id: indicatorArea; anchors.centerIn: parent; width: root.tt.indicator.width + 2 * root.tt.slop; height: parent.height }
      MouseArea {
        anchors.fill: root.active ? zoneArea : indicatorArea
        preventStealing: true
        onPressed: function (m) { zone.pressed = true; root.run(zone.gesture.down(Date.now(), m.x, m.y), zone.screen.name); ticker.start() }
        onPositionChanged: function (m) { if (zone.pressed) root.run(zone.gesture.move(Date.now(), m.x, m.y), zone.screen.name) }
        onReleased: function (m) { ticker.stop(); zone.pressed = false; root.run(zone.gesture.up(Date.now(), m.x, m.y), zone.screen.name) }
        onCanceled: { ticker.stop(); zone.pressed = false; root.run(zone.gesture.cancel(), zone.screen.name) }
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
      if (phase === "down") {
        root.castBottom = { gesture: Gesture.create(root.tt), screen: screenName }
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

  // keyboard, fullscreen and close for the active window, above the indicator (tablet mode, the cast screen)
  WindowBar { id: windowBar; tabletMode: root.active; dispatch: root.dispatch }

  IpcHandler {
    target: "henri.tablet"
    function state(): string { return JSON.stringify({ active: root.active, screens: root.active ? Quickshell.screens.length : 0, log: root.log, castScreen: windowBar.castScreen, window: windowBar.ipc ? windowBar.ipc.class : "", windowBarOpen: windowBar.open }) }
    function clearLog(): string { root.log = []; return "ok" }
    function tap(screen: string): string { windowBar.toggle(screen); return windowBar.openOn }
  }
}
