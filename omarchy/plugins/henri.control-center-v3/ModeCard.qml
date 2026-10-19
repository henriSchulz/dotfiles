import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// A choice as a card: a badge over its name, accent rim while chosen (energy modes).
VTile {
  id: mc
  property string icon: ""
  property string label: ""
  property bool selected: false
  signal chosen()
  height: Theme.layout.meter.card
  border.color: selected ? Theme.r.accent.base : Theme.r.line.rim
  Behavior on border.color { ColorAnimation { duration: Theme.dur("fast") } }
  Spring { id: mcPress; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: mcMouse.pressed ? Theme.scale("press") : 1 }
  scale: mcPress.value
  Rectangle { anchors.fill: parent; radius: parent.radius; color: Theme.r.popover.fillHover; visible: mcMouse.containsMouse && !mc.selected }
  Column {
    anchors.centerIn: parent; spacing: Theme.layout.list.gap / 2
    VBadge { anchors.horizontalCenter: parent.horizontalCenter; icon: mc.icon; on: mc.selected; onTapped: mc.chosen() }
    VText { anchors.horizontalCenter: parent.horizontalCenter; text: mc.label; font.pixelSize: Theme.m.type.small
      font.weight: mc.selected ? Font.DemiBold : Font.Normal; color: mc.selected ? Theme.r.accent.text : Theme.r.popover.inkSecondary }
  }
  MouseArea { id: mcMouse; anchors.fill: parent; hoverEnabled: true; onClicked: mc.chosen() }
}