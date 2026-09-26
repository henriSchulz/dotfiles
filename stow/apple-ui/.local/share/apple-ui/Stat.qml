import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui" as HUi
import "Apple.js" as Apple

// Label links, Wert rechts (crossfadet) — Zelle eines Stat-Rasters.
Item {
  id: st
  readonly property var m: Apple.material(st)
  property string label: ""
  property string value: ""
  height: Style.space(20)
  Text {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: st.label
    color: m.inkMuted
    font.family: Apple.uiFont
    font.pixelSize: Style.space(Apple.subheadline)
  }
  HUi.CrossfadeText {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignRight
    text: st.value
    color: m.ink
    fontFamily: Apple.uiFont
    fontSize: Style.space(Apple.subheadline)
  }
}
