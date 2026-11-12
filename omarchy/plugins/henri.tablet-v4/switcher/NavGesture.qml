import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"
import "Nav.js" as Nav

// Android gesture navigation along the bottom edge (lab/mui-material src/Launcher.jsx): the handle,
// and a finger from the strip under it. Pushed up, the App Switcher comes with it from the first
// pixels (`pull` 0 … 1 over nav.reach of the screen's height) and the handle rises a little; let go
// higher than nav.travel the switcher settles open, lower it sinks away; a quick flick up (faster than
// nav.homeFlick) goes home instead — only when there is a way home (`wayHome`: something open,
// another page), else it would only flash the switcher and take it away again.
//
// API (the owner wires it to MaterialSwitcher; integration comes later):
//   anchors { left; right; bottom }: <the screen>   its height is nav.zone (the strip that starts it)
//   screenHeight: real      the screen's height (reach is a share of it); default: the parent's
//   wayHome: bool           a flick may go home
//   dragging (read only)    a finger drives it          → MaterialSwitcher.dragging
//   pull (read only)        how far the switcher is there → MaterialSwitcher.progress while dragging
//   signal openSwitcher()   let go high enough: set the switcher's progress to 1
//   signal home()           a flick with a way home: close what is open, go to the first page
//   signal sank()           let go low: the switcher's progress back to 0
//   begin(y) / update(y) / end() / abort()   a finger the owner routes itself (edge socket, rig), y in
//                           screen coordinates; otherwise its own MouseArea + MultiPointTouchArea
//   handleVisible: bool     show the handle (default true)
Item {
  id: nav

  property real screenHeight: parent ? parent.height : 0
  property bool wayHome: false
  property bool handleVisible: true
  readonly property bool dragging: g !== null
  readonly property real pull: Nav.pull(travel, screenHeight, cfg.reach)
  property real travel: 0
  property string last: ""           // the last decision, for tests

  signal openSwitcher()
  signal home()
  signal sank()

  readonly property var cfg: Theme.core.surface.material.switcher.nav
  readonly property var sw: Theme.core.surface.material.switcher
  height: cfg.zone

  property var g: null
  function begin(y) {
    g = { y0: y, samples: [[Date.now(), 0, y]] }
    travel = 0
    rise.snap(rise.value)
  }
  function update(y) {
    if (!g) return
    var t = Date.now()
    g.samples = Nav.trim(g.samples.concat([[t, 0, y]]), t, sw.sampleWindow)
    travel = Math.max(0, g.y0 - y)
    rise.snap(Math.min(travel, cfg.travel) * cfg.handleRise)
  }
  function end() {
    var d = g
    if (!d) return
    var v = Nav.velocity(d.samples, Date.now(), sw.sampleWindow)
    var what = Nav.decide(travel, v.y, wayHome, cfg)
    g = null
    travel = 0
    rise.from(rise.value)
    last = what
    if (what === "home") home()
    else if (what === "switcher") openSwitcher()
    else sank()
  }
  function abort() {
    if (!g) return
    g = null
    travel = 0
    rise.from(rise.value)
    last = "back"
    sank()
  }

  // the handle rises with the finger and drops back on a spring
  Spring { id: rise; preset: nav.cfg.handleBack; reduced: Theme.reduceMotion; target: 0 }
  Item {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: nav.cfg.handleWidth
    height: nav.cfg.handleHeight
    visible: nav.handleVisible
    transform: Translate { y: -rise.value }
    VShadow {
      layers: [{ color: nav.cfg.handleShade, offsetX: 0, offsetY: 0, blur: nav.cfg.handleShadeBlur, spread: 0 }]
      radius: nav.cfg.handleHeight / 2
    }
    Rectangle { anchors.fill: parent; radius: height / 2; color: nav.cfg.handleInk }
  }

  // screen coordinates: the strip's y + the finger's y in it
  function sy(y) { return nav.y + y }
  MultiPointTouchArea {
    anchors.fill: parent
    maximumTouchPoints: 1
    mouseEnabled: false
    onPressed: function (pts) { nav.begin(nav.sy(pts[0].y)) }
    onUpdated: function (pts) { nav.update(nav.sy(pts[0].y)) }
    onReleased: function (pts) { nav.end() }
    onCanceled: nav.abort()
  }
  MouseArea {
    anchors.fill: parent
    preventStealing: true
    onPressed: function (m) { nav.begin(nav.sy(m.y)) }
    onPositionChanged: function (m) { nav.update(nav.sy(m.y)) }
    onReleased: function (m) { nav.end() }
    onCanceled: nav.abort()
  }
}
