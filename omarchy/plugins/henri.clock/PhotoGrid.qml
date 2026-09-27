import QtQuick
import QtQuick.Effects
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion

// Four photo tiles, full-bleed, masked to the widget's corner radius — the
// Photos widget of the Notification Center. `photos` is a list of
// { id, thumb } (thumbnail file paths); tiles fade in as they load.
Item {
  id: grid
  property var photos: []
  property int columns: 2
  property int rows: 2
  property real gap: 2
  property real radius: 20
  property color placeholderColor: "#14000000"
  property color placeholderInk: "#8c000000"
  property string placeholderText: "No photos yet"
  property string placeholderFont: "SF Pro"
  property real placeholderFontSize: 11

  readonly property real tileW: (width - gap * (columns - 1)) / columns
  readonly property real tileH: (height - gap * (rows - 1)) / rows
  readonly property var shown: photos.slice(0, columns * rows)

  // The grid sits on the card; only the mask keeps the corners round.
  layer.enabled: true
  layer.effect: MultiEffect {
    maskEnabled: true
    maskSource: gridMask
    maskThresholdMin: 0.5
    maskSpreadAtMin: 0.02
  }

  Rectangle {
    anchors.fill: parent
    color: grid.placeholderColor
    visible: grid.shown.length === 0
    Text {
      anchors.centerIn: parent
      text: grid.placeholderText
      font.family: grid.placeholderFont
      font.pixelSize: grid.placeholderFontSize
      color: grid.placeholderInk
    }
  }

  Repeater {
    model: grid.shown
    delegate: Item {
      id: slot
      required property var modelData
      required property int index
      x: (index % grid.columns) * (grid.tileW + grid.gap)
      y: Math.floor(index / grid.columns) * (grid.tileH + grid.gap)
      width: grid.tileW
      height: grid.tileH
      Rectangle { anchors.fill: parent; color: grid.placeholderColor }
      Image {
        anchors.fill: parent
        source: modelData && modelData.thumb ? "file://" + modelData.thumb : ""
        fillMode: Image.PreserveAspectCrop
        // Thumbnails are 360 × 480; decode to the tile's scale, keep the aspect.
        sourceSize.height: 320
        asynchronous: true
        smooth: true
        mipmap: true
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
      }
    }
  }

  Item {
    id: gridMask
    anchors.fill: parent
    visible: false
    layer.enabled: true
    Rectangle { anchors.fill: parent; radius: grid.radius }
  }
}
