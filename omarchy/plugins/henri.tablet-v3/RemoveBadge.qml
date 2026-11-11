import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// The round remove badge (a minus) on a home screen icon, folder or widget in edit mode (iPadOS):
// it pops in on a spring when `shown` turns on, Launchpad's colours. HomeScreen finds a finger on
// it by its centre (hit), the touch target is badgeHit × bigger than the drawing.
Item {
  id: b
  property real size: 0
  property bool shown: false
  readonly property var ed: Theme.core.surface.tablet.home.edit
  readonly property var lp: Theme.core.surface.launchpad
  width: size
  height: size
  Spring { id: pop; reduced: Theme.reduceMotion; preset: Theme.spring("snappy"); target: b.shown ? 1 : 0 }
  visible: pop.value > 0.002
  scale: Theme.reduceMotion ? 1 : Math.max(0, pop.value)
  opacity: Math.max(0, Math.min(1, pop.value))
  // a finger at (x, y) of `item` on it (only while it shows)
  function hit(item, x, y) {
    if (!shown) return false
    var c = mapToItem(item, width / 2, height / 2)
    return Math.hypot(x - c.x, y - c.y) <= size * ed.badgeHit / 2
  }
  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: b.lp.badge
    VIcon { anchors.centerIn: parent; name: "minus"; weight: "bold"; size: b.size * b.ed.badgeGlyph; color: b.lp.badgeInk }
  }
}
