import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi
import "Apple.js" as Apple

// Auslastungsbalken: Fill gleitet (nur transform) in einem geclippten Track.
Item {
  id: meter
  readonly property var m: Apple.material(meter)
  property real fraction: 0
  property color fillColor: m.accent
  readonly property real clamped: Math.max(0, Math.min(1, fraction))
  height: Style.space(6)
  Rectangle { anchors.fill: parent; radius: height / 2; color: m.sliderTrack }
  Rectangle {
    width: parent.height; height: parent.height; radius: height / 2
    color: meter.fillColor
    opacity: meter.clamped > 0 ? 1 : 0
    Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
  }
  Item {
    x: meter.height / 2
    width: parent.width - x
    height: parent.height
    clip: true
    Rectangle {
      width: meter.width; height: meter.height; radius: height / 2
      color: meter.fillColor
      x: fill.value - meter.width + meter.height / 2
      Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    }
  }
  HUi.SpringValue { id: fill; to: meter.clamped * (meter.width - meter.height / 2); epsilon: 0.5 }
}
