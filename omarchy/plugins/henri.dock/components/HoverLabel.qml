import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/apple-ui/Apple.js" as Apple

// The name above the hovered tile (spec §6): appears at once (80 ms fade),
// jumps between tiles without fading, fades out in 100 ms when the pointer
// leaves the dock, hidden while a menu or stack is open.
Item {
  id: label
  property var dock
  property string text: ""
  property bool shown: false
  property real anchorMain: 0     // main-axis centre of the tile
  property real anchorCross: 0    // cross distance of the arrow tip (icon top + gap)

  readonly property var r: dock.rectFor(anchorMain, anchorCross,
      dock.horizontal ? bubble.implicitWidth : bubble.implicitHeight,
      dock.horizontal ? bubble.implicitHeight : bubble.implicitWidth)
  // Keep the card on screen; the arrow follows the tile instead.
  readonly property real clampedX: Math.max(Style.space(4), Math.min(dock.planeWidth - r.w - Style.space(4), r.x))
  readonly property real clampedY: Math.max(Style.space(4), Math.min(dock.planeHeight - r.h - Style.space(4), r.y))
  x: dock.horizontal ? clampedX : r.x
  y: dock.horizontal ? r.y : clampedY
  width: bubble.implicitWidth
  height: bubble.implicitHeight
  visible: opacity > 0
  opacity: shown && text.length > 0 ? 1 : 0
  Behavior on opacity {
    NumberAnimation {
      duration: label.shown ? Motion.dock.labelIn : Motion.dock.labelOut
      easing.type: Easing.BezierSpline
      easing.bezierCurve: label.shown ? Motion.easeOut : Motion.easeExit
    }
  }

  Bubble {
    id: bubble
    anchors.fill: parent
    palette: dock.palette
    arrowSide: dock.position
    arrowAt: dock.horizontal ? (label.r.x + label.r.w / 2 - label.clampedX) / Math.max(1, label.r.w)
                             : (label.r.y + label.r.h / 2 - label.clampedY) / Math.max(1, label.r.h)
    Text {
      text: label.text
      color: dock.palette.labelText
      font.family: Apple.uiFont
      font.pixelSize: Style.space(Apple.dock.labelFont)
      font.weight: Font.Normal
      renderType: Text.NativeRendering
    }
  }
}
