import QtQuick
import QtQuick.Window
import "file:///home/henri/.local/share/velum/qml/Velum"

// The context menu of a home screen icon (iPadOS: touch and hold an app): the icon lifts on a
// bouncy spring and the menu — Velum's VTouchMenu — grows out of it. HomeScreen drives it with the
// finger (rowAt, hot, choose) and fades the rest of the home screen under the blurred wallpaper by
// `shown`. Reduced motion: a crossfade only.
Item {
  id: im
  readonly property var mc: Theme.core.surface.tablet.home.menu
  property bool open: false
  property var entries: []          // VTouchMenu's model
  property var from: null           // the icon's rect in this item's coordinates { x, y, w } (settled)
  property string iconSource: ""
  property real pressScale: 1       // the icon's scale under the finger when the menu opens
  property alias hot: menu.hot
  readonly property bool busy: menu.busy
  signal chosen(var entry)
  signal closeRequested()

  function preset(response, damping) { return { response: response / 1000 * Theme.speed, dampingRatio: damping } }
  readonly property real exitFactor: Theme.core.motion.exitFactor
  Spring {
    id: lv
    reduced: Theme.reduceMotion
    preset: im.open ? im.preset(im.mc.liftResponse, im.mc.liftDamping) : im.preset(im.mc.liftResponse * im.exitFactor, Theme.core.surface.touchMenu.closeDamping)
    target: im.open ? 1 : 0
  }
  property real fade: open ? 1 : 0
  Behavior on fade { NumberAnimation { duration: im.open ? Theme.dur("fast") : Theme.exit(Theme.dur("fast")) } }
  readonly property real shown: menu.shown
  readonly property bool active: open || menu.active || lv.moving

  onOpenChanged: {
    if (!open) return
    // the pop starts at the pressed icon's size, not at its resting one
    if (mc.liftScale !== 1) lv.from((pressScale - 1) / (mc.liftScale - 1))
  }
  function contains(px, py) { return menu.contains(px, py) }
  function nearby(px, py, slack) { return menu.nearby(px, py, slack) }
  function rowAt(px, py) { return menu.rowAt(px, py) }
  function choose(i) { menu.choose(i) }

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

  // ---- the menu: out of the icon, past its lift
  VTouchMenu {
    id: menu
    anchors.fill: parent
    catchOutside: false               // HomeScreen takes every finger and asks us
    model: im.entries
    from: im.from ? { x: im.from.x, y: im.from.y, w: im.from.w, h: im.from.w } : null
    extraGap: im.from ? im.from.w * (im.mc.liftScale - 1) / 2 + im.mc.gap - Theme.core.surface.touchMenu.gap : 0
    open: im.open
    onTriggered: function (entry) { im.closeRequested(); im.chosen(entry) }
  }
}
