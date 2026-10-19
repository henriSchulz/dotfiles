import QtQuick
import Quickshell
import Quickshell.Hyprland
import "file:///home/henri/.local/share/velum/qml/Velum"

// Enter/exit for the Dock's menus, stacks and settings (after henri-ui Reveal,
// on Velum's motion): kind "menu" opens with no transition (macOS) and fades
// out on menu.close; "popover"/"panel" fade in on popover.in and grow from
// popover.fromScale with the popover spring, closing faster (exit) toward
// scale exitTo; "toast" slides in by offset.toast. Interrupting reverses.
// Esc and a click outside emit dismissRequested() — the caller closes it.
// Same-window outside clicks are swallowed; other windows via HyprlandFocusGrab.
FocusScope {
  id: root

  property bool open: false
  property string kind: "menu"
  property int origin: Item.Top
  property real fromX: 0
  property real fromY: kind === "toast" ? -Theme.core.motion.offset.toast : 0

  readonly property bool shown: visible
  readonly property bool settled: _shownOpen && opacity >= 1

  // opening waits for the first presented frame (a window that is only just mapping
  // would swallow the animation); fallback after firstFrameTimeout
  readonly property int firstFrameTimeout: Theme.dur("slower")
  property bool _shownOpen: false
  property bool _awaitingFrame: false
  function _present() {
    _awaitingFrame = false
    firstFrameFallback.stop()
    _shownOpen = open
  }
  signal closed()
  signal dismissRequested()
  property bool closeOnEscape: true
  property bool animated: true
  property bool closeOnOutsideClick: true
  property var insideWindows: []

  function containsScenePoint(item, x, y) {
    var p = item.mapToItem(root, x, y)
    return p.x >= 0 && p.y >= 0 && p.x < root.width && p.y < root.height
  }

  default property alias content: holder.data

  readonly property bool instantIn: kind === "menu"
  readonly property real fromScale: kind === "menu" || kind === "toast" ? 1 : Theme.scale("popoverFrom")
  readonly property real toExitScale: kind === "popover" || kind === "panel" ? Theme.scale("exitTo") : 1
  readonly property var preset: Theme.motion("popover.scaleSpring")
  readonly property int enterDuration: instantIn ? 0 : Theme.transitionMs("popover.in")
  readonly property int exitDuration: kind === "menu" ? Theme.exit(Theme.transitionMs("menu.close")) : Theme.exit(Theme.transitionMs("popover.in"))

  implicitWidth: holder.childrenRect.width
  implicitHeight: holder.childrenRect.height
  visible: open || opacity > 0.001
  opacity: _shownOpen ? 1 : 0
  transformOrigin: origin
  scale: Theme.reduceMotion ? 1 : scaleS.value
  transform: Translate {
    x: Theme.reduceMotion ? 0 : offX.value
    y: Theme.reduceMotion ? 0 : offY.value
  }

  Behavior on opacity {
    enabled: root.animated
    NumberAnimation {
      duration: root._shownOpen ? root.enterDuration : root.exitDuration
      easing.type: Easing.BezierSpline
      easing.bezierCurve: root._shownOpen ? Theme.motion("popover.in").curve : Theme.motion("menu.close").curve
    }
  }

  SpringValue { id: scaleS; preset: root.preset; to: root._shownOpen ? 1 : root.toExitScale }
  SpringValue { id: offX; preset: root.preset; epsilon: 0.1; to: root._shownOpen ? 0 : root.fromX }
  SpringValue { id: offY; preset: root.preset; epsilon: 0.1; to: root._shownOpen ? 0 : root.fromY }

  Keys.onEscapePressed: function(e) {
    if (root.closeOnEscape && root.open) { root.dismissRequested(); e.accepted = true }
    else e.accepted = false
  }

  onOpenChanged: {
    if (open) forceActiveFocus()
    if (!animated || (open && instantIn)) {
      scaleS.snap(open ? 1 : toExitScale)
      offX.snap(open ? 0 : fromX)
      offY.snap(open ? 0 : fromY)
      _present()
      return
    }
    if (open && opacity < 0.01) {
      scaleS.snap(fromScale)
      offX.snap(fromX)
      offY.snap(fromY)
    }
    if (open) {
      _awaitingFrame = true
      firstFrameFallback.restart()
    } else {
      _present()
    }
  }

  Connections {
    target: root.Window.window
    ignoreUnknownSignals: true
    function onFrameSwapped() {
      if (!root._awaitingFrame) return
      root._present()
    }
  }
  Timer {
    id: firstFrameFallback
    interval: root.firstFrameTimeout
    onTriggered: if (root._awaitingFrame) root._present()
  }
  onOpacityChanged: if (!open && opacity <= 0) closed()
  Component.onCompleted: if (!open) { scaleS.snap(toExitScale); offX.snap(fromX); offY.snap(fromY) }

  Item {
    id: holder
    anchors.fill: parent
  }

  MouseArea {
    parent: root.Window.contentItem
    anchors.fill: parent
    z: 100000
    enabled: root.open && root.closeOnOutsideClick && parent !== null
    visible: enabled
    acceptedButtons: Qt.AllButtons
    onPressed: function(mouse) {
      if (root.containsScenePoint(this, mouse.x, mouse.y)) { mouse.accepted = false; return }
      root.dismissRequested()
    }
  }

  HyprlandFocusGrab {
    active: root.open && root.closeOnOutsideClick && root.QsWindow.window !== null
    windows: [root.QsWindow.window].concat(root.insideWindows).filter(function(w) { return !!w })
    onCleared: if (root.open) root.dismissRequested()
  }
}
