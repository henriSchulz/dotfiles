import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi
import "Apple.js" as Apple

// Push-Button (NSButton rounded, 24 pt): `prominent` füllt mit Akzent.
Rectangle {
  id: btn
  readonly property var m: Apple.material(btn)
  property string text: ""
  property string icon: ""
  property bool prominent: false
  property string name: text
  signal clicked()
  height: Style.space(Apple.capsuleH)
  implicitWidth: row.implicitWidth + Style.space(20)
  radius: Style.space(Apple.radiusControl)
  color: prominent ? m.accent : mouse.containsMouse ? m.tileHover : m.capsule
  border.width: prominent ? 0 : 1
  border.color: m.hairline
  antialiasing: true
  Accessible.role: Accessible.Button
  Accessible.name: btn.name
  Behavior on color {
    ColorAnimation {
      duration: mouse.containsMouse ? Motion.instant : Motion.fast
      easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
    }
  }
  scale: press.value
  HUi.SpringValue { id: press; preset: Motion.snappy; to: mouse.pressed && !Motion.reduceMotion ? Motion.pressScale : 1 }
  readonly property color ink: prominent ? "#ffffff" : m.ink
  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(5)
    Text {
      visible: btn.icon !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: btn.icon
      color: btn.ink
      font.family: Apple.symbolFont
      font.pixelSize: Style.space(Apple.callout)
    }
    Text {
      visible: btn.text !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: btn.text
      color: btn.ink
      font.family: Apple.uiFont
      font.pixelSize: Style.space(Apple.callout)
      font.weight: btn.prominent ? Font.DemiBold : Font.Normal
    }
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: btn.clicked()
  }
}
