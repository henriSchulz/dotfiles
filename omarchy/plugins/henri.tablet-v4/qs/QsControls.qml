import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// The Controls page (lab QuickSettings.jsx `controls`): the brightness and volume sliders (Android 12+ stacks
// them at the top) and the tiles, two per row, in the order kept in tablet-qs.json. Editing: every tile carries
// a remove badge, a held tile goes to the slot under the finger (the others make room on a spring, transform only), and the tiles taken off wait below
// under "Add tiles" (a tap puts one back at the end). The tiles exist once each and are never rebuilt.
// Taller than `maxHeight` (editing on a small screen, 1024 × 768): the page scrolls inside it. The Flickable
// takes no finger itself — the shade's finger carries it (QuickSettings `scroller`: a vertical swipe on the page
// that can move it, then a fling with Velum's motion.scroll), so turning the page sideways and pushing the shade
// up past the end stay as they are. On such a page a tile moves only after a hold (a quick swipe on it scrolls),
// and a held tile near the top or bottom edge scrolls the page (surface.material.qs.scroll).
Item {
  id: ctl
  property var backend: null
  property bool editing: false
  property real maxHeight: 0              // 0: as tall as the content
  readonly property alias scroller: view
  signal toggleRequested(string key)
  signal detailRequested(string key)
  signal longPressed(string key)
  readonly property var k: Theme.core.surface.material.qs
  readonly property int cols: k.tile.cols
  readonly property real tileW: (width - (cols - 1) * k.tile.gap) / cols
  readonly property real rowH: k.tile.height + k.tile.gap

  // the order while a finger drags (saved on the drop), else the backend's
  property var order: backend ? backend.tiles : []
  Connections { target: ctl.backend; function onTilesChanged() { if (!ctl.dragKey) ctl.order = ctl.backend.tiles } }
  property string dragKey: ""
  readonly property var spare: backend ? backend.allTiles.filter(t => order.indexOf(t) < 0) : []
  readonly property int rows: Math.ceil(order.length / cols)
  readonly property real gridH: rows > 0 ? rows * rowH - k.tile.gap : 0
  readonly property real spareH: editing ? caption.height + k.tile.captionTop + k.tile.captionBottom
    + (spare.length ? Math.ceil(spare.length / cols) * rowH - k.tile.gap : 0) : 0
  readonly property real contentH: grid.y + gridH + spareH
  implicitHeight: maxHeight > 0 ? Math.min(contentH, maxHeight) : contentH
  // the content got shorter (editing ended): back inside at once, no animation
  onContentHChanged: if (view.contentY > Math.max(0, contentH - height)) view.contentY = Math.max(0, contentH - height)

  function info(key) {
    const b = ctl.backend
    if (!b) return { label: key, icon: "", lit: false, sub: "" }
    switch (key) {
    case "wifi": {
      const on = b.wifiOn && !b.airplane
      return { label: "Internet", icon: on ? "wifi" : "wifi.slash", lit: on, chevron: true,
               sub: on ? (b.wifiName !== "" ? b.wifiName : "Not connected") : "Off" }
    }
    case "bluetooth": return { label: "Bluetooth", icon: "bluetooth", lit: b.btOn, chevron: true,
                               sub: b.btOn ? (b.btConnectedName !== "" ? b.btConnectedName : "On") : "Off" }
    case "sound": return { label: "Sound", icon: b.muted ? "sound.mute" : "sound", lit: b.hasSink && !b.muted, chevron: true,
                           sub: !b.hasSink ? "No output" : b.muted ? "Muted" : b.sinkLabel }
    case "dnd": return { label: "Do Not Disturb", icon: "minus.circle", lit: b.dnd, sub: b.dnd ? "On" : "Off" }
    case "dark": return { label: "Dark theme", icon: "moon", lit: b.dark, sub: b.dark ? "On" : "Off" }
    case "night": return { label: "Night Light", icon: "night-shift", lit: b.night, sub: b.night ? "On" : "Off" }
    case "airplane": return { label: "Airplane mode", icon: "airplane", lit: b.airplane, sub: b.airplane ? "On" : "Off" }
    case "saver": return { label: "Battery Saver", icon: "battery.saver", lit: b.powerMode === "saver", sub: b.powerMode === "saver" ? "On" : "Off" }
    case "rotate": return { label: "Auto-rotate", icon: "rotation.lock", lit: b.rotate,
                            sub: !b.rotationAvailable ? "Unavailable" : b.rotate ? "On" : "Off" }
    case "cast": return { label: "Screen Cast", icon: "screencast", lit: b.castConnected, sub: b.castConnected ? b.tabletName : "Off" }
    }
    return { label: key, icon: "", lit: false, sub: "" }
  }
  function moveTo(list, key, i) {
    const out = list.filter(x => x !== key)
    out.splice(i, 0, key)
    return out
  }

  // a held tile to the slot under the finger (`finger`: in the page's coordinates, the viewport)
  property point finger: Qt.point(0, 0)
  function dragTo(key) {
    const gx = finger.x, gy = finger.y + view.contentY - grid.y
    const col = Math.max(0, Math.min(cols - 1, Math.floor(gx / (grid.width / cols))))
    const row = Math.max(0, Math.floor(gy / rowH))
    const i = Math.min(order.length - 1, row * cols + col)
    if (order.indexOf(key) !== i) order = moveTo(order, key, i)
    if (view.contentHeight > view.height && edgeDir() !== 0) edgeScroll.start()
  }
  // the finger near the top (-1) or bottom (1) edge with room to scroll that way
  function edgeDir() {
    if (finger.y < k.scroll.edge && view.contentY > 0) return -1
    if (finger.y > height - k.scroll.edge && view.contentY < view.contentHeight - view.height) return 1
    return 0
  }
  Timer {
    id: edgeScroll
    interval: ctl.k.scroll.tick
    repeat: true
    onTriggered: {
      const dir = ctl.dragKey !== "" ? ctl.edgeDir() : 0
      if (dir === 0) { stop(); return }
      const step = ctl.k.scroll.speed * interval / 1000
      view.contentY = Math.max(0, Math.min(view.contentHeight - view.height, view.contentY + dir * step))
      ctl.dragTo(ctl.dragKey)
    }
  }

  // the scroll: a Flickable with no content of its own (its contentY and fling, Velum's motion.scroll); the four
  // parts below follow it by a Translate (transform only), the page clips while it scrolls
  Flickable {
    id: view
    width: ctl.width
    height: ctl.height
    contentWidth: width
    contentHeight: ctl.contentH
    interactive: false
    boundsBehavior: Flickable.StopAtBounds
    flickDeceleration: Theme.core.motion.scroll.flickDeceleration
    maximumFlickVelocity: Theme.core.motion.scroll.maximumFlickVelocity
  }
  clip: view.contentHeight > view.height

  QsSlider {
    id: slider
    transform: Translate { y: -view.contentY }
    objectName: "slider"
    width: ctl.width
    value: ctl.backend ? ctl.backend.brightness : 0
    onHeld: down => { if (ctl.backend) ctl.backend.brightnessHeld = down }
    onMoved: (v, final) => { if (ctl.backend) ctl.backend.setBrightness(v, final) }
  }
  // the default output's volume (0 while muted; a finger that moves it up unmutes)
  QsSlider {
    id: volume
    transform: Translate { y: -view.contentY }
    objectName: "volume"
    y: slider.height + ctl.k.slider.gap
    width: ctl.width
    icon: ctl.backend ? ctl.backend.volumeIcon : "sound"
    value: ctl.backend && !ctl.backend.muted ? ctl.backend.volume : 0
    onHeld: down => { if (ctl.backend) ctl.backend.volumeHeld = down }
    onMoved: (v, final) => { if (ctl.backend) ctl.backend.setVolume(v, final) }
  }

  Item {
    id: grid
    transform: Translate { y: -view.contentY }
    y: volume.y + volume.height + ctl.k.slider.bottom
    width: ctl.width
    height: ctl.gridH
    Repeater {
      model: ctl.backend ? ctl.backend.allTiles : []
      QsTile {
        id: t
        required property string modelData
        readonly property var d: ctl.info(modelData)
        readonly property int slot: ctl.order.indexOf(modelData)
        readonly property real px: (slot % ctl.cols) * (ctl.tileW + ctl.k.tile.gap)
        readonly property real py: Math.floor(slot / ctl.cols) * ctl.rowH
        property int lastSlot: slot
        // a new slot: the tile jumps there and springs in from where it stood (transform only)
        onSlotChanged: {
          if (slot >= 0 && lastSlot >= 0) {
            ox.from((lastSlot % ctl.cols) * (ctl.tileW + ctl.k.tile.gap) + ox.value - px)
            oy.from(Math.floor(lastSlot / ctl.cols) * ctl.rowH + oy.value - py)
          }
          lastSlot = slot
        }
        Spring { id: ox; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: 0 }
        Spring { id: oy; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: 0 }
        transform: Translate { x: ox.value; y: oy.value }
        visible: slot >= 0
        x: px; y: py
        width: ctl.tileW
        key: modelData
        label: d.label; sub: d.sub; icon: d.icon; lit: d.lit; chevron: !!d.chevron
        editing: ctl.editing
        holdFirst: view.contentHeight > view.height
        held: ctl.dragKey === modelData
        z: held ? 1 : 0
        onTapped: ctl.toggleRequested(modelData)
        onChevronTapped: ctl.detailRequested(modelData)
        onLongPressed: ctl.longPressed(modelData)
        onBadgeTapped: if (ctl.backend) ctl.backend.setTiles(ctl.order.filter(x => x !== modelData))
        onGrabbed: ctl.dragKey = modelData
        onMoved: (mx, my) => {
          ctl.finger = t.mapToItem(ctl, mx, my)
          ctl.dragTo(modelData)
        }
        onDropped: {
          ctl.dragKey = ""
          edgeScroll.stop()
          if (ctl.backend && JSON.stringify(ctl.order) !== JSON.stringify(ctl.backend.tiles)) ctl.backend.setTiles(ctl.order)
        }
      }
    }
  }

  // editing: the tiles taken off, to add again
  MText {
    id: caption
    transform: Translate { y: -view.contentY }
    visible: ctl.editing
    y: grid.y + grid.height + ctl.k.tile.captionTop
    width: ctl.width
    size: "caption"; tone: "secondary"
    text: ctl.spare.length ? "Hold and drag to rearrange · Add tiles" : "Hold and drag to rearrange"
  }
  Item {
    visible: ctl.editing
    transform: Translate { y: -view.contentY }
    y: caption.y + caption.height + ctl.k.tile.captionBottom
    width: ctl.width
    Repeater {
      model: ctl.editing ? ctl.spare : []
      QsTile {
        required property string modelData
        required property int index
        readonly property var d: ctl.info(modelData)
        x: (index % ctl.cols) * (ctl.tileW + ctl.k.tile.gap)
        y: Math.floor(index / ctl.cols) * ctl.rowH
        width: ctl.tileW
        spare: true
        key: modelData; label: d.label; icon: d.icon
        onTapped: if (ctl.backend) ctl.backend.setTiles(ctl.order.concat([modelData]))
      }
    }
  }
}
