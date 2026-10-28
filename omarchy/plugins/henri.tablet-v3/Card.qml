import QtQuick
import Quickshell
import Quickshell.Wayland
import "file:///home/henri/.local/share/velum/qml/Velum"
import "HomeModel.js" as HM

// One app as a card of the home gesture and the App Switcher (Home.qml): a snapshot of its window
// (until one arrives, its icon on the window background) at the app area's full size, moved only by
// transform — px / py the centre's offset, ps scale, pm morph into the icon (1 = icon), po opacity,
// pl the switcher's swipe up. The corners are an analytic mask in one shader pass
// (shaders/card.frag), so nothing is re-rendered while it moves.
//   jump(x, y, s, m, t)   follow a finger: sit there, measure the speed for the hand-off
//   to(k, target, kind)   spring k ("x" "y" "s" "m" "o" "l") to target, kind = Theme.spring name
//                         or a preset { response, dampingRatio }
Item {
  id: card

  required property var entry          // { key, address, toplevel, icon, name }
  property var cfg: Theme.core.surface.tablet.home
  property real areaW: 0
  property real areaH: 0
  property bool capture: false         // take (and keep) a snapshot of the window
  property real labelOn: 0             // the switcher's name above the card
  readonly property bool hasShot: shot.hasContent
  readonly property bool moving: anim.running

  property real px: 0
  property real py: 0
  property real ps: 1
  property real pm: 0
  property real po: 1
  property real pl: 0

  width: areaW
  height: areaH
  x: px
  y: py + pl
  scale: ps
  opacity: po
  visible: po > 0.002
  transformOrigin: Item.Center

  // ---- springs: one frame clock for all six values (SwiftUI response / dampingRatio, as Velum's Spring)
  property var _t: ({ x: 0, y: 0, s: 1, m: 0, o: 1, l: 0 })
  property var _v: ({ x: 0, y: 0, s: 0, m: 0, o: 0, l: 0 })
  property var _p: ({})
  property var _live: ({})
  property real _lastJump: 0
  readonly property var _names: ({ x: "px", y: "py", s: "ps", m: "pm", o: "po", l: "pl" })

  function value(k) { return card[_names[k]] }
  function velocity(k) { return _v[k] }
  function set(k, v) { card[_names[k]] = v; _t[k] = v; _v[k] = 0; delete _live[k] }
  function jump(x, y, s, m, t) {
    var dt = (t - _lastJump) / 1000
    var vals = { x: x, y: y, s: s, m: m }
    for (var k in vals) {
      var was = value(k)
      _v[k] = (_lastJump > 0 && dt > 0 && dt < 0.1) ? 0.6 * _v[k] + 0.4 * (vals[k] - was) / dt : 0
      card[_names[k]] = vals[k]; _t[k] = vals[k]; delete _live[k]
    }
    _lastJump = t
  }
  function to(k, target, kind, vel) {
    _t[k] = target
    if (vel !== undefined) _v[k] = vel
    _p[k] = typeof kind === "object" ? kind : Theme.spring(kind || "smooth")
    if (Theme.reduceMotion) { set(k, target); return }
    _live[k] = true
    _lastJump = 0
    if (!anim.running) anim.start()
  }
  function settled(keys) {
    for (var i = 0; i < keys.length; i++) if (_live[keys[i]]) return false
    return true
  }
  FrameAnimation {
    id: anim
    onTriggered: {
      var dt = Math.min(frameTime, 1 / 30), steps = 4, h = dt / steps, any = false
      for (var k in card._live) {
        var p = card._p[k], w = 2 * Math.PI / p.response, kk = w * w, c = 2 * p.dampingRatio * w
        var x = card.value(k), v = card._v[k], t = card._t[k]
        for (var i = 0; i < steps; i++) { var a = -kk * (x - t) - c * v; v += a * h; x += v * h }
        var scale = Math.max(1, Math.abs(t))
        if (Math.abs(x - t) < 0.0005 * scale && Math.abs(v) < 0.005 * scale) { x = t; v = 0; delete card._live[k] }
        else any = true
        card._v[k] = v
        card[card._names[k]] = x
      }
      if (!any) stop()
    }
  }

  // ---- the shadow under the card, its width following the morph's inset
  readonly property real inset: Math.max(0, Math.min(1, pm)) * Math.max(0, areaW - areaH) / 2
  readonly property real radius: HM.cardRadius(ps, Math.max(0, Math.min(1, pm)), areaH, cfg)
  Item {
    anchors.fill: parent
    anchors.leftMargin: card.inset
    anchors.rightMargin: card.inset
    opacity: Math.min(1, (1 - card.ps) * 3) * (1 - Math.max(0, Math.min(1, card.pm)))
    visible: opacity > 0.01
    VShadow { layers: Theme.r.popover.shadow; radius: card.radius }
  }

  // ---- the content: the window's snapshot, or its icon on the window background until it arrives
  Item {
    id: content
    anchors.fill: parent
    Rectangle {
      anchors.fill: parent
      color: Theme.r.bg.window
      visible: !shot.hasContent
      Image {
        anchors.centerIn: parent
        width: card.areaH * card.cfg.splashIcon
        height: width
        source: card.entry.icon || ""
        sourceSize.width: width
        sourceSize.height: height
        asynchronous: true
      }
    }
    ScreencopyView {
      id: shot
      anchors.fill: parent
      captureSource: card.capture && card.entry.toplevel ? card.entry.toplevel.wayland : null
      live: false
      paintCursor: false
    }
  }
  ShaderEffectSource {
    id: tex
    sourceItem: content
    hideSource: true
    visible: false
  }
  ShaderEffect {
    anchors.fill: parent
    property var source: tex
    property size size: Qt.size(card.width, card.height)
    property real inset: card.inset
    property real radius: card.radius
    property real aa: 1 / Math.max(card.ps, 0.05)
    property real fade: 1 - smooth(0.25, 0.85, card.pm)
    function smooth(a, b, x) { var t = Math.max(0, Math.min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t) }
    fragmentShader: Qt.resolvedUrl("shaders/card.frag.qsb")
  }
  // into the icon: the app's icon comes up as the content fades
  Image {
    anchors.centerIn: parent
    width: card.areaH
    height: width
    source: card.entry.icon || ""
    sourceSize.width: card.cfg.iconTexture
    sourceSize.height: card.cfg.iconTexture
    asynchronous: true
    opacity: { var t = Math.max(0, Math.min(1, (card.pm - 0.1) / 0.5)); return t * t * (3 - 2 * t) }
    visible: opacity > 0.01
  }

  // ---- the name above the card (App Switcher), kept at its size on screen
  Row {
    anchors.bottom: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottomMargin: card.cfg.labelAbove / Math.max(card.ps, 0.05)
    spacing: card.cfg.labelGap
    scale: 1 / Math.max(card.ps, 0.05)
    transformOrigin: Item.Bottom
    opacity: card.labelOn * (1 - Math.max(0, Math.min(1, card.pm)))
    visible: opacity > 0.01
    Image {
      anchors.verticalCenter: parent.verticalCenter
      width: card.cfg.labelIcon
      height: width
      source: card.entry.icon || ""
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      asynchronous: true
    }
    VText {
      anchors.verticalCenter: parent.verticalCenter
      text: card.entry.name || ""
      font.weight: Font.DemiBold
      color: Theme.core.surface.launchpad.label
      style: Text.Raised
      styleColor: Theme.core.surface.tablet.home.labelShade
    }
  }
}
