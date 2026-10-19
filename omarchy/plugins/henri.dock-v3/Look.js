.pragma library
// Geometry and behaviour constants of the Dock, from apple-ui Apple.js (`dock`,
// the spec's values, not measured) — only the shape lives here; colours come
// from Velum's roles, motion from Velum's surface.dock tokens (Theme.core.surface.dock).
var dock = {
  tileSize: 48,          // Basisgröße (16–128)
  magnifiedSize: 96,     // Kachel unter dem Cursor (tileSize–128)
  tileMin: 16, tileMax: 128,
  magnificationRadius: 3, // Einflussradius in Kacheln je Seite
  gapFraction: 0.04,     // Abstand zwischen Kacheln, × Basisgröße
  gapMin: 2,
  padCross: 6,           // Innenabstand oben/unten (Querachse)
  padMain: 6,            // Innenabstand links/rechts (Hauptachse)
  separatorPad: 8,       // 1-px-Linie + 8 pt je Seite
  separatorFraction: 0.7, // Trennerlänge × Basisgröße
  radiusFactor: 0.37,    // Eckenradius des Hintergrunds ≈ 0,37 × Basisgröße …
  radiusMin: 10, radiusMax: 26,
  edgeGap: 4,            // Dock schwebt 4 pt über der Bildschirmkante
  iconBody: 0.82,        // sichtbarer Icon-Körper × Kachel
  iconShadowY: 1, iconShadowBlur: 1, iconShadowAlpha: 0.15,
  blur: 24, saturate: 1.8,
  labelGap: 10,          // Label 10 pt über dem vergrößerten Icon
  labelRadius: 6, labelPadY: 4, labelPadX: 10,
  labelArrowW: 10, labelArrowH: 5,
  labelFont: 13,
  indicator: 4, indicatorMin: 3, indicatorMax: 5, // Laufpunkt ø
  indicatorGap: 2,       // über der Innenkante des Hintergrunds
  badgeFraction: 0.4,    // Plakettenhöhe × Kachel
  badgeMin: 16, badgeFont: 12, badgePadX: 5,
  menuRadius: 8, menuPad: 5, menuMinWidth: 180, menuRow: 22, menuFont: 13,
  menuHighlightRadius: 4, menuSeparatorPad: 5,
  focusRing: 3,
  fanIcon: 48, fanMax: 12, fanAngle: 15, fanPill: 32, fanGap: 6,
  gridIcon: 64, gridCell: 96, gridColumns: 5, gridFont: 11, gridRadius: 12, gridPad: 12,
  listIcon: 16, listRow: 22,
  stackPeek: 3,          // „Stapel“-Kachel zeigt die obersten 3 Dateien
  thumbBadge: 0.35,      // App-Icon auf einer Fenster-Miniatur × Kachel
  triggerZone: 3,        // Auto-Hide: Trigger-Zone an der Bildschirmkante
  settingsWidth: 300
}

var flickDeceleration = 1500
var maximumFlickVelocity = 4000
