import QtQuick
import QtQuick.Window
import "file:///home/henri/.local/share/velum/qml/Velum"

// The context menu of a home screen icon (iPadOS: touch and hold an app): the icon lifts on a
// bouncy spring and the menu grows out of its corner on a spring with a soft overshoot, fading in
// during the first part of it; closing goes back into the icon, quicker and without overshoot.
// HomeScreen drives it with the finger (rowAt, hot, choose) and fades the rest of the home screen
// under the blurred wallpaper by `shown`. Reduced motion: a crossfade only.
Item {
  id: im
  readonly property var mc: Theme.core.surface.tablet.home.menu
  property bool open: false
  property var entries: []          // [{ text, icon?, action } | { group: true }]
  property var from: null           // the icon's rect in this item's coordinates { x, y, w } (settled)
  property string iconSource: ""
  property real pressScale: 1       // the icon's scale under the finger when the menu opens
  property int hot: -1              // the row under the finger
  property bool busy: false
  property bool flashOff: false
  signal chosen(var entry)
  signal closeRequested()

  function preset(response, damping) { return { response: response / 1000 * Theme.speed, dampingRatio: damping } }
  readonly property real exitFactor: Theme.core.motion.exitFactor
  Spring {
    id: mv
    reduced: Theme.reduceMotion
    preset: im.open ? im.preset(im.mc.openResponse, im.mc.openDamping) : im.preset(im.mc.openResponse * im.exitFactor, im.mc.closeDamping)
    target: im.open ? 1 : 0
  }
  Spring {
    id: lv
    reduced: Theme.reduceMotion
    preset: im.open ? im.preset(im.mc.liftResponse, im.mc.liftDamping) : im.preset(im.mc.liftResponse * im.exitFactor, im.mc.closeDamping)
    target: im.open ? 1 : 0
  }
  // reduced motion: the menu and the backdrop cross-fade, nothing scales
  property real fade: open ? 1 : 0
  Behavior on fade { NumberAnimation { duration: im.open ? Theme.dur("fast") : Theme.exit(Theme.dur("fast")) } }
  readonly property real shown: Theme.reduceMotion ? fade : Math.max(0, Math.min(1, mv.value))
  readonly property bool active: open || shown > 0.002 || mv.moving || lv.moving

  onOpenChanged: {
    if (!open) return
    busy = false; flashOff = false; hot = -1
    place()
    // the pop starts at the pressed icon's size, not at its resting one
    if (mc.liftScale !== 1) lv.from((pressScale - 1) / (mc.liftScale - 1))
  }

  // ---- where it goes: below the icon if it fits, else above; its leading edge on the icon's,
  // the trailing one when the screen ends first (positions taken when it opens: mapToItem is no binding)
  property real mx: 0
  property real my: 0
  property bool below: true
  readonly property real lifted: from ? from.w * (mc.liftScale - 1) / 2 : 0
  // the platter's height from its rows (the Column has not laid them out yet when it opens)
  function heightOf(list) {
    var h = 2 * Theme.m.menu.pad
    for (var i = 0; i < list.length; i++) h += list[i].group ? mc.groupGap : mc.row
    return h
  }
  function place() {
    var f = from
    if (!f) return
    var w = mc.width, h = heightOf(entries)
    below = f.y + f.w + lifted + mc.gap + h <= height - mc.margin
    var y = below ? f.y + f.w + lifted + mc.gap : f.y - lifted - mc.gap - h
    var x = f.x
    if (x + w > width - mc.margin) x = f.x + f.w - w
    mx = Math.max(mc.margin, Math.min(width - mc.margin - w, x))
    my = Math.max(mc.margin, Math.min(height - mc.margin - h, y))
  }

  function contains(px, py) { return active && px >= mx && px <= mx + platter.width && py >= my && py <= my + platter.height }
  function rowAt(px, py) {
    if (!open || busy || !contains(px, py)) return -1
    for (var i = 0; i < rep.count; i++) {
      var r = rep.itemAt(i)
      if (!r || r.isGroup) continue
      var q = r.mapFromItem(im, px, py)
      if (q.x >= 0 && q.x <= r.width && q.y >= 0 && q.y <= r.height) return i
    }
    return -1
  }
  // a chosen row blinks once (as every Velum menu), then the menu goes back into the icon
  function choose(i) {
    if (busy || i < 0 || !entries[i] || entries[i].group) return
    busy = true; hot = i; flashOff = true
    flash.phase = 0; flash.restart()
  }
  Timer {
    id: flash
    property int phase: 0
    interval: Theme.dur("flash")
    onTriggered: {
      if (phase === 0) { im.flashOff = false; phase = 1; restart(); return }
      var e = im.entries[im.hot]
      im.closeRequested()
      if (e) im.chosen(e)
    }
  }

  // ---- the lifted icon (the one on the home screen is hidden meanwhile), a soft shadow under it
  // as it leaves the page (the dock's shadow, on the icon's visible body)
  Item {
    visible: im.active && !!im.from
    x: im.from ? im.from.x : 0
    y: im.from ? im.from.y : 0
    width: im.from ? im.from.w : 0
    height: width
    scale: Theme.reduceMotion ? 1 : 1 + (im.mc.liftScale - 1) * lv.value
    Item {
      anchors.centerIn: parent
      width: parent.width * VIconMetrics.scale(liftedIcon.source)
      height: width
      opacity: Theme.reduceMotion ? im.fade : Math.max(0, Math.min(1, lv.value))
      VShadow { layers: Theme.core.surface.tablet.home.dock.shadow; radius: parent.width * Theme.core.surface.tablet.home.iconRadius }
    }
    Image {
      id: liftedIcon
      anchors.fill: parent
      source: im.iconSource
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      asynchronous: true
      scale: VIconMetrics.scale(source)
    }
  }

  // ---- the menu
  Item {
    id: platter
    x: im.mx
    y: im.my
    width: im.mc.width
    height: col.implicitHeight + 2 * Theme.m.menu.pad
    visible: im.active
    readonly property real s: Theme.reduceMotion ? 1 : im.mc.fromScale + (1 - im.mc.fromScale) * mv.value
    opacity: Theme.reduceMotion ? im.fade : Math.max(0, Math.min(1, mv.value / im.mc.fadeShare))
    transform: Scale {
      origin.x: im.from ? Math.max(0, Math.min(platter.width, im.from.x + im.from.w / 2 - platter.x)) : 0
      origin.y: im.below ? 0 : platter.height
      xScale: platter.s
      yScale: platter.s
    }
    readonly property var hairline: (Theme.r.menu.shadow || []).filter(function (l) { return !l.inset && l.blur === 0 })[0]
    VShadow { layers: Theme.r.menu.shadow; radius: im.mc.radius }
    Rectangle {
      anchors.fill: parent
      radius: im.mc.radius
      color: Theme.reduceTransparency ? Theme.r.menu.bgOpaque : Theme.r.menu.bg
      border.width: platter.hairline ? platter.hairline.spread : 0
      border.color: platter.hairline ? platter.hairline.color : "transparent"   // lint-ok: no rim without the token
    }
    VLens { layers: Theme.r.menu.shadow; radius: im.mc.radius }
    Column {
      id: col
      x: Theme.m.menu.pad
      y: Theme.m.menu.pad
      width: platter.width - 2 * x
      Repeater {
        id: rep
        model: im.entries
        Item {
          id: row
          required property int index
          required property var modelData
          readonly property bool isGroup: !!modelData.group
          readonly property bool lit: index === im.hot && !im.flashOff
          width: col.width
          height: isGroup ? im.mc.groupGap : im.mc.row
          // between groups: a band, as iPadOS's
          Rectangle {
            visible: row.isGroup
            x: -Theme.m.menu.pad
            width: platter.width
            height: parent.height
            color: Theme.r.menu.line
          }
          Rectangle {
            visible: row.lit
            anchors.fill: parent
            radius: Theme.m.radius.menuRow
            gradient: Gradient {
              GradientStop { position: 0; color: Theme.r.menu.highlightTop }
              GradientStop { position: 1; color: Theme.r.menu.highlight }
            }
          }
          Text {
            visible: !row.isGroup
            x: Theme.layout.menu.itemPadX
            width: parent.width - 2 * x - (glyph.visible ? glyph.width + Theme.layout.menu.glyphGap : 0)
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: row.modelData.text || ""
            font.family: Theme.font
            font.pixelSize: im.mc.font
            font.weight: Theme.m.menu.weight
            color: row.lit ? Theme.r.menu.highlightInk : row.modelData.danger ? Theme.r.menu.danger : Theme.r.menu.ink
          }
          VIcon {
            id: glyph
            visible: !row.isGroup && !!row.modelData.icon
            anchors.right: parent.right
            anchors.rightMargin: Theme.layout.menu.itemPadX
            anchors.verticalCenter: parent.verticalCenter
            name: row.modelData.icon || "plus"
            size: Theme.layout.icon.regular
            color: row.lit ? Theme.r.menu.highlightInk : Theme.r.menu.ink
          }
        }
      }
    }
  }
}
