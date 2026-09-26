import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui" as HUi
import "Apple.js" as Apple

// Titel links, aktueller Wert rechts, über einem Meter ("CPU …… 23 %").
Item {
  id: uh
  readonly property var m: Apple.material(uh)
  property string title: ""
  property string value: ""
  property color valueColor: m.ink
  height: Style.space(24)
  Text {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: uh.title
    color: m.ink
    font.family: Apple.uiFont
    font.pixelSize: Style.space(Apple.body)
    font.weight: Font.DemiBold
  }
  HUi.CrossfadeText {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignRight
    text: uh.value
    color: uh.valueColor
    fontFamily: Apple.uiFont
    fontSize: Style.space(Apple.body)
  }
}
