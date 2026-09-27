import QtQuick
import QtQuick.Effects
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion

// One photo, full-bleed and masked to the widget's corner radius, with the
// date on a soft gradient at the bottom — the Photos widget of the
// Notification Center, like the featured photo of macOS' Photos widget.
// `photo` is { src, taken } (image file path, ISO timestamp) or null.
Item {
  id: tile
  property var photo: null
  property real radius: 20
  property color placeholderColor: "#14000000"
  property color placeholderInk: "#8c000000"
  property string placeholderText: "No photos yet"
  property string captionFont: "SF Pro"
  property real captionFontSize: 13
  property string caption: ""

  readonly property string source: photo && photo.src ? "file://" + photo.src : ""

  // The tile sits on the card; only the mask keeps the corners round.
  layer.enabled: true
  layer.effect: MultiEffect {
    maskEnabled: true
    maskSource: tileMask
    maskThresholdMin: 0.5
    maskSpreadAtMin: 0.02
  }

  Rectangle {
    anchors.fill: parent
    color: tile.placeholderColor
    Text {
      anchors.centerIn: parent
      visible: tile.source === ""
      text: tile.placeholderText
      font.family: tile.captionFont
      font.pixelSize: tile.captionFontSize
      color: tile.placeholderInk
    }
  }

  // Two images: the next photo loads into the hidden one and fades over the
  // visible one once it is ready, so a change never flashes the placeholder.
  readonly property Image front: useA ? imageA : imageB
  readonly property Image back: useA ? imageB : imageA
  property bool useA: true
  onSourceChanged: {
    if (source === "") { imageA.source = ""; imageB.source = ""; return }
    if (front.source == source) return
    back.source = source
    if (back.status === Image.Ready) useA = !useA
  }
  Component.onCompleted: imageA.source = source

  component Photo: Image {
    anchors.fill: parent
    fillMode: Image.PreserveAspectCrop
    sourceSize.width: 1024
    asynchronous: true
    smooth: true
    mipmap: true
    readonly property bool shown: tile.front === this && status === Image.Ready
    opacity: shown ? 1 : 0
    z: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    onStatusChanged: if (status === Image.Ready && tile.back === this && tile.source !== "" && source == tile.source) tile.useA = !tile.useA
  }
  Photo { id: imageA }
  Photo { id: imageB }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: parent.height * 0.32
    z: 2
    visible: tile.caption !== "" && tile.front.opacity > 0
    opacity: tile.front.opacity
    gradient: Gradient {
      GradientStop { position: 0; color: "#00000000" }
      GradientStop { position: 1; color: "#80000000" }
    }
  }
  Text {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.margins: tile.radius * 0.7
    text: tile.caption
    z: 2
    visible: tile.caption !== ""
    opacity: tile.front.opacity
    font.family: tile.captionFont
    font.pixelSize: tile.captionFontSize
    font.weight: Font.DemiBold
    color: "#ffffff"
    style: Text.Raised
    styleColor: "#40000000"
  }

  Item {
    id: tileMask
    anchors.fill: parent
    visible: false
    layer.enabled: true
    Rectangle { anchors.fill: parent; radius: tile.radius }
  }
}
