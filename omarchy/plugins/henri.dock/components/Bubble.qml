import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/apple-ui/Apple.js" as Apple

// Rounded glass card with a small arrow pointing at the dock (label, menu,
// grid stack, settings). `arrowSide` is the side the arrow sits on — "bottom"
// for a dock at the bottom (arrow points down), "left"/"right" for a dock at
// that edge. The content area is the card without the arrow.
Item {
  id: bubble
  property var palette: Apple.dockPalette(false)
  property color fill: palette.label
  property color border: palette.border
  property color hairline: palette.hairline
  property real radius: Style.space(Apple.dock.labelRadius)
  property string arrowSide: "bottom"
  property real arrowW: Style.space(Apple.dock.labelArrowW)
  property real arrowH: Style.space(Apple.dock.labelArrowH)
  // Arrow tip position along the card's arrow side (0.5 = centred).
  property real arrowAt: 0.5
  property real padX: Style.space(Apple.dock.labelPadX)
  property real padY: Style.space(Apple.dock.labelPadY)
  default property alias content: inner.data
  readonly property alias cardItem: card

  readonly property bool vertical: arrowSide === "bottom"
  implicitWidth: inner.childrenRect.width + padX * 2 + (vertical ? 0 : arrowH)
  implicitHeight: inner.childrenRect.height + padY * 2 + (vertical ? arrowH : 0)

  Rectangle {
    // Soft shadow stand-in: a darker plate slightly offset toward the dock.
    anchors.fill: card
    anchors.topMargin: Style.space(2)
    radius: card.radius
    color: bubble.palette.shadow
    opacity: 0.6
  }
  Rectangle {
    id: card
    x: bubble.arrowSide === "left" ? bubble.arrowH : 0
    y: 0
    width: bubble.width - (bubble.vertical ? 0 : bubble.arrowH)
    height: bubble.height - (bubble.vertical ? bubble.arrowH : 0)
    radius: bubble.radius
    color: Motion.glass ? bubble.fill : bubble.palette.opaque
    border.width: 1
    border.color: bubble.hairline
    antialiasing: true
    Rectangle {
      anchors.fill: parent
      anchors.margins: 1
      radius: parent.radius - 1
      color: "transparent"
      border.width: 1
      border.color: bubble.border
      antialiasing: true
    }
    Item {
      id: inner
      x: bubble.padX
      y: bubble.padY
      width: parent.width - bubble.padX * 2
      height: parent.height - bubble.padY * 2
    }
  }
  Canvas {
    id: arrow
    width: bubble.vertical ? bubble.arrowW : bubble.arrowH
    height: bubble.vertical ? bubble.arrowH : bubble.arrowW
    x: bubble.arrowSide === "left" ? 0
     : bubble.arrowSide === "right" ? bubble.width - width
     : Math.round(card.x + card.width * bubble.arrowAt - width / 2)
    y: bubble.vertical ? card.height - 1
     : Math.round(card.height * bubble.arrowAt - height / 2)
    onPaint: {
      var c = getContext("2d")
      c.reset()
      c.fillStyle = card.color
      c.strokeStyle = bubble.hairline
      c.lineWidth = 1
      c.beginPath()
      if (bubble.arrowSide === "bottom") { c.moveTo(0, 0); c.lineTo(width / 2, height); c.lineTo(width, 0) }
      else if (bubble.arrowSide === "left") { c.moveTo(width, 0); c.lineTo(0, height / 2); c.lineTo(width, height) }
      else { c.moveTo(0, 0); c.lineTo(width, height / 2); c.lineTo(0, height) }
      c.closePath()
      c.fill()
    }
    Connections { target: card; function onColorChanged() { arrow.requestPaint() } }
    Connections { target: bubble; function onHairlineChanged() { arrow.requestPaint() } function onArrowSideChanged() { arrow.requestPaint() } }
  }
}
