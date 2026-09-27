.pragma library
// Apple UI — Design-Tokens, gemessen und gescrapt an echtem macOS (Tahoe).
// Gegenstück zu henri-ui/Motion.js: EINE Quelle für alle Plugins/Apps, die
// den echten Apple-Look wollen. Bewegung kommt weiterhin aus henri-ui.
//
// Quellen (Stand 2026-09-26):
//   * ~/macos-scrape/dist/macos-tokens.json (Run 20260925T204357Z):
//     NSColor-Werte (light appearance), Typografie-Punktgrößen.
//   * ~/macos-scrape/controlCenter-fixed/ax.json: Geometrie des Control Centers
//     in Punkten (Kachelgrößen, Abstände, Slider, Badges, Edit-Controls).
//   * ~/macos-scrape/controlCenter-fixed/screen.png (2x): Pixelmessungen für
//     Glas-Alphas, Haarlinie, Slider-Track, Eckenradius, Badge-Maße.
//
// Einbinden (QML):
//   import "file:///home/henri/.local/share/apple-ui/Apple.js" as Apple
//   import "file:///home/henri/.local/share/apple-ui" as AUi
// Punkt-Werte werden im Plugin mit Style.space(pt) auf die Shell-Skala gebracht.

// Geltungsbereich: die Geometrie-, Radius- und Material-Werte unten sind am
// Control Center gemessen und gelten für Menüleisten-Popups. Eine App (Fenster,
// Sidebar, Toolbar, Sheet) bekommt eigene, an ihrer Referenzfläche gemessene
// Abschnitte — die Popup-Werte nicht dafür zweckentfremden. NSColor und
// Typografie gelten flächenunabhängig. Siehe henri-ui references/apple.md.

// ---- Schriften. SF Pro / SF Symbols sind lokal installiert (nie committen).
var uiFont = "SF Pro"
var symbolFont = ".SF Symbols Fallback"
function sf(cp) { return String.fromCodePoint(cp) }

// ---- Typografie (pointSize, macos-tokens.json → typography)
var largeTitle = 26
var title1 = 22
var title2 = 17
var title3 = 15
var headline = 13      // bold
var body = 13
var callout = 12
var subheadline = 11
var footnote = 10
var caption = 10

// ---- NSColor (light, macos-tokens.json → colors), als #AARRGGBB
var accent = "#ff007aff"            // controlAccentBlueColor
var label = "#d8000000"             // labelColor α 0.847
var secondaryLabel = "#7f000000"    // secondaryLabelColor α 0.498
var tertiaryLabel = "#42000000"     // tertiaryLabelColor α 0.259
var separator = "#19000000"         // separatorColor α 0.098
var systemFill = "#19000000"        // systemFillColor α 0.098
var secondarySystemFill = "#14000000"
var systemRed = "#ffff383c"
var systemGreen = "#ff34c759"
var systemOrange = "#ffff8d28"
var systemYellow = "#ffffcc00"
var systemGray = "#ff8e8e93"
var selectedMenuItem = "#ff4277f4"
var linkColor = "#ff0068da"

// ---- Control-Center-Geometrie in Punkten (ax.json + screen.png)
var contentWidth = 292   // Inhaltsbreite des Panels
var padding = 10         // Sheet-Rand → Kacheln
var gap = 12             // Abstand zwischen Kacheln
var tile = 140           // halbe Kachel
var tileH = 64           // Kachelhöhe
var circle = 64          // runde Icon-Kachel
var badge = 36           // Icon-Badge in Wi-Fi/Bluetooth-Kacheln
var badgeInset = 14      // Badge-Einrückung
var textX = 57           // Textspalte neben dem Badge
var labelInset = 16      // Titel "Display"/"Sound" links
var labelTop = 11        // Titel oben
var sliderY = 42         // Slider-Mitte unter der Kachel-Oberkante
var sliderH = 4          // Track-Höhe
var art = 40             // Now-Playing-Cover
var artInset = 14
var transport = 26       // Transport-Buttons
var transportY = 100
var capsuleW = 94        // "Edit Controls" 93.5 × 24
var capsuleH = 24
var capsuleGap = 16
var airplay = 26
var rowH = 44            // Listenzeile (Detailseiten)
var pageHeaderH = 36
var switchW = 38         // NSSwitch regular
var switchH = 22
var iconButton = 30

