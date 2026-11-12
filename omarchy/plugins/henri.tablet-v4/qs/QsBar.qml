import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// Material's determinate progress bar (the lab's LinearProgress, 10 px, round): the level of a battery.
// The fill is a full-width bar slid into place (transform), never resized. `low`: the danger colour.
Item {
  id: b
  property real value: 0                   // 0 … 1
  property bool low: false
  readonly property var k: Theme.core.surface.material.qs
  implicitHeight: k.battery.bar
  readonly property color fill: low ? Theme.r.danger : Theme.r.accent.base
  Rectangle { anchors.fill: parent; radius: height / 2; color: Qt.alpha(b.fill, b.k.battery.trackAlpha) }
  Item {
    anchors.fill: parent
    clip: true
    Rectangle {
      width: b.width; height: b.height; radius: height / 2
      color: b.fill
      transform: Translate { x: (Math.max(0, Math.min(1, b.value)) - 1) * b.width }
    }
  }
}
