import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// The app drawer's long-press menu in the lab's ActionMenu look (lab/mui-material/src/ActionMenu.jsx):
// the app as a header (icon, name, "On the Home screen" when it is there), then tonal tiles in the rows'
// height — Add to Home, App info. Velum's popover glass and shadow. It grows out of the pressed app
// (above it when there is room, else below) on a Velum Spring, as MUI's Grow; a tap beside it closes
// it and is swallowed. Tokens: surface.material.drawer.menu.
//
// It fills its parent (the drawer). The finger that opened it may lift without closing it: that
// release belongs to the pressed cell's MouseArea, which grabbed the press before this menu existed.
//
// API
//   app: { id, name, icon }   anchor: rect of the pressed app in this item's coordinates
//   onHome: bool              family: font family
//   open(), close()           readonly shown, readonly active (on screen, also while closing)
//   signals: chosen(key)      key "add" | "info" (the menu closes itself first)
//            closed()         after the close motion
Item {
  id: menu
  anchors.fill: parent

  property var app: null
  property rect anchor: Qt.rect(0, 0, 0, 0)
  property bool onHome: false
  property string family: Theme.font
  readonly property bool shown: _shown
  readonly property bool active: visible
  readonly property var tiles: [{ key: "add", text: "Add to Home", glyph: "plus-square" }, { key: "info", text: "App info", glyph: "info" }]

  signal chosen(string key)
  signal closed()

  readonly property var cfg: Theme.core.surface.material.drawer.menu
  property bool _shown: false

  function open() { _shown = true }
  function close() { _shown = false }
  function choose(key) { close(); chosen(key) }

  Spring {
    id: grow
    preset: menu._shown ? ({ response: menu.cfg.openResponse * Theme.speed, dampingRatio: menu.cfg.openDamping })
      : ({ response: menu.cfg.openResponse * Theme.speed * Theme.core.motion.exitFactor, dampingRatio: menu.cfg.openDamping })
    target: menu._shown ? 1 : 0
  }
  readonly property real fade: Math.max(0, Math.min(1, grow.value))
  readonly property real k: Theme.reduceMotion ? 1 : grow.value
  visible: _shown || grow.value > 0
  Connections {
    target: grow
    function onMovingChanged() { if (!grow.moving && !menu._shown && grow.value <= 0) menu.closed() }
  }

  // a tap beside closes it and goes nowhere else
  MouseArea {
    anchors.fill: parent
    enabled: menu._shown
    onPressed: menu.close()
  }

  readonly property color tint: Qt.alpha(Theme.r.accent.base, Theme.dark ? cfg.tintDark : cfg.tintLight)
  // the header's and the tiles' natural width, then clamped
  readonly property real natural: Math.max(cfg.minWidth - 2 * cfg.pad,
    head.natural,
    tiles.length * tileMeasure.implicitWidth + (tiles.length - 1) * cfg.tileGap)
  readonly property real cardW: Math.min(cfg.maxWidth, natural + 2 * cfg.pad)
  readonly property real cardH: cfg.pad + 2 * cfg.headPadY + head.height + cfg.tile + cfg.pad
  readonly property bool above: anchor.y - cfg.gap - cardH >= cfg.margin
  readonly property real cardX: Math.max(cfg.margin, Math.min(width - cfg.margin - cardW, anchor.x + anchor.width / 2 - cardW / 2))
  readonly property real cardY: above ? anchor.y - cfg.gap - cardH : Math.min(height - cfg.margin - cardH, anchor.y + anchor.height + cfg.gap)

  // the widest tile's text, for the natural width
  Row {
    id: tileMeasure
    visible: false
    spacing: menu.cfg.tileGlyphGap
    leftPadding: menu.cfg.tilePadX
    rightPadding: menu.cfg.tilePadX
    Item { width: menu.cfg.tileGlyph; height: 1 }
    Text { text: menu.tiles[0].text; font.family: menu.family; font.pixelSize: menu.cfg.titleSize; font.weight: Font.Medium }
  }

  Item {
    id: card
    property string velumSurface: "popover"
    x: menu.cardX
    y: menu.cardY
    width: menu.cardW
    height: menu.cardH
    opacity: menu.fade
    scale: menu.cfg.fromScale + (1 - menu.cfg.fromScale) * menu.k
    transformOrigin: menu.above ? Item.Bottom : Item.Top

    VShadow { layers: Theme.r.popover.shadow; radius: menu.cfg.radius }
    Rectangle {
      anchors.fill: parent
      radius: menu.cfg.radius
      color: Theme.userReduceTransparency ? Theme.r.popover.bgOpaque : Theme.r.popover.bg
      border.width: 1 / Screen.devicePixelRatio
      border.color: Theme.r.line.rim
    }
    MouseArea { anchors.fill: parent }

    Row {
      id: head
      x: menu.cfg.pad + menu.cfg.headPadX
      y: menu.cfg.pad + menu.cfg.headPadY
      width: card.width - 2 * (menu.cfg.pad + menu.cfg.headPadX)
      height: Math.max(menu.cfg.headIcon, names.implicitHeight)
      spacing: menu.cfg.headGap
      Image {
        anchors.verticalCenter: parent.verticalCenter
        width: menu.cfg.headIcon; height: menu.cfg.headIcon
        sourceSize.width: menu.cfg.headIcon; sourceSize.height: menu.cfg.headIcon
        source: menu.app ? menu.app.icon || "" : ""
        asynchronous: true
        smooth: true
      }
      Column {
        id: names
        anchors.verticalCenter: parent.verticalCenter
        width: head.width - menu.cfg.headIcon - head.spacing
        Text {
          width: parent.width
          text: menu.app ? menu.app.name : ""
          elide: Text.ElideRight
          font.family: menu.family
          font.pixelSize: menu.cfg.titleSize
          font.weight: Font.Medium
          color: Theme.r.popover.ink
        }
        Text {
          visible: menu.onHome
          width: parent.width
          text: "On the Home screen"
          elide: Text.ElideRight
          font.family: menu.family
          font.pixelSize: menu.cfg.subtitleSize
          color: Theme.r.popover.inkSecondary
        }
      }
      // what the Row reports as its natural width: icon, gap, the longer name
      readonly property real natural: menu.cfg.headIcon + spacing + Math.max(nameMeasure.implicitWidth, subMeasure.implicitWidth) + 2 * menu.cfg.headPadX
      Text { id: nameMeasure; visible: false; text: menu.app ? menu.app.name : ""; font.family: menu.family; font.pixelSize: menu.cfg.titleSize; font.weight: Font.Medium }
      Text { id: subMeasure; visible: false; text: menu.onHome ? "On the Home screen" : ""; font.family: menu.family; font.pixelSize: menu.cfg.subtitleSize }
    }

    Row {
      x: menu.cfg.pad
      y: menu.cfg.pad + 2 * menu.cfg.headPadY + head.height
      spacing: menu.cfg.tileGap
      Repeater {
        model: menu.tiles
        delegate: Item {
          id: tile
          required property var modelData
          width: (card.width - 2 * menu.cfg.pad - (menu.tiles.length - 1) * menu.cfg.tileGap) / menu.tiles.length
          height: menu.cfg.tile
          Rectangle { anchors.fill: parent; radius: menu.cfg.tileRadius; color: menu.tint }
          Rectangle {
            anchors.fill: parent
            radius: menu.cfg.tileRadius
            color: Theme.r.popover.ink
            opacity: tileTap.pressed ? Theme.core.alpha.pressed : 0
          }
          Row {
            x: menu.cfg.tilePadX
            anchors.verticalCenter: parent.verticalCenter
            spacing: menu.cfg.tileGlyphGap
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: menu.cfg.tileGlyph
              horizontalAlignment: Text.AlignHCenter
              font.family: Theme.iconFamily("bold")
              font.pixelSize: menu.cfg.tileGlyph
              text: Theme.glyph(tile.modelData.glyph, "bold")
              color: Theme.r.popover.ink
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: tile.width - 2 * menu.cfg.tilePadX - menu.cfg.tileGlyph - menu.cfg.tileGlyphGap
              elide: Text.ElideRight
              text: tile.modelData.text
              font.family: menu.family
              font.pixelSize: menu.cfg.titleSize
              font.weight: Font.Medium
              color: Theme.r.popover.ink
            }
          }
          TapHandler { id: tileTap; onTapped: menu.choose(tile.modelData.key) }
        }
      }
    }
  }
}
