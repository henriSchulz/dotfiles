import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi
import "Apple.js" as Apple

// Kleiner runder Aktions-Button (30 pt) mit SF-Symbol; Name für die Zugänglichkeit.
Rectangle {
  id: ib
  readonly property var m: Apple.material(ib)
  property string icon: ""
  property string name: ""
  signal clicked()
  width: Style.space(Apple.iconButton)
  height: width
  radius: width / 2
  color: mouse.containsMouse ? m.tileHover : m.badgeOff
  antialiasing: true
  Accessible.role: Accessible.Button
  Accessible.name: ib.name
  Behavior on color {
    ColorAnimation {
      duration: mouse.containsMouse ? Motion.instant : Motion.fast
      easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
    }
  }
  scale: press.value
  HUi.SpringValue { id: press; preset: Motion.snappy; to: mouse.pressed && !Motion.reduceMotion ? Motion.pressScale : 1 }
  Text {
    anchors.centerIn: parent
    text: ib.icon
    color: m.ink
    font.family: Apple.symbolFont
    font.pixelSize: Style.space(14)
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: ib.clicked()
  }
}
