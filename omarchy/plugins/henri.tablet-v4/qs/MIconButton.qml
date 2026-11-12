import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// Material's round icon button (MUI IconButton: a 24 px symbol in a 40 px circle) with a state layer under a
// finger.
Item {
  id: b
  property string icon: ""
  property string label: ""
  signal clicked()
  readonly property var k: Theme.core.surface.material.qs
  implicitWidth: k.header.button
  implicitHeight: k.header.button
  Rectangle {
    anchors.fill: parent; radius: width / 2
    color: Theme.r.popover.ink
    opacity: area.pressed ? Theme.core.alpha.pressed : 0
  }
  VIcon { anchors.centerIn: parent; name: b.icon; size: b.k.header.icon; color: Theme.r.popover.ink }
  TapHandler { id: area; onTapped: b.clicked() }
  Accessible.name: label
}
