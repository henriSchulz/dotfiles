import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "file:///home/henri/.local/share/velum/qml/Velum"
import "Nav.js" as Nav

// One window of the App Switcher (MaterialSwitcher.qml): the window's picture at the card's size
// (ScreencopyView, captured once when the card is made — the switcher makes its cards per open),
// cropped from the top as the lab's object-fit: cover / object-position: top, the app's icon and
// name above it. The item's own box is the picture, so contains() is the hit test; the header lies
// above it. Only x/y (its slot and lift springs) and opacity change per frame.
//   follow(dy)   a finger pushes it up by dy (≤ 0)
//   drop(vy)     back into the row, carrying the finger's speed
//   fly(vy)      off the top (closed); `away` from then on
Item {
  id: card

  required property var entry          // { address, toplevel, name, icon }
  required property int index
  property int count: 1
  property real cardW: 0
  property real cardH: 0
  property real step: 0
  property real areaW: 0
  property real areaH: 0
  property bool lifted: false          // a finger has it (its header hides, as the lab's)
  property bool away: false
  // opening its app: 0 … 1 from its place in the row to the whole screen (`from` = its top left in the
  // switcher's coordinates at the tap); only transform, the clip's corner and height, the picture's width and the header's opacity change
  property real launch: 0
  property real dim: 1                 // the others fade while one opens
  property point from: Qt.point(0, 0)
  // where it lands: the window's own place (entry.place), else the whole area. The card scales
  // evenly to the window's width; its picture turns from "cover" to the window's own shape meanwhile
  readonly property rect goal: entry.place ? entry.place : Qt.rect(0, 0, areaW, areaH)
  readonly property real grow: goal.width / Math.max(1, cardW)
  // taken over from the app's own card (henri.tablet-v3's pull over an app): 1 … 0 from `handRect`
  // (that card on screen, the switcher's coordinates) into its place in the row; `handFrom` = its
  // top left in the row at the take. Only transform changes
  property real hand: 0
  property rect handRect: Qt.rect(0, 0, 0, 0)
  property point handFrom: Qt.point(0, 0)
  readonly property var cfg: Theme.core.surface.material.switcher
  readonly property string family: Theme.core.surface.material.widgets.font[0]
  readonly property bool hasPicture: shot.hasContent

  width: cardW
  height: cardH
  x: areaW / 2 - cardW / 2 + slotS.value
  y: areaH / 2 - cardH / 2 + liftS.value
  opacity: {
    var up = Math.max(0, -liftS.value) / Math.max(1, areaH)
    var o = 1 - Math.min(cfg.liftFade, up)
    return (away ? o * Math.max(0, 1 - up) : o) * card.dim
  }
  visible: opacity > 0.002
  z: launch > 0 ? 1 : 0
  transform: [
    Scale { xScale: 1 + (card.grow - 1) * card.launch; yScale: xScale },
    Translate { x: (card.goal.x - card.from.x) * card.launch; y: (card.goal.y - card.from.y) * card.launch },
    Scale { xScale: 1 + (card.handRect.width / Math.max(1, card.cardW) - 1) * card.hand; yScale: xScale },
    Translate { x: (card.handRect.x - card.handFrom.x) * card.hand; y: (card.handRect.y - card.handFrom.y) * card.hand }
  ]

  // its place in the row; a closed neighbour's gap closes on a spring
  Spring { id: slotS; preset: card.cfg.slotSpring; reduced: Theme.reduceMotion; target: Nav.slot(card.index, card.count, card.step) }
  Spring { id: liftS; preset: card.cfg.liftSpring; reduced: Theme.reduceMotion; target: 0 }
  Component.onCompleted: slotS.snap(slotS.target)

  function follow(dy) { liftS.snap(dy) }
  function drop(vy) {
    liftS.velocity = vy
    if (liftS.target !== 0) liftS.target = 0
    else if (liftS.value !== 0) liftS.anim.start()
  }
  function fly(vy) {
    away = true
    liftS.preset = cfg.closeSpring
    liftS.velocity = Math.min(0, vy)
    liftS.target = -areaH
  }

  // ---- header: icon + name above the picture
  Row {
    y: -(card.cfg.headerHeight + card.cfg.headerGap)
    height: card.cfg.headerHeight
    spacing: card.cfg.headerGap
    opacity: card.lifted || card.away ? 0 : (1 - Math.min(1, card.launch * card.cfg.launchFade)) * (1 - card.hand)
    Image {
      anchors.verticalCenter: parent.verticalCenter
      width: card.cfg.headerIcon
      height: width
      source: card.entry.icon || ""
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      asynchronous: true
      visible: source != ""
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, card.cardW - card.cfg.headerIcon - card.cfg.headerGap)
      text: card.entry.name || ""
      elide: Text.ElideRight
      color: card.cfg.ink
      font.family: card.family
      font.pixelSize: card.cfg.labelSize
      font.weight: card.cfg.labelWeight
    }
  }

  // ---- the picture on its card, with Velum's popover shadow (a lab influence)
  VShadow { layers: Theme.r.popover.shadow; radius: card.cfg.cardRadius; opacity: 1 - card.launch }
  ClippingRectangle {
    // growing into its app it takes the window's height (its place may be shorter than the screen)
    width: parent.width
    height: card.cardH + (card.goal.height / Math.max(0.001, card.grow) - card.cardH) * card.launch
    // square once it fills the screen (the radius is in card units, the card is scaled up)
    radius: card.cfg.cardRadius * (1 - card.launch)
    color: Theme.dark ? card.cfg.cardDark : card.cfg.cardLight
    // until the picture comes: the app's icon in the middle
    Image {
      anchors.centerIn: parent
      width: card.cardH * card.cfg.splashIcon
      height: width
      source: card.entry.icon || ""
      sourceSize.width: width
      sourceSize.height: height
      asynchronous: true
      visible: !shot.hasContent && source != ""
    }
    ScreencopyView {
      id: shot
      // cover from the top: as wide as the card, as tall as the window's aspect needs (or the other way)
      readonly property real aspect: sourceSize.width > 0 ? sourceSize.height / sourceSize.width : card.cardH / Math.max(1, card.cardW)
      readonly property bool tall: aspect >= card.cardH / Math.max(1, card.cardW)
      readonly property real coverW: tall ? card.cardW : card.cardH / aspect
      // growing into its app it turns to the window's width, as the window will stand
      width: coverW + (card.cardW - coverW) * card.launch
      height: width * aspect
      x: (card.cardW - width) / 2
      y: 0
      captureSource: card.entry.toplevel ? card.entry.toplevel.wayland : null
      live: false
      paintCursor: false
    }
  }
}
