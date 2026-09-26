import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi
import "Apple.js" as Apple

// Kapsel-Button (24 pt, wie "Edit Controls"): Label, optional SF-Symbol,
// `selected` füllt mit Akzent. Hover instant rein / fast raus, Press snappy.
Rectangle {
  id: cap
  readonly property var m: Apple.material(cap)
  property string label: ""
  property string symbol: ""
  property bool selected: false
  property bool outlined: true
  signal clicked()
  height: Style.space(Apple.capsuleH)
  implicitWidth: row.implicitWidth + Style.space(24)
  radius: height / 2
  color: selected ? m.badgeOn : mouse.containsMouse ? m.tileHover : m.capsule
  border.width: outlined ? 1 : 0
  border.color: m.hairline
  antialiasing: true
  Behavior on color {
    ColorAnimation {
      duration: mouse.containsMouse ? Motion.instant : Motion.fast
      easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
    }
  }
  scale: press.value
  HUi.SpringValue { id: press; preset: Motion.snappy; to: mouse.pressed && !Motion.reduceMotion ? Motion.pressScale : 1 }
  readonly property color ink: selected ? m.badgeOnGlyph : m.ink
  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(5)
    Text {
      visible: cap.symbol !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: cap.symbol
      color: cap.ink
      font.family: Apple.symbolFont
      font.pixelSize: Style.space(cap.label === "" ? Apple.body : Apple.subheadline)
      Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    }
    Text {
      visible: cap.label !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: cap.label
      color: cap.ink
      font.family: Apple.uiFont
      font.pixelSize: Style.space(Apple.callout)
      font.weight: cap.selected ? Font.DemiBold : Font.Normal
      Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    }
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: cap.clicked()
  }
}
