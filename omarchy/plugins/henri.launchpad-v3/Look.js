.pragma library
// Geometry of the Launchpad, after macOS 15 Launchpad by eye (not measured) —
// only the shape lives here; colours come from Velum's surface.launchpad tokens
// (Theme.core.surface.launchpad), type and radii from Velum's roles, motion from
// surface.launchpad. Spec: ~/Projects/launchpad/replica/design/components.md.
var grid = {
  columns: 7, rows: 5,     // defaults; settings may change them (4–12 × 3–8)
  iconSize: 88,            // default, settings 64–128
  iconBody: 0.86,          // visible icon body × iconSize (icons carry their own padding)
  marginX: 0.10,           // free space left and right × screen width
  marginTop: 0.14,         // grid starts below the search field × screen height
  marginBottom: 0.13,      // room for the page dots × screen height
  labelGap: 8,             // icon to title
  labelLines: 1,           // titles elide, never wrap (macOS)
  labelMaxFactor: 1.5,     // title width × iconSize
  pressedScale: 0.94,
  edgeZone: 48             // px at the screen edge that turns the page while dragging
}

var search = {
  width: 240, widthFocused: 320,
  height: 30,
  top: 44,                 // from the top edge of the screen
  glyph: 14,
  padX: 10
}

var dots = {
  size: 7, gap: 10,
  hit: 24,                 // click target per dot
  bottom: 52               // from the bottom edge of the screen
}

var folder = {
  tileRadius: 0.23,        // × iconSize, plate behind the mini icons
  tileInset: 0.12,         // × iconSize
  previewGrid: 3,          // 3 × 3 mini icons on the tile
  emojiSize: 0.5,          // emoji height × visible icon body
  previewGap: 0.04,        // × iconSize
  panelWidth: 0.62,        // × screen width
  panelMaxWidth: 1100,
  panelPad: 32,
  panelGap: 18,            // title to grid
  titleSize: 26            // = type.largeTitle; the title field sits above the panel
}

var badge = {
  size: 22, glyph: 11,
  offset: -0.08            // × iconSize, sits on the icon's top-left corner
}

var results = {
  width: 560,              // search results column
  row: 44, icon: 28,
  maxRows: 9,
  fileRows: 4,             // files under the apps
  fileMinChars: 2,
  fileDebounce: 180        // ms after the last key before fd runs
}

var settings = {
  sliderWidth: 160,
  hiddenMaxRows: 6
}

var toast = {
  bottom: 96,
  hold: 3200               // ms on screen
}

var info = {
  icon: 48,                // app icon in the Get Info head
  field: 200,              // name / icon field width
  emojiField: 72,
  swatch: 20,              // folder colour dots
  swatchRing: 2
}

var folderPage = {
  dotsGap: 14              // folder page dots below the panel's grid
}
