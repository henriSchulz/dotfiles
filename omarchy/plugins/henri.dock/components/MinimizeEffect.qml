import QtQuick
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "../DockModel.js" as DockModel

// Minimize / restore animation (spec §12) drawn from a window snapshot the
// dock holds in its vault: genie (N strips flowing through a funnel into the
// tile) or linear scale. progress 0 = window, 1 = tile. Reduce motion: a
// plain crossfade at the window's place.
Item {
  id: fx
  property var dock
  property var snap: null
  property var win: ({ u0: 0, u1: 1, vNear: 0, vFar: 1 })
  property var tile: ({ u0: 0, u1: 1, vNear: 0, vFar: 1 })
  property string mode: "genie"
  property bool reverse: false
  property bool reduce: false
  property real progress: 0
  readonly property bool running: anim.running
  readonly property int stripCount: 48
  signal finished()

  anchors.fill: parent
  visible: running

  function play(snapshot, winRect, tileRect, effect, backwards, slow) {
    snap = snapshot
    win = winRect
    tile = tileRect
    mode = effect
    reverse = backwards
    reduce = dock.reduceMotion
    anim.stop()
    var base = reduce ? Motion.dock.scaleMinimize : (mode === "genie" ? Motion.dock.genie : Motion.dock.scaleMinimize)
    anim.duration = base * (slow ? Motion.dock.slowMotion : 1)
    progress = backwards ? 1 : 0
    anim.to = backwards ? 0 : 1
    updateStrips()
    anim.start()
  }

  NumberAnimation {
    id: anim
    target: fx
    property: "progress"
    easing.type: fx.mode === "scale" ? Easing.BezierSpline : Easing.Linear
    easing.bezierCurve: Motion.easeInOut
    onFinished: fx.finished()
  }

  onProgressChanged: updateStrips()

  function toRect(u, v, w, h) { return dock.rectFor(u + w / 2, v, w, h) }

  function updateStrips() {
    if (!running && progress !== 0 && progress !== 1) return
    if (mode !== "genie" || reduce) return
    var rects = DockModel.genieStrips(progress, win, tile, stripCount)
    for (var k = 0; k < rects.length && k < strips.count; k++) {
      var s = strips.itemAt(k)
      if (!s) continue
      var r = toRect(rects[k].u, rects[k].v, rects[k].w, rects[k].h)
      s.x = r.x; s.y = r.y; s.width = Math.max(1, r.w); s.height = Math.max(1, r.h)
    }
  }

  // ---- genie strips
  Repeater {
    id: strips
    model: fx.mode === "genie" && !fx.reduce && fx.snap ? fx.stripCount : 0
    delegate: Item {
      id: strip
      required property int index
      readonly property real sw: fx.snap ? fx.snap.width : 1
      readonly property real sh: fx.snap ? fx.snap.height : 1
      readonly property real n: fx.stripCount
      // Strip 0 is the window edge next to the dock.
      readonly property rect src: dock.position === "bottom" ? Qt.rect(0, sh * (1 - (index + 1) / n), sw, sh / n)
                                : dock.position === "left" ? Qt.rect(sw * index / n, 0, sw / n, sh)
                                : Qt.rect(sw * (1 - (index + 1) / n), 0, sw / n, sh)
      ShaderEffectSource {
        anchors.fill: parent
        sourceItem: fx.snap
        sourceRect: strip.src
        live: false
        hideSource: false
        smooth: true
        Component.onCompleted: scheduleUpdate()
      }
    }
  }

  // ---- linear scale (or reduce-motion crossfade)
  Item {
    id: whole
    visible: fx.snap !== null && (fx.mode === "scale" || fx.reduce)
    readonly property real e: fx.reduce ? 0 : fx.progress
    readonly property real u0: fx.win.u0 + (fx.tile.u0 - fx.win.u0) * e
    readonly property real u1: fx.win.u1 + (fx.tile.u1 - fx.win.u1) * e
    readonly property real vNear: fx.win.vNear + (fx.tile.vNear - fx.win.vNear) * e
    readonly property real vFar: fx.win.vFar + (fx.tile.vFar - fx.win.vFar) * e
    readonly property var r: fx.toRect(u0, vNear, Math.max(1, u1 - u0), Math.max(1, vFar - vNear))
    x: r.x; y: r.y; width: r.w; height: r.h
    opacity: fx.reduce ? 1 - fx.progress : 1
    ShaderEffectSource {
      anchors.fill: parent
      sourceItem: fx.snap
      live: false
      hideSource: false
      smooth: true
      Component.onCompleted: scheduleUpdate()
    }
  }
}
