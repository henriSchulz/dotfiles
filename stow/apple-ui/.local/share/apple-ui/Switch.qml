import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi
import "Apple.js" as Apple

// NSSwitch (38 × 22): Track crossfadet (fast), Knopf gleitet (snappy) und
// wird beim Drücken breiter. Folgt dem Backend — `checked` bleibt ein Binding.
Rectangle {
  id: sw
  readonly property var m: Apple.material(sw)
  property bool checked: false
  signal toggled(bool on)
  width: Style.space(Apple.switchW)
  height: Style.space(Apple.switchH)
  radius: height / 2
  color: checked ? m.accent : m.badgeOff
  border.width: 1
  border.color: m.hairline
  antialiasing: true
  Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
  readonly property real gap: Style.space(2)
  readonly property real knobBase: height - gap * 2
  Rectangle {
    id: knob
    readonly property real stretch: mouse.pressed && !Motion.reduceMotion ? sw.knobBase * 0.12 : 0
    width: sw.knobBase + stretch
    height: sw.knobBase
    radius: height / 2
    y: sw.gap
    x: sw.gap + pos.value * (sw.width - sw.knobBase - sw.gap * 2) - (sw.checked ? stretch : 0)
    color: "#ffffff"
    antialiasing: true
    Behavior on width { NumberAnimation { duration: Motion.instant; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    HUi.SpringValue { id: pos; preset: Motion.snappy; to: sw.checked ? 1 : 0 }
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    anchors.margins: -Style.space(4)
    cursorShape: Qt.PointingHandCursor
    onClicked: sw.toggled(!sw.checked)
  }
}
