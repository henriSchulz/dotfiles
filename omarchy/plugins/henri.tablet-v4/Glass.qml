import QtQuick
import QtQuick.Effects
import "file:///home/henri/.local/share/velum/qml/Velum"

// A floating surface of the Material home screen on Velum's glass (the lab's influence: theme.js
// `glass`): the popover material and its layered shadow, an inset rim, over the wallpaper blurred
// from a small copy into a cached layer (as the v3 dock does it) — never a live blur of what moves.
// The surface's own transform (a Grow) leaves the cached layer alone.
Item {
  id: gl
  property real radius: 0
  property color rim: "transparent"   // lint-ok: set by the owner (mode-dependent)
  // the wallpaper as the compositor draws it, in the coordinates `origin` is in (this item's top left there)
  property string wallSource: ""
  property rect wallRect
  property point origin
  readonly property var dk: Theme.core.surface.tablet.home.dock
  readonly property var hm: Theme.core.surface.tablet.home

  VShadow { layers: Theme.r.popover.shadow; radius: gl.radius }
  Item {
    anchors.fill: parent
    visible: !Theme.userReduceTransparency && gl.wallSource !== ""
    layer.enabled: visible
    layer.effect: MultiEffect { maskEnabled: true; maskSource: glassMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
    Image {
      id: wall
      x: gl.wallRect.x - gl.origin.x
      y: gl.wallRect.y - gl.origin.y
      width: gl.wallRect.width
      height: gl.wallRect.height
      source: gl.wallSource
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: Math.max(1, gl.wallRect.width / gl.hm.blurDownscale)
      sourceSize.height: Math.max(1, gl.wallRect.height / gl.hm.blurDownscale)
      visible: false
      cache: true
    }
    MultiEffect {
      x: wall.x; y: wall.y; width: wall.width; height: wall.height
      source: wall
      blurEnabled: true
      blur: 1
      blurMax: gl.dk.blurMax
      saturation: gl.dk.saturation
    }
  }
  Item {
    id: glassMask
    anchors.fill: parent
    layer.enabled: true
    visible: false
    Rectangle { anchors.fill: parent; radius: gl.radius; color: Theme.core.surface.tablet.home.folder.maskInk }
  }
  Rectangle {
    anchors.fill: parent
    radius: gl.radius
    color: Theme.userReduceTransparency ? Theme.r.popover.bgOpaque : Theme.r.popover.bg
    border.width: 1
    border.color: gl.rim
  }
}
