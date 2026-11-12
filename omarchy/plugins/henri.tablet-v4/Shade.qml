import QtQuick
import Quickshell
import Quickshell.Wayland
import "file:///home/henri/.local/share/velum/qml/Velum"
import "qs" as QS

// Quick Settings from the top edge in tablet mode (henri.tablet-v4, phase 4 of docs/TABLET-V4-PLAN.md):
// the owner of qs/QuickSettings.qml. In tablet mode the top edge's right share pulls "controlCenter"
// (bar-v3's DragHandler, a cast screen's top edge through velum-edge / Tablet.qml castSurface); this shade
// follows those pulls and tells control-center-v3 to leave them alone with VGestures' existing out-map:
// VGestures.setOut("tabletShade", screen, true) while tablet mode is on (FullCenter ignores a pull on a
// screen where isOut("tabletShade", screen)). The Velum module is unchanged; without henri.tablet-v4 nobody
// sets it and v3 behaves as before. The tap on the Control Center symbol still opens FullCenter.
//
// One overlay window per screen, mapped only while its shade shows (pulled, open or moving), taking the
// keyboard once the finger is off it (Escape closes). One QsBackend for all: it polls only while a shade
// shows, and runs commands only in the real shell (`live`; a rig or test logs them as dry runs).
//
// As in the lab: in tablet mode the Material status bar (qs/StatusBar.qml) replaces the menu bar. bar-v3 is
// hidden through Omarchy's bar-off toggle (only if Henri had not hidden it himself — a marker in
// $XDG_RUNTIME_DIR says v4 did, so tablet mode off / v4 unloading brings it back), and the status bar stands
// on every screen in its own top-layer window with an exclusive zone (apps sit below it, as on Android); a
// pull down from it drives the shade like the top edge does. A rig never touches the bar-off toggle.
Item {
  id: sh
  property bool active: false
  property bool live: false
  property var homeCtl: null
  readonly property string wallpaper: homeCtl ? homeCtl.wallpaperLink : ""
  property var shades: ({})                 // screen name → its QuickSettings
  readonly property bool anyShown: { for (var k in shades) if (shades[k].shown) return true; return false }
  // for tests: the last things that happened
  property var log: []
  function note(s) { log = log.concat([s]).slice(-30) }   // lint-ok: the test log keeps the last 30

  // which screens this shade claims the Control Center pull on (VGestures.setOut, read by control-center-v3)
  property var claimed: []
  function claim() {
    var want = active ? Object.keys(shades) : []
    for (var i = 0; i < claimed.length; i++) if (want.indexOf(claimed[i]) < 0) VGestures.setOut("tabletShade", claimed[i], false)
    for (var j = 0; j < want.length; j++) VGestures.setOut("tabletShade", want[j], true)
    claimed = want
  }
  onActiveChanged: { claim(); syncBar(); if (!active) for (var k in shades) shades[k].close() }   // tablet mode off: closed
  onShadesChanged: claim()
  Component.onDestruction: {
    for (var i = 0; i < claimed.length; i++) VGestures.setOut("tabletShade", claimed[i], false)
    if (active) { active = false; syncBar() }   // v4 goes away: the menu bar comes back if v4 hid it
  }

  // the menu bar off while tablet mode is on (bar-off toggle + our marker), back on when it ends
  property bool inRig: (Quickshell.env("VELUM_SHELL_RIG") || "") !== ""
  readonly property string barMark: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/velum-tablet-v4-bar-hidden"
  function syncBar() {
    if (inRig) { note(active ? "bar hide (rig: skipped)" : "bar show (rig: skipped)"); return }
    var t = (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/toggles/bar-off"
    var cmd = active
      ? "[ -e '" + t + "' ] || { omarchy-toggle-bar on >/dev/null 2>&1 && touch '" + barMark + "'; }"
      : "[ -e '" + barMark + "' ] && { rm -f '" + barMark + "'; omarchy-toggle-bar off >/dev/null 2>&1; }; true"
    Quickshell.execDetached(["bash", "-c", cmd])
  }
  Component.onCompleted: syncBar()

  // never the owner: it only writes the appearance (the Dark theme tile) through the file
  VelumSettings { id: velum; priority: -2 }
  QS.QsBackend { id: qsb; live: sh.live; active: sh.anyShown; velum: velum }
  readonly property alias backend: qsb

  Connections {
    target: VGestures
    function onPull(surface, screenName, phase, travel, velocity) {
      if (surface !== "controlCenter" || !sh.active) return
      var s = sh.shades[screenName]
      if (!s) return
      if (phase === "move") {
        if (!s.dragging) { s.dragProgress = 0; s.dragging = true; sh.note("pull") }
        s.dragProgress = Math.max(0, travel) / Math.max(1, s.travel)
        return
      }
      if (!s.dragging) return
      if (phase === "end") { s.release(velocity); sh.note("release " + Math.round(velocity)) }
      else sh.note("cancel")                       // cancel / handover: back to where it was
      s.dragging = false
    }
  }
  function open(screenName) { var s = shades[screenName]; if (s && active) s.open(); return !!s }
  function close(screenName) { var s = shades[screenName]; if (s) s.close(); return !!s }
  function probe(screenName) {
    var s = shades[screenName]
    if (!s) return null
    return { progress: +s.progress.toFixed(3), shown: s.shown, open: s.wantOpen, dragging: s.dragging, tab: s.tab,
             detail: s.detail, editing: s.editing, confirm: s.pendingAction !== null, live: qsb.live, castOverWifi: qsb.castOverWifi,
             focus: s.activeFocus, mapped: s.mapped,
             claimed: VGestures.isOut("tabletShade", screenName), log: sh.log, commands: qsb.log.map(function (e) { return (e.live ? "LIVE " : "dry ") + e.argv.join(" ") }) }
  }

  // for tests: the centre of the visible item named NAME (objectName: tile-wifi, power-off, btn-edit …) in
  // screen coordinates (the window covers the screen), or null
  function pointOf(screenName, name) {
    var s = shades[screenName]
    if (!s) return null
    function find(it) {
      if (!it || !it.visible) return null
      if (it.objectName === name && it.width > 0) return it
      var kids = it.children || []
      for (var i = 0; i < kids.length; i++) { var f = find(kids[i]); if (f) return f }
      if (it.contentItem && kids.indexOf(it.contentItem) < 0) return find(it.contentItem)
      return null
    }
    var f = find(s)
    if (!f) return null
    var q = f.mapToItem(s, f.width / 2, f.height / 2)
    return { x: Math.round(q.x), y: Math.round(q.y) }
  }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      visible: sh.active && shade.shown
      WlrLayershell.namespace: "velum-tablet-shade"
      WlrLayershell.layer: WlrLayer.Overlay
      // Escape once it stands; never under the finger that still pulls (taking the keyboard ends its grab)
      WlrLayershell.keyboardFocus: shade.shown && !shade.dragging ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      readonly property bool menuBar: { var h = sh.homeCtl ? sh.homeCtl.screenHomes[modelData.name] : null; return !!h && h.top() > 0 }

      QS.QuickSettings {
        id: shade
        anchors.fill: parent
        backend: qsb
        wallpaper: sh.wallpaper
        topInset: 0
        readonly property bool mapped: win.visible
        onOpened: sh.note("opened")
        onClosed: sh.note("closed")
        // a held tile without a page of its own (dnd, dark, night, airplane, rotate): noted only for now
        onTileLongPressed: function (key) { sh.note("long " + key) }
        Component.onCompleted: { var m = Object.assign({}, sh.shades); m[win.modelData.name] = shade; sh.shades = m }
        Component.onDestruction: { var m = Object.assign({}, sh.shades); if (m[win.modelData.name] === shade) delete m[win.modelData.name]; sh.shades = m }
      }
    }
  }

  // the status bar in place of the menu bar, on every screen while tablet mode is on
  Variants {
    model: sh.active ? Quickshell.screens : []
    PanelWindow {
      id: bar
      required property var modelData
      screen: modelData
      anchors { top: true; left: true; right: true }
      implicitHeight: status.implicitHeight
      exclusiveZone: status.implicitHeight
      color: "transparent"
      WlrLayershell.namespace: "velum-tablet-statusbar"
      WlrLayershell.layer: WlrLayer.Top
      QS.StatusBar { id: status; width: parent.width; backend: qsb; shown: true }
      // a pull down from the bar (a finger or the pointer) goes the same way as the top edge
      MouseArea {
        anchors.fill: parent
        property real y0: 0
        property var samples: []
        function pull(phase, y, v) { VGestures.pull("controlCenter", bar.modelData.name, phase, y - y0, v) }
        onPressed: function (m) { y0 = m.y; samples = [[Date.now(), m.y]] }
        onPositionChanged: function (m) {
          var t = Date.now(), list = samples.concat([[t, m.y]])
          while (list.length > 2 && t - list[0][0] > Theme.core.surface.tablet.sampleWindow) list.shift()
          samples = list
          pull("move", m.y, 0)
        }
        onReleased: function (m) {
          var a = samples[0], b = samples[samples.length - 1]
          pull("end", m.y, b[0] > a[0] ? (b[1] - a[1]) / (b[0] - a[0]) * 1000 : 0)   // px/s
        }
        onCanceled: VGestures.pull("controlCenter", bar.modelData.name, "cancel", 0, 0)
      }
    }
  }
}
