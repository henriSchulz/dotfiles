import QtQuick
import qs.Commons
import qs.Ui
import "Motion.js" as Motion

// Material for menus, popovers, panels, toasts: theme background, hairline,
// radius by role. Put it inside HUi.Reveal; children go into the content area.
//
//   HUi.Surface { role: "popups"; kind: "popover"; padding: Style.spacing.popupPadding; … }
BorderSurface {
  id: root

  property string role: "popups"      // popups | menu | tooltip | notifications (Color.<role>)
  property string kind: "popover"     // panel | popover | menu | chip → radius
  readonly property var palette: Color[role] || Color.popups

  // Glass drops the theme's near-opaque alpha so the compositor's blur shows
  // through; otherwise the theme decides, alpha included.
  color: Motion.glass
    ? Util.alpha(palette.background, kind === "menu" ? Motion.glassMenuAlpha : Motion.glassAlpha)
    : palette.background
  radius: Style.space(kind === "panel" ? Motion.radiusPanel
    : kind === "chip" ? Motion.radiusChip : Motion.radiusPopover)
  borderSpec: Border.surfaceSpec(role, "border",
    Util.alpha(Color.foreground, Motion.hairlineAlpha), 1)

  GlassSheen {
    anchors.fill: parent
    radius: root.radius
  }
}
