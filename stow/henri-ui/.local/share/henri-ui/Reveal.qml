import QtQuick
import Quickshell
import Quickshell.Hyprland
import "Motion.js" as Motion

// Enter/exit choreography for everything that appears: menu, popover, panel, toast.
// Wrap the surface in it and drive `open`; it stays visible until faded out.
//
//   HUi.Reveal {
//     open: root.opened
//     kind: "menu"                  // menu | popover | panel | toast
//     origin: Item.Top              // side of the anchor it grows out of
//     onDismissRequested: root.close()      // Esc / click outside — REQUIRED, see below
//     insideWindows: [barWindow]            // optional: windows that don't count as "outside"
//     onClosed: popupWindow.visible = false   // optional: after the exit finished
//     HUi.Surface { … }
//   }
//
// Interrupting (close while opening, reopen while closing) reverses smoothly.
//
// Esc: while open the Reveal holds keyboard focus (FocusScope) and turns Esc
// into dismissRequested(). It never sets `open` itself — that would break the
// caller's binding (e.g. open: root.opened) and desync the panel state — so the
// caller closes it the way it opened it. Inner handlers get Esc first
// (HUi.PageStack goes back a page before the surface closes).
//
// Click outside — also dismissRequested(), two layers:
//  • same window: a transparent catcher covers the window while open; a press
//    outside the surface is consumed (like macOS: the dismissing click does not
//    also hit what is underneath), presses on the surface pass straight through.
//  • other windows / desktop: HyprlandFocusGrab on this window (+ insideWindows,
//    e.g. the bar holding the trigger, so the trigger can toggle it itself).
FocusScope {
  id: root

  property bool open: false
  property string kind: "menu"
  property int origin: Item.Top
  // Slide-in distance. Menus drop out of the anchor, toasts come from the edge;
  // set the sign to match (e.g. toast at the bottom: toastOffset positive).
  property real fromX: 0
  property real fromY: kind === "menu" ? Motion.menuOffsetY : kind === "toast" ? -Motion.toastOffset : 0

  // true from the moment it starts opening until the exit has finished
  readonly property bool shown: visible
  // true once fully in — start expensive work (models, polling) here, not at open
  readonly property bool settled: open && opacity >= 1
  signal closed()
  signal dismissRequested()
  property bool closeOnEscape: true
  property bool closeOnOutsideClick: true
  property var insideWindows: []

  function containsScenePoint(item, x, y) {
    var p = item.mapToItem(root, x, y)
    return p.x >= 0 && p.y >= 0 && p.x < root.width && p.y < root.height
  }

  default property alias content: holder.data

  readonly property real fromScale: kind === "menu" ? Motion.menuFromScale
    : kind === "toast" ? 1 : Motion.popoverFromScale
  readonly property real toExitScale: kind === "toast" ? 1 : Motion.exitToScale
  readonly property var preset: kind === "menu" ? Motion.smooth : Motion.gentle
  readonly property int enterDuration: kind === "menu" ? Motion.base : Motion.slow

  implicitWidth: holder.childrenRect.width
  implicitHeight: holder.childrenRect.height
  visible: open || opacity > 0.001
  opacity: open ? 1 : 0
  transformOrigin: origin
  scale: Motion.reduceMotion ? 1 : scaleS.value
  transform: Translate {
    x: Motion.reduceMotion ? 0 : offX.value
    y: Motion.reduceMotion ? 0 : offY.value
  }

  Behavior on opacity {
    NumberAnimation {
      duration: root.open ? root.enterDuration : Motion.exit(root.enterDuration)
      easing.type: Easing.BezierSpline
      easing.bezierCurve: root.open ? Motion.easeOut : Motion.easeExit
    }
  }

  SpringValue { id: scaleS; preset: root.preset; to: root.open ? 1 : root.toExitScale }
  SpringValue { id: offX; preset: root.preset; epsilon: 0.1; to: root.open ? 0 : root.fromX }
  SpringValue { id: offY; preset: root.preset; epsilon: 0.1; to: root.open ? 0 : root.fromY }

  Keys.onEscapePressed: function(e) {
    if (root.closeOnEscape && root.open) { root.dismissRequested(); e.accepted = true }
    else e.accepted = false
  }

  // Only a fully closed surface starts from the small/offset pose; a surface
  // reopened mid-exit just turns around.
  onOpenChanged: {
    if (open) forceActiveFocus()
    if (open && opacity < 0.01) {
      scaleS.snap(fromScale)
      offX.snap(fromX)
      offY.snap(fromY)
    }
  }
  onOpacityChanged: if (!open && opacity <= 0) closed()
  Component.onCompleted: if (!open) { scaleS.snap(toExitScale); offX.snap(fromX); offY.snap(fromY) }

  Item {
    id: holder
    anchors.fill: parent
  }

  // Same-window outside clicks. Lives on the window's content item so it
  // covers everything, but lets presses on the surface fall through.
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

  // Clicks into other windows or the desktop.
  HyprlandFocusGrab {
    active: root.open && root.closeOnOutsideClick && root.QsWindow.window !== null
    windows: [root.QsWindow.window].concat(root.insideWindows).filter(function(w) { return !!w })
    onCleared: if (root.open) root.dismissRequested()
  }
}
