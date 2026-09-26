import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "Apple.js" as Apple

// Zeile mit Titel, Erklärung und Schalter; die ganze Zeile schaltet.
Rectangle {
  id: sr
  readonly property var m: Apple.material(sr)
  property string title: ""
  property string caption: ""
  property bool checked: false
  signal toggled(bool on)
  width: parent ? parent.width : 0
  height: Style.space(48)
  radius: Style.space(Apple.radiusRow)
  color: mouse.containsMouse ? m.rowHover : Qt.rgba(m.rowHover.r, m.rowHover.g, m.rowHover.b, 0)
  Behavior on color {
    ColorAnimation {
      duration: mouse.containsMouse ? Motion.instant : Motion.fast
      easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
    }
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: sr.toggled(!sr.checked)
  }
  Column {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(12)
    anchors.right: toggle.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    Text {
      width: parent.width
      text: sr.title
      color: m.ink
      font.family: Apple.uiFont
      font.pixelSize: Style.space(Apple.body)
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      visible: text !== ""
      text: sr.caption
      color: m.inkMuted
      font.family: Apple.uiFont
      font.pixelSize: Style.space(Apple.subheadline)
      elide: Text.ElideRight
    }
  }
  Switch {
    id: toggle
    anchors.right: parent.right
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    checked: sr.checked
    onToggled: function(on) { sr.toggled(on) }
  }
}
