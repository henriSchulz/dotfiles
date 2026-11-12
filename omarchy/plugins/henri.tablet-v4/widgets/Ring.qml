import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// A level as a ring (lab Widgets.jsx Ring): a faint track and the accent's arc clockwise from twelve
// o'clock, round ends, whatever is declared inside in its middle. Velum's VRing underneath — a Shape
// (PathAngleArc, curve renderer) whose geometry changes only when the value does (it springs there
// and grows in once when shown), never a per-frame Canvas.
//   Ring { size: 96; value: 0.62; VText { anchors.centerIn: parent; text: "62" } }
VRing {
  readonly property var wcfg: Theme.core.surface.material.widgets
  line: size * wcfg.ringLine
  color: Theme.r.accent.base
  track: Theme.dark ? wcfg.trackDark : wcfg.trackLight
}
