import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// Material's switch as the lab draws it (MUI Switch: a thin track, a round thumb with a shadow that slides
// over it, the accent when on). Taps toggle; the owner keeps `checked` (its signal is `toggled`).
Item {
  id: sw
  property bool checked: false
  signal toggled(bool on)
  readonly property var k: Theme.core.surface.material.qs
  implicitWidth: k.switch.width
  implicitHeight: k.switch.height
  Spring { id: pos; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: sw.checked ? 1 : 0 }
  Rectangle {
    anchors.centerIn: parent
    width: sw.k.switch.trackW; height: sw.k.switch.trackH; radius: height / 2
    color: Qt.alpha(Theme.r.popover.ink, sw.k.switch.offAlpha)
  }
  Rectangle {
    anchors.centerIn: parent
    width: sw.k.switch.trackW; height: sw.k.switch.trackH; radius: height / 2
    color: Qt.alpha(Theme.r.accent.base, sw.k.switch.onAlpha)
    opacity: pos.value
  }
  Item {
    id: thumb
    width: sw.k.switch.thumb; height: width
    anchors.verticalCenter: parent.verticalCenter
    x: (sw.width - sw.k.switch.trackW) / 2 - (width - sw.k.switch.trackH) / 2
    transform: Translate { x: pos.value * (sw.k.switch.trackW - sw.k.switch.trackH) }
    VShadow { layers: Theme.r.segment.plateShadow; radius: thumb.width / 2 }
    Rectangle { anchors.fill: parent; radius: width / 2; color: sw.k.switch.thumbOff }
    Rectangle { anchors.fill: parent; radius: width / 2; color: Theme.r.accent.base; opacity: pos.value }
  }
  TapHandler { onTapped: sw.toggled(!sw.checked) }
}