// ---- Radien (screen.png gemessen: ~22 pt auf einer 64-pt-Kachel)
var radius = 22
var radiusArt = 8
var radiusRow = 10
var radiusControl = 8
var radiusPill = 999

// ---- Fenster (App): am Finder gemessen (macOS 26.2, Light, 2x) —
// ~/macos-scrape/20260925T204357Z/system/finder.{icon,list,column}View
// (ax.json = Punkte, window.png = Pixelmessung). Eigener Abschnitt, nicht die
// Popup-Werte oben. Referenz-App: ~/Projects/finder.
var window = {
  bg: "#fffbfbfb",            // Fensterhintergrund (Toolbar-Zone), gemessen 251
  content: "#ffffffff",       // Inhaltsfläche
  sidebar: "#fffafafa",       // Sidebar-Karte, gemessen 250
  sidebarInset: 8,            // Karte 8 pt vom Fensterrand
  sidebarRadius: 18,          // Kartenradius (Kantenprofil, r ≈ 36 px)
  sidebarShadow: "0 0 8px rgba(0,0,0,0.05)",
  sidebarHighlight: "#ffffffff",  // 1 px innere Kante
  sidebarWidth: 226,
  sidebarTop: 44,             // erste Zeile 44 pt unter der Kartenoberkante (Ampel-Zone)
  sidebarRow: 32,
  sidebarHeader: 19,          // Abschnittszeile ("Favorites"), 11 pt bold, secondaryLabel
  sidebarHeaderGap: 13,       // Abstand vor einer Abschnittszeile
  sidebarIconX: 18,           // Symbol-Linke ab Kartenrand
  sidebarTextX: 45,           // Text-Linke ab Kartenrand
  sidebarHeaderX: 15,
  sidebarSelInset: 10,        // Auswahl-Kapsel 10 pt von den Kartenrändern
  sidebarSelected: "#14000000",   // secondarySystemFill α 0.078 (gemessen 231 auf 250)
  sidebarSelectedRadius: 8,
  radius: 20,                 // Fensterecken (Kantenprofil, r ≈ 42 px)
  toolbar: 52,
  toolbarInset: 8,
  toolbarGap: 12,
  capsule: 38,                // Toolbar-Kapsel
  segment: 36,                // Knopf in der Kapsel
  capsuleFill: "#ffffffff",
  capsuleShadow: "0 1px 2px rgba(0,0,0,0.05)",
  title: 15,                  // Fenstertitel, semibold (Cap-Höhe 11 pt)
  titleColor: "#ff4c4c4c",    // gemessen 76
  traffic: 12,                // Ampel-Punkte
  trafficPitch: 23,
  trafficX: 18, trafficY: 18, // Mitte des ersten Punkts ab Kartenecke
  trafficClose: "#ffff5f57", trafficMin: "#fffebc2e", trafficZoom: "#ff28c840",
  trafficInactive: "#ffd0d0d3",
  listHeader: 28,
  listHeaderGap: 5,
  listRow: 20,
  listInset: 10,              // Spaltenbeginn ab Inhaltsrand
  listIconX: 27,
  listTextX: 47,
  zebra: "#fff4f5f5",         // alternatingContentBackgroundColor (exakt)
  grid: "#ffe6e6e6",          // gridColor (Kopfzeilen-Trenner)
  iconCell: 112,
  icon: 64,
  iconTop: 4,
  iconLabelGap: 7,
  iconInset: 10,
  column: 238,
  columnRow: 22,
  columnTextX: 33,
  columnSelInset: 6,
  columnSelRadius: 6,
  status: 22,
  text: 13,                   // Zeilen-/Label-Text (Cap-Höhe 9–9,5 pt)
  small: 11,                  // Kopfzeilen, Abschnitte, Statuszeile
  disabled: "#42000000"       // tertiaryLabel (gemessen 189: Nav-Chevrons inaktiv)
}

