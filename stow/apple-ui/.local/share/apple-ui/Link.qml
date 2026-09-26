import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "Apple.js" as Apple

// Textlink am Fuß einer Detailseite ("Disconnect", "Sound Output …").
Text {
  id: link
  readonly property var m: Apple.material(link)
  signal clicked()
  leftPadding: Style.space(6)
  color: mouse.containsMouse ? m.ink : m.inkMuted
  Behavior on color {
    ColorAnimation {
      duration: mouse.containsMouse ? Motion.instant : Motion.fast
      easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
    }
  }
  font.family: Apple.uiFont
  font.pixelSize: Style.space(Apple.subheadline)
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: link.clicked()
  }
}
