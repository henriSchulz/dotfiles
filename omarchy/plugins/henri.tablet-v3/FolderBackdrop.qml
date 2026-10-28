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
  Image {
    id: wall
    x: back.wallRect.x; y: back.wallRect.y; width: back.wallRect.width; height: back.wallRect.height
    source: back.wallSource
    fillMode: Image.PreserveAspectCrop
    sourceSize.width: back.wallRect.width / back.cfg.blurDownscale
    sourceSize.height: back.wallRect.height / back.cfg.blurDownscale
    visible: false
    cache: true
  }
  MultiEffect {
    x: wall.x; y: wall.y; width: wall.width; height: wall.height
    source: wall
    visible: !Theme.reduceTransparency && back.wallSource !== ""
    blurEnabled: true
    blur: 1
    blurMax: back.fc.backdropBlur
    saturation: back.cfg.dock.saturation
  }
  Rectangle {
    anchors.fill: parent
    color: Theme.reduceTransparency || back.wallSource === "" ? Theme.r.popover.bgOpaque : back.fc.backdropTint
  }
}