// ---- Material. Zwei Paletten: dunkles Glas (am Screenshot gemessen) und
// helles Glas (Scrape-Farben). Welche gilt, entscheidet die Helligkeit des
// Hintergrunds unter dem Panel (AUi.Backdrop) — wie macOS.
var darkBelowLuma = 0.75

var light = {
  dark: false,
  ink: label,
  inkSecondary: secondaryLabel,
  inkMuted: secondaryLabel,
  sheet: "#73ffffff",          // Weiß α 0.45 (+ Compositor-Blur)
  tile: "#66ffffff",           // Weiß α 0.40
  tileHover: "#8cffffff",      // Weiß α 0.55
  hairline: separator,
  badgeOn: accent,
  badgeOnGlyph: "#ffffffff",
  badgeOff: systemFill,
  badgeOffGlyph: label,
  sliderTrack: systemFill,
  sliderFill: "#ffffffff",
  capsule: "#0f000000",        // Schwarz α 0.06
  artPlaceholder: "#0f000000",
  rowHover: "#66ffffff",
  field: "#66ffffff",
  cursorRing: accent,
  accent: accent,
  urgent: systemRed,
  ok: systemGreen
}

var darkGlass = {
  dark: true,
  ink: "#ffffffff",
  inkSecondary: "#ffffffff",  // gemessen: SSID-Zeile ist reines Weiß, Hierarchie nur über Gewicht
  inkMuted: "#8cffffff",
  sheet: "#59292929",          // Grau 0.16 α 0.35 (über ignore_alpha 0.3, sonst kein Blur)
  tile: "#26ffffff",           // Weiß α 0.15 (gemessen)
  tileHover: "#40ffffff",      // Weiß α 0.25
  hairline: "#47ffffff",       // Weiß α 0.28 (gemessen ~0.5 auf 0.5 pt)
  badgeOn: "#ffffffff",        // gemessen: weißer Kreis …
  badgeOnGlyph: accent,        // … mit Akzent-Glyphe
  badgeOff: "#40ffffff",       // Weiß α 0.25 (gemessen)
  badgeOffGlyph: "#ffffffff",
  sliderTrack: "#33000000",    // Schwarz α 0.20 (gemessen)
  sliderFill: "#ffffffff",
  capsule: "#40ffffff",        // Weiß α 0.25 (gemessen)
  artPlaceholder: "#26ffffff",
  rowHover: "#26ffffff",
  field: "#26ffffff",
  cursorRing: "#ffffffff",
  accent: accent,
  urgent: systemRed,
  ok: systemGreen
}

function palette(dark) { return dark ? darkGlass : light }

// Komponenten finden ihr Material über die Item-Hierarchie: irgendein
// Vorfahre trägt `appleMaterial` (ein AUi.Material). Ohne Fund: helle Palette.
// Innerhalb eines Popup-Fensters muss das Material am obersten Inhalts-Item
// hängen — die Item-Kette endet am Fenster, nicht am QML-Wurzelobjekt.
function lookup(item, name, fallback) {
  var p = item
  while (p) {
    if (p[name] !== undefined) return p[name]
    p = p.parent
  }
  return fallback
}
function material(item) { return lookup(item, "appleMaterial", light) }

