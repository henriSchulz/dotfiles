import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "Apple.js" as Apple

// Kopf einer Detailseite: Zurück-Chevron + Titel (title3 15 pt semibold),
// optional ein Schalter rechts. Klick links von ihm geht zurück.
Item {
  id: ph
  readonly property var m: Apple.material(ph)
  property string title: ""
  property bool showSwitch: false
  property bool checked: false
  signal toggled(bool on)
  signal back()
  // Trailing controls (pop-up button, icon buttons) sit right of the title,
  // left of the switch.
  default property alias trailing: trailingRow.data
  width: parent ? parent.width : 0
  implicitHeight: Style.space(Apple.pageHeaderH)
  height: implicitHeight

  Row {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: Apple.sf(0x100189)
      transform: Translate {
        x: chevronHover.hovered && !Motion.reduceMotion ? -Style.space(3) : 0
        Behavior on x {
          NumberAnimation {
            duration: chevronHover.hovered ? Motion.instant : Motion.fast
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
          }
        }
      }
      color: m.ink
      font.family: Apple.symbolFont
      font.pixelSize: Style.space(Apple.title2)
      HoverHandler { id: chevronHover }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: ph.title
      color: m.ink
      font.family: Apple.uiFont
      font.pixelSize: Style.space(Apple.title3)
      font.weight: Font.DemiBold
    }
  }
  MouseArea {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.right: trailingRow.left
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: ph.back()
  }
  Row {
    id: trailingRow
    anchors.right: toggle.visible ? toggle.left : parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)
  }
  Switch {
    id: toggle
    visible: ph.showSwitch
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    checked: ph.checked
    onToggled: function(on) { ph.toggled(on) }
  }
}
