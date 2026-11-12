import QtQuick
import QtQuick.Shapes
import "file:///home/henri/.local/share/velum/qml/Velum"

// Today's battery history (akku-test's CSV via qs-read, at most surface.material.qs.battery.points): the
// percentage as an area over the panel's width, the line on top (lab QsPages.jsx History). Redrawn only
// when the points change (every poll while its page is shown).
Item {
  id: c
  property var points: []                  // [[minute of the day, percent], …]
  readonly property var k: Theme.core.surface.material.qs
  implicitHeight: k.battery.chart
  readonly property var line: {
    const p = c.points || []
    if (p.length < 2 || c.width <= 0) return []
    const t0 = p[0][0], t1 = p[p.length - 1][0], span = Math.max(1, t1 - t0)
    // inside the item by half the line, so the round caps never reach a neighbour page
    const m = c.k.battery.line / 2, w = c.width - 2 * m, h = c.height - 2 * m
    return p.map(q => Qt.point(m + (q[0] - t0) / span * w, m + h - q[1] / 100 * h))
  }
  MText { visible: c.line.length < 2; anchors.verticalCenter: parent.verticalCenter; text: "No history today"; size: "caption"; tone: "secondary" }
  Shape {
    anchors.fill: parent
    visible: c.line.length >= 2
    preferredRendererType: Shape.CurveRenderer
    antialiasing: true
    ShapePath {
      strokeWidth: -1
      fillColor: Qt.alpha(Theme.r.accent.base, c.k.battery.areaAlpha)
      PathPolyline { path: c.line.length ? c.line.concat([Qt.point(c.width, c.height), Qt.point(0, c.height)]) : [] }
    }
    ShapePath {
      strokeColor: Theme.r.accent.base
      strokeWidth: c.k.battery.line
      fillColor: "transparent"
      joinStyle: ShapePath.RoundJoin
      capStyle: ShapePath.RoundCap
      PathPolyline { path: c.line }
    }
  }
}