// ---- Spotlight (macOS 26 „Tahoe“, Liquid Glass). Eigener Abschnitt, nicht
// die Popup-Werte oben. Gemessen 2026-09-26 an Apples Support-Screenshots
// (~/Downloads/f8089fdb… Feld + Buttons, ~/Downloads/ba1156d1… aufgeklappt);
// Skala je Bild über die Breite von SF-Pro-Text (Feldtext 22 pt, Zeilentitel
// 15, Untertitel/Kapseln 13, Meta 12 — drei unabhängige Anker stimmten auf
// 1,54 px/pt bzw. 1,33 px/pt überein). Farben/Alphas per Pixelmessung, die
// dunkle Palette ist abgeleitet (kein dunkler Screenshot). Referenz-Plugin:
// ~/.config/omarchy/plugins/henri.menu. Punkt-Werte → Style.space(pt).
// Die Auswahl ist eine leichte Tönung, kein Akzent-Balken (Text bleibt Ink).
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
  buttonSlide: 8,
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
  shadowOffset: 22,      // Spec: 0 22px 70px 4px
  shadowBlur: 70,
  shadowSpread: 4,
  contactOffset: 4,
  contactBlur: 12,
  contactAlpha: 0.12,
  light: {
    dark: false,
    fill: "#73ffffff",          // Weiß α 0.45 über dem Blur (gemessen ≈ 0.4)
    opaqueFill: "#ffececec",    // „Transparenz reduzieren“
    border: "#1a000000",
    highlight: "#99ffffff",
    textPrimary: "#d9000000",   // 0.85
    textSecondary: "#80000000", // 0.50
    textTertiary: "#4d000000",  // 0.30
    separator: "#0f000000",     // Trennlinie unter der Suchzeile (gemessen sehr zart)
    selectionFill: "#1a000000", // Auswahl: Schwarz α 0.10 (gemessen 0.08–0.15)
    selectionBorder: "#66ffffff",
    capsule: "#99ffffff",       // Filter-Kapseln: Weiß α 0.60 (gemessen 243 auf ~250)
    capsuleSelected: "#e6ffffff",
    shortcut: "#a6ffffff",      // Kürzel-Chip: Weiß α 0.65 (gemessen 230 neutral)
    hover: "#0d000000",
    shadowAlpha: 0.35
  },
  dark: {
    dark: true,
    fill: "#b328282a",          // rgba(40,40,42,0.70) (Spec, kein dunkler Screenshot)
    opaqueFill: "#ff2a2a2c",
    border: "#24ffffff",
    highlight: "#38ffffff",
    textPrimary: "#e6ffffff",
    textSecondary: "#8cffffff",
    textTertiary: "#4dffffff",
    separator: "#14ffffff",
    selectionFill: "#26ffffff", // Weiß α 0.15
    selectionBorder: "#1fffffff",
    capsule: "#1fffffff",       // Weiß α 0.12
    capsuleSelected: "#40ffffff",
    shortcut: "#33ffffff",
    hover: "#12ffffff",
    shadowAlpha: 0.55
  }
}
function spotlightPalette(dark) { return dark ? spotlight.dark : spotlight.light }

// ---- Mitteilungszentrale (macOS 14/15). Eigener Abschnitt, nicht die
// Popup-Werte oben. Werte aus der Spec ~/Downloads/spec-mitteilungszentrale-macos.md
// (Näherungen, noch nicht am Screenshot nachgemessen — beim Nachmessen hier
// ersetzen). Referenz-Plugin: ~/.config/omarchy/plugins/henri.clock
// (NotificationCenter.qml). Punkt-Werte → Style.space(pt).
var notificationCenter = {
  width: 344,            // Spaltenbreite
  edgeInset: 12,         // Abstand zum Bildschirmrand und unter der Menüleiste
  gap: 12,               // Abstand zwischen Karten und zwischen kleinen Widgets
  cardPadding: 12,
  icon: 32,              // App-Symbol
  iconGap: 10,           // Symbol → Text
  iconRadius: 0.22,      // Symbolmaske, Anteil der Kantenlänge
  thumb: 40,             // Vorschaubild rechts
  thumbRadius: 6,
  cardMinHeight: 64,
  radiusCard: 16,        // Mitteilungskarte (Tahoe: 20)
  radiusWidget: 20,
  closeButton: 18,       // X-Kreis links oben
  minusButton: 20,       // Bearbeitungsmodus
  capsuleHeight: 24,     // „Weniger anzeigen“, „Alle löschen“
  editButtonHeight: 28,  // „Widgets bearbeiten“
  widgetSmall: 164,      // klein 164 × 164, mittel 344 × 164, groß 344 × 344
  stripOffset: 8,        // Stapel: Ebene 2/3 um 8/16 pt nach unten
  stripScale2: 0.94, stripScale3: 0.88,
  stripAlpha2: 0.8, stripAlpha3: 0.6,
  swipeActions: 140,     // Breite von Optionen + Löschen hinter der Karte
  swipeDelete: 0.6,      // ab 60 % Kartenbreite sofort löschen
  titleFont: 13,         // semibold
  bodyFont: 13,
  metaFont: 11,          // Zeitstempel, Gruppenzähler
  lineHeight: 16,
  bodyLines: 4,          // zugeklappt
  blur: 30,
  saturate: 1.8,
  light: {
    dark: false,
    tint: "#b8f6f6f6",          // rgba(246,246,246,0.72)
    borderInner: "#73ffffff",   // Weiß α 0.45, 0.5 pt
    borderOuter: "#14000000",   // Schwarz α 0.08
    shadow: "#1f000000",        // 0 4 16 α 0.12
    textPrimary: "#d9000000",   // 0.85
    textSecondary: "#8c000000", // 0.55
    capsule: "#14000000",
    capsuleHover: "#29000000",
    opaque: "#ffececec",        // „Transparenz reduzieren“
    face: "#b3ffffff"           // Zifferblatt der Uhr
  },
  dark: {
    dark: true,
    tint: "#b3282828",          // rgba(40,40,40,0.70)
    borderInner: "#1fffffff",   // Weiß α 0.12
    borderOuter: "#80000000",   // Schwarz α 0.50
    shadow: "#59000000",        // 0 4 16 α 0.35
    textPrimary: "#e6ffffff",   // 0.90
    textSecondary: "#8cffffff", // 0.55
    capsule: "#1fffffff",
    capsuleHover: "#33ffffff",
    opaque: "#ff2a2a2a",
    face: "#1fffffff"
  }
}
function ncPalette(dark) { return dark ? notificationCenter.dark : notificationCenter.light }

