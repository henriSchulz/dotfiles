import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi
import "Apple.js" as Apple

// Runder Schließen-/Minus-Knopf, der die linke obere Ecke einer Karte
// überlappt (Mitteilungszentrale, Banner, Widget-Bearbeitung). Mit `label`
// wächst er beim Hover zur Kapsel („Alle löschen“), `grey` ist der graue
// Minus-Knopf des Bearbeitungsmodus.
//
//   AUi.NcCornerButton { palette: Apple.bannerPalette(dark); size: Style.space(Apple.banner.closeButton); onClicked: … }
HUi.Pressable {
  id: corner
  property var palette: Apple.ncPalette(false)
  property color ink: palette.textPrimary
  property string label: ""
  property string symbol: Apple.sf(0x100184)
  property bool grey: false
  property real size: Style.space(Apple.notificationCenter.closeButton)
  implicitHeight: size
  implicitWidth: size + (label !== "" && corner.hovered ? labelText.implicitWidth + Style.space(10) : 0)
  radius: height / 2
  showFill: false
  tint: ink
  Behavior on implicitWidth { NumberAnimation { duration: Motion.move(Motion.base); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
  Rectangle {
    anchors.fill: parent
    radius: corner.radius
    color: corner.grey ? Apple.systemGray : (Motion.glass ? corner.palette.tint : corner.palette.opaque)
    border.width: 1
    border.color: corner.palette.borderOuter
    Rectangle { anchors.fill: parent; anchors.margins: 1; radius: parent.radius - 1; color: "transparent"; border.width: 1; border.color: corner.palette.borderInner }
  }
  Text {
    x: (corner.size - width) / 2
    anchors.verticalCenter: parent.verticalCenter
    text: corner.symbol
    font.family: Apple.symbolFont
    font.pixelSize: corner.size * 0.5
    font.weight: Font.Bold
    color: corner.grey ? "#ffffff" : corner.ink
  }
  Text {
    id: labelText
    x: corner.size - Style.space(2)
    anchors.verticalCenter: parent.verticalCenter
    text: corner.label
    font.family: Apple.uiFont
    font.pixelSize: Style.space(11)
    font.weight: Font.DemiBold
    color: corner.ink
    opacity: corner.label !== "" && corner.hovered ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
  }
}
