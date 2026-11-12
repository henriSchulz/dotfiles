import QtQuick
import QtQuick.Effects
import QtQuick.Window
import "file:///home/henri/.local/share/velum/qml/Velum"

// A folder's tile on the home screen (iPadOS): a light frosted plate the size of an icon's body
// with its first apps in a small grid. Also the plate that grows behind an icon a held one aims at.
Item {
  id: plate
  property real size: 0
  property var apps: []          // [{ id, name, icon }], at most cfg.miniCols²
  property var cfg               // surface.tablet.home.folder
  property real iconRadius: 0    // share of the size (home.iconRadius)
  // frosted: the wallpaper blurred behind it, as the dock does it — `wallRect` in the coordinates
  // `origin` is in (where this plate's top left corner sits there)
  property string wallSource: ""
  property rect wallRect
  property point origin
  property real blurMax: 0
  property real saturation: 0
  width: size
  height: size
  readonly property real pad: size * cfg.miniPad
  readonly property real gap: size * cfg.miniGap
  readonly property real mini: (size - 2 * pad - (cfg.miniCols - 1) * gap) / cfg.miniCols

  Item {
    anchors.fill: parent
    visible: !Theme.reduceTransparency && plate.wallSource !== ""
    layer.enabled: visible
    layer.effect: MultiEffect { maskEnabled: true; maskSource: plateMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
    Image {
      id: plateWall
      x: plate.wallRect.x - plate.origin.x
      y: plate.wallRect.y - plate.origin.y
      width: plate.wallRect.width
      height: plate.wallRect.height
      source: plate.wallSource
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: plate.wallRect.width / plate.cfg.blurDownscale
      sourceSize.height: plate.wallRect.height / plate.cfg.blurDownscale
      visible: false
      cache: true
    }
    MultiEffect {
      x: plateWall.x; y: plateWall.y; width: plateWall.width; height: plateWall.height
      source: plateWall
      blurEnabled: true
      blur: 1
      blurMax: plate.blurMax
      saturation: plate.saturation
    }
  }
  Item {
    id: plateMask
    anchors.fill: parent
    layer.enabled: true
    visible: false
    Rectangle { anchors.fill: parent; radius: plate.size * plate.iconRadius; color: plate.cfg.maskInk }
  }
  Rectangle {
    anchors.fill: parent
    radius: plate.size * plate.iconRadius
    color: plate.cfg.plate
    border.width: 1 / Screen.devicePixelRatio
    border.color: plate.cfg.plateRim
  }
  Grid {
    x: plate.pad
    y: plate.pad
    columns: plate.cfg.miniCols
    spacing: plate.gap
    Repeater {
      model: plate.apps
      Image {
        required property var modelData
        width: plate.mini
        height: width
        source: modelData.icon
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        asynchronous: true
        scale: VIconMetrics.scale(source)
      }
    }
  }
}