// ---- Banner: die Mitteilung oben rechts (macOS 26 Tahoe). Gemessen am
// 2026-09-27 an Apples Support-Screenshot (mac-help mh40609: Erinnerungs-
// Banner im Hover-Zustand mit Schließen-Kreis und „Options“-Kapsel; Skala
// 2,17 px/pt über fünf SF-Pro-Textbreiten, Menüleisten-Uhr inklusive).
// Referenz-Plugin: henri.notifications (Klon des Omarchy-Daemons).
var banner = {
  width: 312,            // Karte (gemessen 311)
  edgeInset: 14,         // zum rechten Bildschirmrand (gemessen 13,8)
  gap: 8,                // zwischen gestapelten Bannern (nicht gemessen)
  padding: 12,           // rundum; Text beginnt bei 53 pt (12 + 32 + 10)
  icon: 32,              // App-Symbol, vertikal zentriert
  iconGap: 10,
  badge: 14,             // App-Symbol unten rechts, wenn ein Bild das Symbol ersetzt
  minHeight: 64,         // gemessen 67 mit Overline + Titel + Text
  radius: 20,            // Kantenprofil ≈ 40-px-Kreis → 18–20 pt
  closeButton: 22,       // Schließen-Kreis (gemessen 21,7)
  closeCenterX: 5,       // Kreismitte ab Kartenecke
  closeCenterY: 7,
  capsuleHeight: 22,     // „Options ⌄“ 72 × 22, unten rechts
  capsulePadX: 12,
  capsuleRight: 10,
  capsuleBottom: 6,
  capsuleReserve: 80,    // Textbreite, die die Kapsel abzieht, wenn Aktionen da sind
  overlineFont: 11,      // „TIME SENSITIVE“: semibold, Versalien, sekundär
  titleFont: 13,         // semibold
  bodyFont: 13,
  lineHeight: 16,
  bodyLines: 4,
  light: {
    dark: false,
    tint: "#6bffffff",          // Weiß α 0.42 (gemessen 0.38/0.44/0.45 je Kanal)
    borderInner: "#73ffffff",   // Weiß α 0.45
    borderOuter: "#14000000",   // Schwarz α 0.08
    shadow: "#1f000000",
    textPrimary: "#d9000000",
    textSecondary: "#8c000000",
    capsule: "#0f000000",       // Schwarz α 0.06 (gemessen ≈ 0.05)
    capsuleHover: "#1a000000",
    opaque: "#ffececec"         // „Transparenz reduzieren“
  },
  dark: {
    dark: true,
    tint: "#59292929",          // wie das dunkle Control-Center-Glas (Grau 0.16 α 0.35)
    borderInner: "#1fffffff",
    borderOuter: "#80000000",
    shadow: "#59000000",
    textPrimary: "#e6ffffff",
    textSecondary: "#8cffffff",
    capsule: "#40ffffff",       // Weiß α 0.25 (Control Center, gemessen)
    capsuleHover: "#59ffffff",
    opaque: "#ff2a2a2a"
  }
}
function bannerPalette(dark) { return dark ? banner.dark : banner.light }

