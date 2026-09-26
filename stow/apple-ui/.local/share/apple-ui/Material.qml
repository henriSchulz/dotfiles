import QtQuick
import "Apple.js" as Apple

// Palette-Objekt für ein Plugin: `dark` wählt zwischen dunklem (gemessenem)
// und hellem (gescraptem) Glas. Am obersten Inhalts-Item als `appleMaterial`
// veröffentlichen, dann finden alle AUi-Komponenten es von selbst.
//
//   AUi.Material { id: mat; dark: backdrop.dark }
//   Item { property var appleMaterial: mat; … }
QtObject {
  property bool dark: false
  readonly property var p: dark ? Apple.darkGlass : Apple.light

  readonly property color ink: p.ink
  readonly property color inkSecondary: p.inkSecondary
  readonly property color inkMuted: p.inkMuted
  readonly property color sheet: p.sheet
  readonly property color tile: p.tile
  readonly property color tileHover: p.tileHover
  readonly property color hairline: p.hairline
  readonly property color badgeOn: p.badgeOn
  readonly property color badgeOnGlyph: p.badgeOnGlyph
  readonly property color badgeOff: p.badgeOff
  readonly property color badgeOffGlyph: p.badgeOffGlyph
  readonly property color sliderTrack: p.sliderTrack
  readonly property color sliderFill: p.sliderFill
  readonly property color capsule: p.capsule
  readonly property color artPlaceholder: p.artPlaceholder
  readonly property color rowHover: p.rowHover
  readonly property color field: p.field
  readonly property color cursorRing: p.cursorRing
  readonly property color accent: p.accent
  readonly property color urgent: p.urgent
  readonly property color ok: p.ok
}
