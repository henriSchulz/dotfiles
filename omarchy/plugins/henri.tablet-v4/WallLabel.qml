import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// A name under an icon on the wallpaper (the Material home screen): white Roboto body2 over a soft
// shadow (lab: textShadow 0 1px 2px black 0.6). The shadow text is drawn at a fraction of its
// resolution and scaled up, so its edge is soft without a blur pass; both are static layers.
Item {
  id: lb
  readonly property var mc: Theme.core.surface.material.color
  property alias text: main.text
  property color color: mc.label
  readonly property real paintedWidth: main.paintedWidth
  MText {
    width: parent.width
    height: parent.height
    y: lb.mc.labelShadowY
    horizontalAlignment: Text.AlignHCenter
    text: main.text
    color: lb.mc.labelShadow
    layer.enabled: true
    layer.smooth: true
    layer.textureSize: Qt.size(Math.max(1, Math.ceil(width * lb.mc.labelShadowSoft)), Math.max(1, Math.ceil(height * lb.mc.labelShadowSoft)))
  }
  MText {
    id: main
    width: parent.width
    height: parent.height
    horizontalAlignment: Text.AlignHCenter
    color: lb.color
  }
}
