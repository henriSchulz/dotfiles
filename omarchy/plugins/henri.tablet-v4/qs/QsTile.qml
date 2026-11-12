import QtQuick
import QtQuick.Shapes
import "file:///home/henri/.local/share/velum/qml/Velum"

// A Quick Settings tile (Android 14 large tile, lab QuickSettings.jsx): symbol, label and its state on a
// rounded tile — the accent when on, the ink at a low alpha when off (the two crossfade). Internet and
// Bluetooth carry a chevron that opens their details. While editing: a remove badge on the corner, and the
// finger that holds the tile drags it (the grid places it, `moved` reports where); `spare` = a tile to add
// (dashed outline, add badge).
Item {
  id: tile
  property string key: ""
  property string label: ""
  property string sub: ""
  property string icon: ""
  property bool lit: false
  property bool chevron: false
  property bool editing: false
  property bool spare: false
  property bool held: false
  property bool holdFirst: false       // editing on a page that scrolls: a quick swipe scrolls, a held finger drags
  property bool armed: false           // …held still for shade.longPress
  signal tapped()
  signal longPressed()
  signal chevronTapped()
  signal badgeTapped()
  signal grabbed(real x, real y)       // editing: a finger took the tile (in the tile's coordinates)
  signal moved(real x, real y)
  signal dropped()
  readonly property var k: Theme.core.surface.material.qs
  readonly property color ink: lit && !spare ? Theme.r.ink.onAccent : Theme.r.popover.ink
  implicitHeight: k.tile.height
  objectName: (spare ? "spare-" : "tile-") + key
  opacity: held ? k.tile.heldOpacity : 1

  Rectangle {
    anchors.fill: parent; radius: tile.k.tile.radius
    visible: !tile.spare
    color: Qt.alpha(Theme.r.popover.ink, tile.k.tile.offAlpha)
  }
  Rectangle {
    anchors.fill: parent; radius: tile.k.tile.radius
    visible: !tile.spare
    color: Theme.r.accent.base
    opacity: tile.lit ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.dur("fast"); easing.bezierCurve: Theme.curve("out") } }
  }
  // a tile to add: a dashed outline
  Shape {
    anchors.fill: parent
    visible: tile.spare
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: Qt.alpha(Theme.r.popover.ink, tile.k.tile.dashAlpha)
      strokeWidth: 1
      fillColor: "transparent"
      strokeStyle: ShapePath.DashLine
      dashPattern: [tile.k.tile.dash, tile.k.tile.dash]
      PathRectangle { x: 0.5; y: 0.5; width: tile.width - 1; height: tile.height - 1; radius: tile.k.tile.radius }
    }
  }
  // the state layer under a finger
  Rectangle {
    anchors.fill: parent; radius: tile.k.tile.radius
    color: tile.ink
    opacity: area.pressed ? Theme.core.alpha.pressed : 0
  }

  Row {
    id: inner
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: tile.k.tile.padX
    anchors.rightMargin: tile.k.tile.padX
    anchors.verticalCenter: parent.verticalCenter
    spacing: tile.k.tile.iconGap
    VIcon { anchors.verticalCenter: parent.verticalCenter; name: tile.icon; weight: "fill"; size: tile.k.header.icon; color: tile.ink }
    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: inner.width - tile.k.header.icon - inner.spacing - (chev.visible ? chev.width + inner.spacing : 0)
      MText { width: parent.width; text: tile.label; medium: true; color: tile.ink }
      MText { width: parent.width; visible: !tile.spare && tile.sub !== ""; text: tile.sub; size: "caption"; color: tile.ink; opacity: tile.k.tile.subOpacity }
    }
    Item {
      id: chev
      visible: tile.chevron && !tile.editing
      width: tile.k.header.icon; height: tile.k.header.icon
      anchors.verticalCenter: parent.verticalCenter
      VIcon { anchors.centerIn: parent; name: "chevron.right"; weight: "bold"; size: tile.k.header.icon; color: tile.ink; opacity: tile.k.tile.subOpacity }
    }
  }

  // pointer handlers, not a MouseArea: the press also reaches the shade, whose swipes (push up, turn the
  // page) take the finger over from a tap that has not happened yet
  TapHandler {
    id: area
    enabled: !tile.editing || tile.spare
    longPressThreshold: tile.spare ? 0 : tile.k.shade.longPress / 1000
    onLongPressed: if (!tile.spare) tile.longPressed()
    onTapped: point => {
      if (tile.spare) { tile.tapped(); return }
      if (tile.chevron && point.position.x >= chev.mapToItem(tile, 0, 0).x - tile.k.tile.iconGap) tile.chevronTapped()
      else tile.tapped()
    }
  }
  TapHandler {
    enabled: tile.editing && !tile.spare && tile.holdFirst
    longPressThreshold: tile.k.shade.longPress / 1000
    onLongPressed: tile.armed = true
    onPressedChanged: if (!pressed) tile.armed = false
  }
  // editing: the finger that holds a tile moves it (this handler is asked before the shade's); with holdFirst only
  // once armed — before, no movement is enough and the shade's finger scrolls the page
  DragHandler {
    id: hold
    enabled: tile.editing && !tile.spare
    target: null
    // not armed: farther than the window reaches, so moving alone never starts it
    dragThreshold: !tile.holdFirst || tile.armed ? tile.k.shade.slop : Math.max(tile.k.shade.slop, tile.Window.width + tile.Window.height)
    grabPermissions: PointerHandler.CanTakeOverFromAnything
    onActiveChanged: if (active) tile.grabbed(centroid.position.x, centroid.position.y); else tile.dropped()
    onCentroidChanged: if (active) tile.moved(centroid.position.x, centroid.position.y)
  }

  // the badge: remove (editing) or add (a spare tile)
  Item {
    objectName: "badge-" + tile.key
    visible: tile.editing || tile.spare
    width: tile.k.tile.badge; height: width
    x: -tile.k.tile.badgeOffset; y: -tile.k.tile.badgeOffset
    Rectangle { anchors.centerIn: parent; width: parent.width * 0.8; height: width; radius: width / 2; color: Theme.r.popover.bgOpaque }   // lint-ok: the circle under the glyph's ring
    VIcon { anchors.centerIn: parent; name: tile.spare ? "plus.circle" : "minus.circle"; weight: "fill"; size: parent.width
      color: tile.spare ? Theme.r.accent.base : Theme.r.popover.inkSecondary }
    TapHandler { enabled: tile.editing && !tile.spare; onTapped: tile.badgeTapped() }
  }
}
