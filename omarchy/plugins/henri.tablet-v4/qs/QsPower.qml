import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// The Power page (lab QsPages.jsx PowerPage): Lock, Sleep, Log out, Restart and Shut down as large tiles, two
// per row, Shut down across both in the danger colour. `chosen` goes to QuickSettings, which asks first for
// the three that end the session.
Item {
  id: pg
  signal chosen(string key, string text)
  readonly property var k: Theme.core.surface.material.qs
  readonly property var items: [
    { key: "lock", text: "Lock", icon: "lock" },
    { key: "sleep", text: "Sleep", icon: "sleep" },
    { key: "logout", text: "Log out", icon: "logout" },
    { key: "restart", text: "Restart", icon: "restart" },
    { key: "off", text: "Shut down", icon: "power" }]
  readonly property real tileW: (width - k.tile.gap) / k.tile.cols
  implicitHeight: Math.ceil(items.length / k.tile.cols) * (k.tile.height + k.tile.gap) - k.tile.gap
  Repeater {
    model: pg.items
    Item {
      required property var modelData
      required property int index
      readonly property bool danger: modelData.key === "off"
      objectName: "power-" + modelData.key
      x: danger ? 0 : (index % pg.k.tile.cols) * (pg.tileW + pg.k.tile.gap)
      y: Math.floor(index / pg.k.tile.cols) * (pg.k.tile.height + pg.k.tile.gap)
      width: danger ? pg.width : pg.tileW
      height: pg.k.tile.height
      readonly property color ink: danger ? Theme.r.ink.onDanger : Theme.r.popover.ink
      Rectangle { anchors.fill: parent; radius: pg.k.tile.radius
        color: parent.danger ? Theme.r.danger : Qt.alpha(Theme.r.popover.ink, pg.k.tile.offAlpha) }
      Rectangle { anchors.fill: parent; radius: pg.k.tile.radius; color: parent.ink; opacity: area.pressed ? Theme.core.alpha.pressed : 0 }
      Row {
        anchors.left: parent.left; anchors.leftMargin: pg.k.tile.padX
        anchors.verticalCenter: parent.verticalCenter
        spacing: pg.k.tile.iconGap
        VIcon { anchors.verticalCenter: parent.verticalCenter; name: modelData.icon; weight: "fill"; size: pg.k.header.icon; color: parent.parent.ink }
        MText { anchors.verticalCenter: parent.verticalCenter; text: modelData.text; medium: true; color: parent.parent.ink }
      }
      TapHandler { id: area; onTapped: pg.chosen(modelData.key, modelData.text) }
    }
  }
}
