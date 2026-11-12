import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// Material's exclusive toggle-button group (MUI ToggleButtonGroup, small, full width): outlined segments,
// the chosen one tinted. model: [{key, text}], current: a key.
Item {
  id: seg
  property var model: []
  property string current: ""
  signal chosen(string key)
  readonly property var k: Theme.core.surface.material.qs
  readonly property real w: model.length ? width / model.length : 0
  implicitHeight: k.battery.segHeight
  readonly property color line: Qt.alpha(Theme.r.popover.ink, k.battery.segLineAlpha)
  Repeater {
    model: seg.model
    Item {
      required property var modelData
      required property int index
      readonly property bool first: index === 0
      readonly property bool last: index === seg.model.length - 1
      x: index * seg.w; width: seg.w; height: seg.height
      Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.r.popover.ink, Theme.dark ? seg.k.battery.segSelectedAlpha : seg.k.battery.segSelectedAlphaLight)
        visible: seg.current === parent.modelData.key
        topLeftRadius: parent.first ? seg.k.battery.segRadius : 0
        bottomLeftRadius: parent.first ? seg.k.battery.segRadius : 0
        topRightRadius: parent.last ? seg.k.battery.segRadius : 0
        bottomRightRadius: parent.last ? seg.k.battery.segRadius : 0
      }
      Rectangle { visible: !parent.first; width: 1; height: parent.height; color: seg.line }
      MText { anchors.centerIn: parent; size: "small"; medium: true; text: parent.modelData.text
        tone: seg.current === parent.modelData.key ? "primary" : "secondary" }
      TapHandler { onTapped: seg.chosen(parent.modelData.key) }
    }
  }
  Rectangle { anchors.fill: parent; radius: seg.k.battery.segRadius; color: "transparent"; border.width: 1; border.color: seg.line }
}
