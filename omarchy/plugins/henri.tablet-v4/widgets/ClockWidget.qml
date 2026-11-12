import QtQuick
import Quickshell
import "file:///home/henri/.local/share/velum/qml/Velum"

// The Clock widget (lab Widgets.jsx Clock): the time large and light, the date under it.
// API: width, height (from the home grid; 2 × 2 cells by default — surface.material.widgets.cells).
WidgetCard {
  id: cw
  readonly property var w: Theme.core.surface.material.widgets
  readonly property string family: w.font[0]

  SystemClock { id: clock; precision: SystemClock.Minutes }

  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.margins: cw.w.pad
    spacing: cw.w.gap
    Text {
      width: parent.width
      text: Qt.formatTime(clock.date, "HH:mm")
      elide: Text.ElideRight
      color: Theme.dark ? cw.w.inkDark : cw.w.inkLight
      font.family: cw.family
      font.pixelSize: Math.min(cw.w.type.clock, cw.width * cw.w.clockShare)
      font.weight: cw.w.weight.light
      lineHeight: 1
    }
    Text {
      width: parent.width
      text: Qt.locale("en_GB").toString(clock.date, "dddd d MMMM")
      elide: Text.ElideRight
      color: Theme.dark ? cw.w.inkSoftDark : cw.w.inkSoftLight
      font.family: cw.family
      font.pixelSize: cw.w.type.body
    }
  }
}
