.pragma library
// Spotlight geometry (points; the plugin scales them with Style.space), taken
// over unchanged from apple-ui Apple.js `spotlight` (measured on macOS Tahoe
// screenshots). Colours and motion come from Velum, not from here.
var spotlight = {
  topFraction: 0.23,     // Oberkante des Feldes bei 23 % der Bildschirmhöhe (Spec)
  // Kompakte Kapsel (nichts getippt): 438 × 63,5 px / 1,33
  compactWidth: 330,
  compactHeight: 48,
  fieldInset: 18,        // Kapselrand → Lupe (24 px)
  fieldIcon: 20,         // SF magnifyingglass (26 px hoch)
  fieldGap: 16,          // Lupe → Text/Caret (22 px)
  fieldFont: 22,         // Regular
  fieldLine: 1.2,
  caret: 2,
  chipHeight: 22,        // Kategorie-Token links im Feld
  chipFont: 12,
  chipPadX: 8,
  // Runde Kategorie-Buttons rechts neben der Kapsel: 62 px ø, 11 px Abstand, 12 px zum Feld
  button: 46,
  buttonIcon: 21,
  buttonGap: 8,
  buttonOffset: 9,
  // Aufgeklappt: ein Panel (851 × 522 px / 1,54), Feldzeile oben, Trennlinie,
  // Filter-Kapseln, zweizeilige Ergebnisse
  width: 560,
  radius: 20,            // Kantenprofil ≈ 30 px
  fieldRow: 50,          // Höhe der Suchzeile im Panel (Trennlinie bei 76 px)
  panelInset: 17,        // Lupe, Trennlinie und Kapseln 26 px vom Rand
  capsuleTop: 58,        // Filter-Kapseln: Oberkante ab Panel-Oberkante
  capsuleHeight: 21,     // 32 px
  capsuleGap: 7,         // 11 px
  capsuleFont: 13,
  rowsTop: 89,           // erste Zeile ab Panel-Oberkante (287 px)
  rowInset: 8,           // Zeilen 13 px vom Panelrand
  rowHeight: 49,         // Zeilenraster 75 px
  rowIcon: 25,           // 38 px App-Icon
  rowIconInset: 10,      // Icon 16 px ab Zeilenrand
  rowTextX: 55,          // Text 83 px ab Zeilenrand
  rowRadius: 8,
  titleFont: 15,         // Regular
  subtitleFont: 13,      // sekundär
  metaFont: 12,          // rechts („Yesterday“), sekundär
  metaInset: 8,
  calcFont: 28,
  shortcutW: 24,         // Kürzel-Chip („sm“) 37 × 26 px
  shortcutH: 17,
  shortcutRadius: 5,
  shortcutFont: 11,
  bottomPad: 7,
  resultsMaxHeight: 480,
  // Aktionsseite (→ auf einem Treffer): Kopf mit dem Treffer, dann kompakte
  // einzeilige Zeilen in Gruppen — bewusst anders als die Ergebnisliste
  // (Spec §7: 36-pt-Zeilen, 11-pt-Überschriften in normaler Schreibung).
  actionHeader: 49,
  actionRowHeight: 36,
  actionFont: 13,
  sectionFont: 11,
  sectionTop: 8,
  sectionTopFirst: 4,
  sectionBottom: 2,
  // Info-Blatt (Get Info): Eigenschaftszeilen Label | Wert, nichts auswählbar
  infoRowHeight: 24,
  infoLabelWidth: 84,
  infoPad: 6,
  shadowOffset: 22,      // Spec: 0 22px 70px 4px
  shadowBlur: 70,
  shadowSpread: 4,
  contactOffset: 4,
  contactBlur: 12,
  contactAlpha: 0.12
}

function sf(cp) { return String.fromCodePoint(cp) }
// list flicking, as henri-ui Motion.js (Velum has no scroll tokens yet)
var flickDeceleration = 1500
var maximumFlickVelocity = 4000
