import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// A tile of rows with an optional title: the detail pages' building block.
VTile {
  id: grp
  property string title: ""
  property string titleDetail: ""
  default property alias rows: grpCol.data
  width: parent ? parent.width : 0
  height: grpCol.height + 2 * Theme.layout.module.tileInset + (title ? Theme.layout.module.section - Theme.layout.module.tileInset : 0)
  VText { visible: grp.title !== ""; x: Theme.layout.module.pad; height: Theme.layout.module.section; verticalAlignment: Text.AlignVCenter
    text: grp.title; font.weight: Font.DemiBold; color: Theme.r.popover.ink }
  VText { visible: grp.titleDetail !== ""; anchors.right: parent.right; anchors.rightMargin: Theme.layout.module.pad
    height: Theme.layout.module.section; verticalAlignment: Text.AlignVCenter; text: grp.titleDetail; tone: "secondary" }
  Column { id: grpCol; y: grp.title ? Theme.layout.module.section : Theme.layout.module.tileInset; width: parent.width }
}