// ---- Dock (macOS Sonoma/Sequoia). Eigener Abschnitt, nicht die Popup-Werte
// oben. Werte aus der Spec ~/Downloads/dock-spec.md (Richtwerte, noch nicht
// am Screenshot nachgemessen — beim Nachmessen hier ersetzen). Bewegung:
// henri-ui Motion.dock. Referenz-Plugin: ~/.config/omarchy/plugins/henri.dock.
// Punkt-Werte → Style.space(pt); Größen, die der Nutzer per Trenner zieht
// (tileSize/magnifiedSize), bleiben Pixel und skalieren nicht mit der Shell.
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
  badge: "#ffff3b30", badgeText: "#ffffffff",
  menuRadius: 8, menuPad: 5, menuMinWidth: 180, menuRow: 22, menuFont: 13,
  menuHighlightRadius: 4, menuSeparatorPad: 5,
  accent: "#ff0a84ff",   // Menü-Hover, Fokusring
  focusRing: 3,
  fanIcon: 48, fanMax: 12, fanAngle: 15, fanPill: 32, fanGap: 6,
  gridIcon: 64, gridCell: 96, gridColumns: 5, gridFont: 11, gridRadius: 12, gridPad: 12,
  listIcon: 16, listRow: 22,
  stackPeek: 3,          // „Stapel“-Kachel zeigt die obersten 3 Dateien
  thumbBadge: 0.35,      // App-Icon auf einer Fenster-Miniatur × Kachel
  triggerZone: 3,        // Auto-Hide: Trigger-Zone an der Bildschirmkante
  settingsWidth: 300,
  light: {
    dark: false,
    sheet: "#47ffffff",        // Weiß α 0.28 (+ Compositor-Blur 24, Sättigung 180 %)
    border: "#73ffffff",       // Weiß α 0.45, 0.5 pt
    hairline: "#1f000000",     // äußere Haarlinie Schwarz α 0.12
    shadow: "#2e000000",       // 0 10 30 α 0.18
    separator: "#2e000000",    // Schwarz α 0.18
    indicator: "#bf000000",    // Schwarz α 0.75
    label: "#d9f0f0f0",        // rgba(240,240,240,0.85)
    labelText: "#ff1d1d1f",
    menu: "#d9f0f0f0",
    menuText: "#ff1d1d1f",
    menuHairline: "#1f000000",
    pill: "#b3ffffff",         // Fächer-Namen: Weiß α 0.70
    pillText: "#ff1d1d1f",
    opaque: "#ffececec"        // „Transparenz reduzieren“
  },
  dark: {
    dark: true,
    sheet: "#591e1e1e",        // rgba(30,30,30,0.35)
    border: "#2effffff",       // Weiß α 0.18
    hairline: "#80000000",     // Schwarz α 0.5
    shadow: "#59000000",       // 0 10 30 α 0.35
    separator: "#38ffffff",    // Weiß α 0.22
    indicator: "#ccffffff",    // Weiß α 0.8
    label: "#d9282828",        // rgba(40,40,40,0.85)
    labelText: "#fff5f5f7",
    menu: "#d9282828",
    menuText: "#fff5f5f7",
    menuHairline: "#2effffff",
    pill: "#99000000",         // Schwarz α 0.60
    pillText: "#fff5f5f7",
    opaque: "#ff2a2a2a"
  }
}
function dockPalette(dark) { return dark ? dock.dark : dock.light }

