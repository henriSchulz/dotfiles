import QtQuick
import qs.Commons
import "Motion.js" as Motion

// The lit top edge of a glass surface, like macOS Tahoe: a white veil that is
// strongest at the very top and gone by 45 % of the height. Only the light
// makes a translucent panel read as glass rather than as a weak fill.
//
// Put it directly inside a surface, above the fill and below the content — the
// components that own a surface (Surface, PopupCard, PopupPanel) already do.
// It draws nothing unless the experimental glass mode is on.
//
//   HUi.GlassSheen { anchors.fill: parent; radius: card.radius }
Rectangle {
  id: root

  property real sheen: Motion.glassSheen

  visible: Motion.glass && opacity > 0
  opacity: Motion.glass ? 1 : 0
  // The surface itself fades in; this only has to follow a mode change, which
  // costs a shell restart anyway, so a plain crossfade is enough.
  Behavior on opacity {
    NumberAnimation {
      duration: Motion.fast
      easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
    }
  }

  color: "transparent"
  gradient: Gradient {
    GradientStop { position: 0.0; color: Util.alpha("#ffffff", root.sheen) }
    GradientStop { position: 0.45; color: Util.alpha("#ffffff", 0) }
  }
}
