import QtQuick
import QtQuick.Effects
import "file:///home/henri/.local/share/velum/qml/Velum"

// Behind an open folder (iPadOS): the wallpaper, blurred, with a light shade so names stay legible.
Item {
  id: back
  property string wallSource: ""
  property rect wallRect          // the wallpaper's rect in this item's coordinates
  readonly property var fc: Theme.core.surface.tablet.home.folder
  readonly property var cfg: Theme.core.surface.tablet.home
  // over the blurred wallpaper (v4: the Material scrim, surface.material.color.scrim)
  property color tint: fc.backdropTint
  // the blur reaches past the wallpaper's rect by its radius: a blur mixes in the transparency beyond
  // its source, and a light frame showed along the screen's edges (as Home.qml's blurBox)
  readonly property real pad: fc.backdropBlur
  Image {
    id: wall
    x: back.wallRect.x - back.pad; y: back.wallRect.y - back.pad
    width: back.wallRect.width + 2 * back.pad; height: back.wallRect.height + 2 * back.pad
    source: back.wallSource
    fillMode: Image.PreserveAspectCrop
    sourceSize.width: wall.width / back.cfg.blurDownscale
    sourceSize.height: wall.height / back.cfg.blurDownscale
    visible: false
    cache: true
  }
  MultiEffect {
    x: wall.x; y: wall.y; width: wall.width; height: wall.height
    source: wall
    visible: !Theme.userReduceTransparency && back.wallSource !== ""
    blurEnabled: true
    blur: 1
    blurMax: back.fc.backdropBlur
    saturation: back.cfg.dock.saturation
  }
  Rectangle {
    anchors.fill: parent
    color: Theme.userReduceTransparency || back.wallSource === "" ? Theme.r.popover.bgOpaque : back.tint
  }
}
