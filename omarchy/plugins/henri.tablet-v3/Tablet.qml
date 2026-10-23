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
//   pull up far / flick        home: Launchpad (custom event "launchpad open")
//   pull up and pause          App Switcher: Mission Control under the finger (the
//                              "mission-control-gesture:…" events its touchpad swipe uses)
//   slide along the edge       next / previous app (one app per workspace in tablet mode)
// The top edge belongs to henri.bar-v3 (Control Center, Notification Center).
// The zone reserves its height (exclusive zone), so it covers nothing, like a safe area.
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

  function run(actions, screenName) {
    for (var i = 0; i < actions.length; i++) {
      var a = actions[i]
      note(a.do + (a.phase ? ":" + a.phase : "") + (a.step ? ":" + a.step : ""))
      if (a.do === "dock") {
        VGestures.pull("dock", screenName, a.phase, a.travel || 0, a.velocity || 0)
      } else if (a.do === "home") {
        event("launchpad open")
      } else if (a.do === "switcher") {
        var t = Date.now()
        if (a.phase === "end") event("mission-control-gesture:end:" + (a.cancelled ? 1 : 0) + ":" + t)
        else event("mission-control-gesture:" + a.phase + ":" + (a.delta * root.mcUnits).toFixed(3) + ":" + t)
      } else if (a.do === "app") {
        var ws = a.step > 0 ? "m+1" : "m-1"
        dispatch("hl.dsp.focus({ workspace = \"" + ws + "\" })", "workspace " + ws)
      }
    }
  }

  Variants {
    model: root.active ? Quickshell.screens : []

    PanelWindow {
      id: zone
      required property var modelData
      screen: modelData
      anchors { bottom: true; left: true; right: true }
      implicitHeight: root.tt.homeZone
      exclusionMode: ExclusionMode.Normal
      exclusiveZone: root.tt.homeZone
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
      MouseArea {
        anchors.fill: parent
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

  IpcHandler {
    target: "henri.tablet"
    function state(): string { return JSON.stringify({ active: root.active, screens: root.active ? Quickshell.screens.length : 0, log: root.log }) }
    function clearLog(): string { root.log = []; return "ok" }
  }
}
