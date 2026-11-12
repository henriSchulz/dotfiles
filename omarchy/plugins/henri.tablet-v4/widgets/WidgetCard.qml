import QtQuick
import Quickshell.Widgets
import "file:///home/henri/.local/share/velum/qml/Velum"

// The Material card every home screen widget sits on (MUI Card on the lab's theme: shape 12 × 1.75,
// background.paper with elevation 1). What is declared inside is clipped to its corners.
//   WidgetCard { width; height; VText { … } }    tone: "paper" (default) or "photo" (grey.900)
Item {
  id: wc
  default property alias content: inner.data
  property string tone: "paper"
  readonly property var cfg: Theme.core.surface.material.widgets

  VShadow {
    layers: [{ color: wc.cfg.shadow, offsetX: 0, offsetY: wc.cfg.shadowY, blur: wc.cfg.shadowBlur, spread: 0 }]
    radius: wc.cfg.radius
  }
  ClippingRectangle {
    id: inner
    anchors.fill: parent
    radius: wc.cfg.radius
    color: wc.tone === "photo" ? wc.cfg.photo.empty : Theme.dark ? wc.cfg.cardDark : wc.cfg.cardLight
  }
}
