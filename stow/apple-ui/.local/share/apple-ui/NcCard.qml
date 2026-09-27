import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "Apple.js" as Apple

// Schwebende Karte der Mitteilungszentrale und des Mitteilungs-Banners:
// Tönung, innere Glanz-Haarlinie, äußere Haarlinie, Kontaktschatten (kein
// Blur — eine weiche Platte knapp unter der Karte; das Glas macht der
// Compositor-Blur auf dem Layer). `palette` ist Apple.ncPalette(dark) bzw.
// Apple.bannerPalette(dark); mit Motion.glass = false wird die Fläche deckend.
//
//   AUi.NcCard { palette: Apple.bannerPalette(dark); radius: Style.space(Apple.banner.radius); … }
Item {
  id: card
  property var palette: Apple.ncPalette(false)
  property real radius: Style.space(Apple.notificationCenter.radiusCard)
  property alias color: fill.color
  default property alias content: fill.data

  Rectangle {
    // Shadow stand-in (no blur: a soft plate slightly below the card).
    anchors.fill: fill
    anchors.topMargin: Style.space(3)
    anchors.leftMargin: Style.space(1)
    anchors.rightMargin: Style.space(1)
    radius: card.radius
    color: card.palette.shadow
  }
  Rectangle {
    id: fill
    anchors.fill: parent
    radius: card.radius
    color: Motion.glass ? card.palette.tint : card.palette.opaque
    border.width: 1
    border.color: card.palette.borderOuter
    antialiasing: true
    Behavior on color { ColorAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    Rectangle {
      anchors.fill: parent
      anchors.margins: 1
      radius: parent.radius - 1
      color: "transparent"
      border.width: 1
      border.color: card.palette.borderInner
      antialiasing: true
    }
  }
}
