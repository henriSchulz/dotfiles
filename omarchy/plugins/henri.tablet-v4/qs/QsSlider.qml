import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// The brightness slider (Android 12+, lab QuickSettings.jsx): a thick full-round track, the accent fill with
// the symbol inside it; a finger sets the value where it lands and drags it. The fill never changes size: a
// fixed round cap at the left and a full-width round bar that slides (transform only), clipped at the cap's
// middle, so nothing is laid out while the finger moves. `preventStealing`: the shade's swipes never take it.
Item {
  id: s
  property real value: 0.5                 // 0 … 1, owned by the caller
  property string icon: "brightness"
  signal moved(real v, bool final)
  signal held(bool down)
  readonly property var k: Theme.core.surface.material.qs
  readonly property real h: k.slider.height
  implicitHeight: h
  readonly property real shown: area.pressed ? area.v : value

  Rectangle { anchors.fill: parent; radius: s.h / 2; color: Qt.alpha(Theme.r.popover.ink, s.k.slider.trackAlpha) }
  Rectangle { width: s.h; height: s.h; radius: s.h / 2; color: Theme.r.accent.base }
  Item {
    x: s.h / 2; width: s.width - s.h / 2; height: s.h
    clip: true
    Rectangle {
      width: s.width; height: s.h; radius: s.h / 2
      color: Theme.r.accent.base
      transform: Translate { x: -s.width + s.h / 2 + s.shown * (s.width - s.h) }
    }
  }
  VIcon {
    x: (s.h - width) / 2; anchors.verticalCenter: parent.verticalCenter
    name: s.icon; weight: "fill"; size: s.k.header.icon; color: Theme.r.ink.onAccent
  }
  MouseArea {
    id: area
    anchors.fill: parent
    preventStealing: true
    property real v: 0
    function at(x) { return Math.max(0, Math.min(1, (x - s.h / 2) / Math.max(1, s.width - s.h))) }
    onPressed: mouse => { v = at(mouse.x); s.held(true); s.moved(v, false) }
    onPositionChanged: mouse => { v = at(mouse.x); s.moved(v, false) }
    onReleased: mouse => { v = at(mouse.x); s.moved(v, true); s.held(false) }
    onCanceled: { s.moved(v, true); s.held(false) }
  }
}
