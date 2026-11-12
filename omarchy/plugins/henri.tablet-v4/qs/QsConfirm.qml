import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// A question before something that ends the session or cuts the line the screen comes over (Material 3
// dialog, inside the Quick Settings panel): a title, one line, Cancel and the action (red when it ends the
// session). It grows in on the snappy spring (scale + opacity) over the panel's dimmed content.
Item {
  id: c
  property string title: ""
  property string text: ""
  property string action: ""
  property bool danger: true
  property bool open: false
  signal accepted()
  signal canceled()
  readonly property var k: Theme.core.surface.material.qs
  visible: s.value > 0
  Spring { id: s; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: c.open ? 1 : 0 }

  Rectangle {
    anchors.fill: parent
    radius: c.k.panel.radius
    color: c.k.shade.scrim
    opacity: s.value
    MouseArea { anchors.fill: parent; enabled: c.open; onClicked: c.canceled() }
  }
  Rectangle {
    id: card
    anchors.centerIn: parent
    width: parent.width - 2 * c.k.panel.pad
    height: col.height + 2 * c.k.confirm.pad
    radius: c.k.panel.radius
    color: Theme.r.popover.bgOpaque
    opacity: s.value
    scale: Theme.reduceMotion ? 1 : Theme.core.motion.scale.popoverFrom + (1 - Theme.core.motion.scale.popoverFrom) * s.value
    VShadow { layers: Theme.r.popover.shadow; radius: card.radius; z: -1 }
    MouseArea { anchors.fill: parent }
    Column {
      id: col
      x: c.k.confirm.pad; y: c.k.confirm.pad
      width: parent.width - 2 * c.k.confirm.pad
      spacing: c.k.confirm.gap
      MText { width: parent.width; size: "subtitle"; medium: true; text: c.title }
      MText { width: parent.width; tone: "secondary"; text: c.text; wrapMode: Text.WordWrap; maximumLineCount: 3 }
      Row {
        anchors.right: parent.right
        spacing: c.k.header.gap
        Repeater {
          model: [{ key: "cancel", text: "Cancel" }, { key: "go", text: c.action }]
          Item {
            required property var modelData
            readonly property bool main: modelData.key === "go"
            objectName: "confirm-" + modelData.key
            width: label.width + 2 * c.k.header.donePad; height: c.k.confirm.button
            Rectangle { anchors.fill: parent; radius: height / 2; visible: parent.main; color: c.danger ? Theme.r.danger : Theme.r.accent.base }
            Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.r.popover.ink; opacity: btn.pressed ? Theme.core.alpha.pressed : 0 }
            MText { id: label; anchors.centerIn: parent; medium: true; text: parent.modelData.text
              color: parent.main ? Theme.r.ink.onAccent : Theme.r.accent.text }
            MouseArea { id: btn; anchors.fill: parent; onClicked: parent.main ? c.accepted() : c.canceled() }
          }
        }
      }
    }
  }
}
