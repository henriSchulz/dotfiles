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
