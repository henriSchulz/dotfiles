import QtQuick
import "Motion.js" as Motion

// Enter/exit choreography for everything that appears: menu, popover, panel, toast.
// Wrap the surface in it and drive `open`; it stays visible until faded out.
//
//   HUi.Reveal {
//     open: root.opened
//     kind: "menu"                  // menu | popover | panel | toast
//     origin: Item.Top              // side of the anchor it grows out of
//     onClosed: popupWindow.visible = false   // optional: after the exit finished
//     HUi.Surface { … }
//   }
//
// Interrupting (close while opening, reopen while closing) reverses smoothly.
Item {
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

  // Only a fully closed surface starts from the small/offset pose; a surface
  // reopened mid-exit just turns around.
  onOpenChanged: {
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
}
