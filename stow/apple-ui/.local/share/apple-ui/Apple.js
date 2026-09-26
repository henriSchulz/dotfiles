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
// die Popup-Werte oben. Quelle: Henris Design-Spec (spotlight-design-spec.md,
// aus Retina-Screenshots abgeleitete Näherungen, 1 pt = 1 px), nicht gescrapt —
// wer pixelgenau will, misst am eigenen Mac nach (references/apple.md).
// Referenz-Plugin: ~/.config/omarchy/plugins/henri.menu. Punkt-Werte werden
// mit Style.space(pt) auf die Shell-Skala gebracht. Die Auswahlfarbe folgt der
// Akzentfarbe des Systems (Omarchy: Color.accent); `selection` ist der Fallback.
var spotlight = {
  width: 620,            // Suchfeld und Ergebnispanel (600–640)
  topFraction: 0.23,     // Oberkante des Suchfelds bei 23 % der Bildschirmhöhe
  fieldHeight: 52,
  fieldRadius: 999,      // Kapsel
  fieldInset: 18,        // links bis zur Lupe, rechts bis zum Text
  fieldIcon: 20,         // SF `magnifyingglass`
  fieldGap: 10,          // Lupe → Text
  fieldFont: 22,         // Light
  fieldLine: 1.2,
  caret: 2,
  chipHeight: 22,        // Kategorie-Token links im Feld
  chipFont: 12,
  chipPadX: 8,
  button: 44,            // runde Kategorie-Buttons rechts neben dem Feld
  buttonIcon: 18,
  buttonGap: 8,
  buttonOffset: 10,      // Abstand Feld → erster Button
  buttonSlide: 8,        // Einblenden: von links hineingleiten
  resultsGap: 8,         // Feld → Ergebnispanel
  resultsRadius: 24,     // 22–26
  resultsPadding: 8,
  resultsMaxHeight: 480,
  rowHeight: 36,
  rowIcon: 24,
  rowGap: 8,             // Icon → Text
  rowInset: 10,
  rowRadius: 10,         // 10–12
  rowFont: 13,
  metaFont: 11,          // Pfad/Art rechts, Tastaturkürzel
  metaAlpha: 0.7,        // Kürzel-Hinweis: Zeilentextfarbe bei 70 %
  topHeight: 48,         // Top-Treffer 44–52
  topIcon: 32,
  topGap: 10,
  topFont: 15,           // Medium
  calcFont: 28,          // Rechenergebnis
  sectionFont: 11,       // Semibold, normale Schreibung
  sectionInset: 10,
  sectionTop: 8,
  sectionTopFirst: 4,
  sectionBottom: 2,
  shadowOffset: 22,      // 0 22px 70px 4px
  shadowBlur: 70,
  shadowSpread: 4,
  contactOffset: 4,      // 0 4px 12px
  contactBlur: 12,
  contactAlpha: 0.12,
  pressedDarken: 1.1,    // Auswahlfarbe gedrückt: ~10 % dunkler
  light: {
    dark: false,
    fill: "#b8f6f6f6",          // rgba(246,246,246,0.72)
    opaqueFill: "#ffececec",    // „Transparenz reduzieren“
    border: "#1a000000",        // 0.10
    highlight: "#99ffffff",     // obere Lichtkante 0.60
    textPrimary: "#d9000000",   // 0.85
    textSecondary: "#80000000", // 0.50
    textTertiary: "#4d000000",  // 0.30 (Platzhalter, Vervollständigung)
    separator: "#1a000000",
    selection: "#ff0064e1",
    selectionText: "#ffffffff",
    hover: "#0d000000",         // 0.05
    inactiveSelection: "#40808080",
    shadowAlpha: 0.35
  },
  dark: {
    dark: true,
    fill: "#b328282a",          // rgba(40,40,42,0.70)
    opaqueFill: "#ff2a2a2c",
    border: "#24ffffff",        // 0.14
    highlight: "#38ffffff",     // 0.22
    textPrimary: "#e6ffffff",   // 0.90
    textSecondary: "#8cffffff", // 0.55
    textTertiary: "#4dffffff",  // 0.30
    separator: "#1affffff",
    selection: "#ff0a84ff",
    selectionText: "#ffffffff",
    hover: "#12ffffff",         // 0.07
    inactiveSelection: "#40808080",
    shadowAlpha: 0.55
  }
}
function spotlightPalette(dark) { return dark ? spotlight.dark : spotlight.light }
