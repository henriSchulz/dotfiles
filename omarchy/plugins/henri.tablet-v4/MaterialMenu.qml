import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"
import "MaterialModel.js" as MM

// Every long-press menu of the Material home screen in one shape (the lab's ActionMenu.jsx): an
// optional header (the app's icon, its name, a subtitle), rows (an icon left, danger in error red,
// groups split by a divider) and tonal tiles at the foot in the rows' height — on Velum's glass.
// It grows out of the pressed icon (centred above it when it fits, else below) or out of a finger's
// point (MUI Grow). MaterialHome drives it with the finger: keyAt / contains / hot; the finger that
// opened it may lift, the menu stays.
//   rows:  [{ key, text, icon, danger? } | { divider: true }]     tiles: [{ key, text, icon }]
Item {
  id: mm
  property var pal                    // MaterialHome's palette (mode-dependent colours)
  property bool open: false
  property var anchor: null           // { x, y, w, h } of the pressed icon, or a point { x, y }
  property var header: null           // { icon: url | "", folder: [apps] | null, title, subtitle }
  property var rows: []
  property var tiles: []
  property string hot: ""             // the key under the finger (a pressed row lights up)
  property string wallSource: ""
  property rect wallRect              // the wallpaper in this item's coordinates
  readonly property var mt: Theme.core.surface.material
  readonly property var me: mt.menu
  signal chosen(string key)

  // laid out when it opens (kept while it closes): the parts with their y, the menu's box
  property var parts: []
  property real mw: 0
  property real mh: 0
  property real mx: 0
  property real my: 0
  property real ox: 0
  property real oy: 0
  property var shownHeader: null
  property var shownTiles: []
  property real p: 0                  // MUI Grow: 0 closed … 1 open
  readonly property bool active: open || p > 0
  visible: active

  NumberAnimation {
    id: grow
    target: mm; property: "p"
  }
  onOpenChanged: {
    if (open) { layoutNow(); grow.stop(); grow.to = 1; grow.duration = Theme.reduceMotion ? 0 : mm.mt.motion.enter; grow.easing.type = Easing.BezierSpline; grow.easing.bezierCurve = mm.mt.motion.easeOut; grow.start() }
    else { grow.stop(); grow.to = 0; grow.duration = Theme.reduceMotion ? 0 : mm.mt.motion.exit; grow.easing.type = Easing.BezierSpline; grow.easing.bezierCurve = mm.mt.motion.sharp; grow.start(); hot = "" }
  }

  TextMetrics { id: tm; font.family: "Roboto"; font.pixelSize: mm.mt.type.body2; font.weight: Font.Medium }
  function textW(t, size) { tm.font.pixelSize = size || mm.mt.type.body2; tm.text = t || ""; return tm.advanceWidth }
  function layoutNow() {
    var e = me, ty = mt.type, w = 0, y = e.pad, out = []
    var h = header, rs = rows || [], ts = tiles || []
    if (h) {
      var tw = Math.max(textW(h.title), h.subtitle ? textW(h.subtitle, ty.caption) : 0)
      w = Math.max(w, 2 * e.rowPadX + e.headerIcon + e.headerGap + tw)
      var th = ty.body2 * ty.body2Line + (h.subtitle ? ty.caption * ty.body2Line : 0)
      var hh = 2 * e.headerPadY + Math.max(e.headerIcon, th)
      out.push({ kind: "header", y: y, h: hh })
      y += hh
    }
    for (var i = 0; i < rs.length; i++) {
      var r = rs[i]
      if (r.divider) { out.push({ kind: "divider", y: y + e.dividerY, h: 1 }); y += 1 + 2 * e.dividerY; continue }
      w = Math.max(w, 2 * e.rowPadX + e.rowIconBox + e.tileIconGap + textW(r.text))
      out.push({ kind: "row", y: y, h: e.row, key: r.key, text: r.text, icon: r.icon || "", danger: !!r.danger })
      y += e.row
    }
    if (rs.length && ts.length && !rs[rs.length - 1].divider) { out.push({ kind: "divider", y: y + e.dividerY, h: 1 }); y += 1 + 2 * e.dividerY }
    var cols = Math.min(2, ts.length), tileNeed = 0
    for (var j = 0; j < ts.length; j++) tileNeed = Math.max(tileNeed, 2 * e.rowPadX + e.icon + e.tileIconGap + textW(ts[j].text))
    if (cols) w = Math.max(w, cols * tileNeed + (cols - 1) * e.tileGap)
    for (var k = 0; k < ts.length; k += cols) {
      for (var c = 0; c < cols && k + c < ts.length; c++) out.push({ kind: "tile", y: y, h: e.row, col: c, cols: cols, key: ts[k + c].key, text: ts[k + c].text, icon: ts[k + c].icon || "" })
      y += e.row + (k + cols < ts.length ? e.tileGap : 0)
    }
    mw = Math.max(e.minWidth, Math.min(e.maxWidth, w + 2 * e.pad))
    mh = y + e.pad
    var at = MM.placeMenu(anchor || { x: width / 2, y: height / 2 }, mw, mh, width, height, e.gap, e.margin)
    mx = at.x; my = at.y; ox = at.originX; oy = at.originY
    shownHeader = h; shownTiles = ts
    parts = out
  }
  // the key under (x, y) of this item, "" between them
  function keyAt(x, y) {
    if (!open || !contains(x, y)) return ""
    var lx = x - mx, ly = y - my, inner = mw - 2 * me.pad
    for (var i = 0; i < parts.length; i++) {
      var q = parts[i]
      if (!q.key || ly < q.y || ly > q.y + q.h) continue
      if (q.kind === "row") return q.key
      var tw = (inner - (q.cols - 1) * me.tileGap) / q.cols, tx = me.pad + q.col * (tw + me.tileGap)
      if (lx >= tx && lx <= tx + tw) return q.key
    }
    return ""
  }
  function contains(x, y) { return open && x >= mx && x <= mx + mw && y >= my && y <= my + mh }
  // a part's centre (tests): its key or text
  function pointOf(name) {
    for (var i = 0; i < parts.length; i++) {
      var q = parts[i]
      if (q.key !== name && q.text !== name) continue
      var inner = mw - 2 * me.pad
      if (q.kind === "row") return { x: mx + mw / 2, y: my + q.y + q.h / 2 }
      var tw = (inner - (q.cols - 1) * me.tileGap) / q.cols
      return { x: mx + me.pad + q.col * (tw + me.tileGap) + tw / 2, y: my + q.y + q.h / 2 }
    }
    return null
  }

  Item {
    id: paper
    x: mm.mx
    y: mm.my
    width: mm.mw
    height: mm.mh
    opacity: Math.min(1, mm.p)
    readonly property real s: Theme.reduceMotion ? 1 : mm.mt.motion.growFrom + (1 - mm.mt.motion.growFrom) * mm.p
    transform: Scale { origin.x: mm.ox; origin.y: mm.oy; xScale: paper.s; yScale: paper.s * paper.s }   // MUI Grow: scale(s, s²)
    Glass {
      anchors.fill: parent
      radius: mm.mt.glass.menuRadius
      rim: mm.pal.rim
      wallSource: mm.wallSource
      wallRect: mm.wallRect
      origin: Qt.point(mm.mx, mm.my)
    }
    Repeater {
      model: mm.parts
      Item {
        id: part
        required property var modelData
        readonly property var q: modelData
        readonly property real inner: mm.mw - 2 * mm.me.pad
        readonly property real tw: q.kind === "tile" ? (inner - (q.cols - 1) * mm.me.tileGap) / q.cols : inner
        x: q.kind === "divider" ? mm.me.pad + mm.me.dividerX : q.kind === "tile" ? mm.me.pad + q.col * (tw + mm.me.tileGap) : mm.me.pad
        y: q.y
        width: q.kind === "divider" ? mm.mw - 2 * (mm.me.pad + mm.me.dividerX) : tw
        height: q.h
        Rectangle {
          visible: part.q.kind === "divider"
          anchors.fill: parent
          color: mm.pal.divider
        }
        // a row under the finger, or a tonal tile
        Rectangle {
          visible: part.q.kind === "tile" || (part.q.kind === "row" && mm.hot === part.q.key)
          anchors.fill: parent
          radius: mm.me.rowRadius
          color: part.q.kind === "tile" ? (mm.hot === part.q.key ? mm.pal.press : mm.pal.tint) : mm.pal.press
        }
        // the header: the app's icon (or the folder's plate) and its name
        Item {
          visible: part.q.kind === "header"
          anchors.fill: parent
          Image {
            id: hIcon
            x: mm.me.rowPadX
            anchors.verticalCenter: parent.verticalCenter
            width: mm.me.headerIcon
            height: width
            visible: !!mm.shownHeader && !mm.shownHeader.folder
            source: mm.shownHeader && !mm.shownHeader.folder ? mm.shownHeader.icon || "" : ""
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            asynchronous: true
            scale: VIconMetrics.scale(source)
          }
          FolderPlate {
            x: mm.me.rowPadX
            anchors.verticalCenter: parent.verticalCenter
            visible: !!mm.shownHeader && !!mm.shownHeader.folder
            size: mm.me.headerIcon
            apps: mm.shownHeader && mm.shownHeader.folder ? mm.shownHeader.folder : []
            cfg: Theme.core.surface.tablet.home.folder
            iconRadius: Theme.core.surface.tablet.home.iconRadius
          }
          Column {
            x: mm.me.rowPadX + mm.me.headerIcon + mm.me.headerGap
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - mm.me.rowPadX
            MText {
              width: parent.width
              text: mm.shownHeader ? mm.shownHeader.title || "" : ""
              font.weight: Font.Medium
              color: mm.pal.text
            }
            MText {
              width: parent.width
              visible: !!(mm.shownHeader && mm.shownHeader.subtitle)
              text: mm.shownHeader ? mm.shownHeader.subtitle || "" : ""
              font.pixelSize: mm.mt.type.caption
              color: mm.pal.text2
            }
          }
        }
        // a row: icon, text
        Item {
          visible: part.q.kind === "row" || part.q.kind === "tile"
          anchors.fill: parent
          VIcon {
            id: rIcon
            x: mm.me.rowPadX
            anchors.verticalCenter: parent.verticalCenter
            visible: !!part.q.icon
            name: part.q.icon || ""
            size: mm.me.icon
            color: part.q.danger ? mm.pal.error : mm.pal.text
          }
          MText {
            x: mm.me.rowPadX + (part.q.kind === "tile" ? mm.me.icon + mm.me.tileIconGap : mm.me.rowIconBox + mm.me.tileIconGap)
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - mm.me.rowPadX
            text: part.q.text || ""
            font.weight: Font.Medium
            color: part.q.danger ? mm.pal.error : mm.pal.text
          }
        }
      }
    }
  }
}
