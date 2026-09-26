# apple-ui

Gegenstück zu `henri-ui` für Oberflächen, die **1:1 wie echtes macOS (Tahoe)**
aussehen sollen: Farben, Typografie, Geometrie, Radien und Glas-Material sind
gemessen bzw. gescrapt (Quellen in `Apple.js`), nicht aus dem Omarchy-Theme.
Bewegung (Dauern, Kurven, Springs) kommt weiterhin aus `henri-ui/Motion.js`.

**Geltungsbereich:** Der heutige Stand ist am Control Center gemessen und gilt für
**Menüleisten-Popups** (Control Center, Batterie-Menü, Popover unter einem Bar-Icon).
Eine **App** (Fenster, Sidebar, Toolbar, Listen, Sheets) ist anders aufgebaut — dafür
nicht diese Kacheln/Radien/Alphas übernehmen, sondern die passende macOS-Fläche
scrapen und nachmessen und die Werte als eigenen Abschnitt hier ergänzen. Die
NSColor-/Typografie-Tokens aus dem Scrape gelten überall. Details:
`~/.claude/skills/henri-ui/references/apple.md`.

```qml
import "file:///home/henri/.local/share/apple-ui/Apple.js" as Apple
import "file:///home/henri/.local/share/apple-ui" as AUi
```

## Material

```qml
AUi.Backdrop { id: backdrop }               // Wallpaper-Helligkeit unter dem Panel
AUi.Material { id: mat; dark: backdrop.dark } // dunkles (gemessen) / helles (Scrape) Glas
Item { property var appleMaterial: mat; … }   // oberstes Inhalts-Item im Popup
```

Jede Komponente findet ihre Palette über `Apple.material(this)`: der erste
Vorfahre mit `appleMaterial`. Innerhalb eines Popup-Fensters muss das am
obersten Inhalts-Item hängen (die Item-Kette endet am Fenster). Ohne Fund gilt
die helle Palette. `appleRevealed` (bool) am selben Item steuert die
Eintritts-Kaskade der Kacheln (`revealIndex`).

Sheet-Alpha muss über Hyprlands `ignore_alpha 0.3` bleiben (layer_rule auf
`omarchy-keyboard-panel`), sonst fällt der Blur weg. `HUi.PopupPanel`
bekommt `cardColor: mat.sheet` und `borderSpec: Border.flat(mat.hairline, 1)`.

## Komponenten

| Komponente | Wofür | API |
|---|---|---|
| `Tile` | Glas-Kachel (Radius 22) | `interactive`, `hasCursor`, `revealIndex`, `clicked()`, `rightClicked()` |
| `IconTile` | runde 64-pt-Icon-Kachel | `glyph`, `on`, `name` (Accessible) |
| `Badge` | 36-pt-Icon-Badge in Kacheln | `on`, `glyph`, `glyphFont`, `glyphSize`, `squircle`, `clickable`, `clicked()` |
| `Slider` | Tahoe-Slider (4-pt-Track, weißer Fill, kein Knopf) | `value`, `minimum/maximum`, `step`, `stops`, `enabled`, `moved()`, `released()` |
| `Title` / `Subtitle` / `Caption` | 13 bold / 12 sekundär / 11 gedämpft | Text-Props |
| `Glyph` | SF-Symbol | `text`, `size` |
| `SectionLabel` | Versal-Überschrift | Text-Props |
| `DisclosureLabel` | Versal-Überschrift mit Aufklapp-Chevron (Kopf zu `HUi.Collapse`) | `text`, `expanded`, `leftPadding`, `clicked()` |
| `Separator` | Haarlinie | — |
| `Capsule` | Kapsel-Button 24 pt | `label`, `symbol`, `selected`, `outlined`, `clicked()` |
| `Button` | NSButton rounded | `text`, `icon`, `prominent`, `clicked()` |
| `Switch` | NSSwitch 38 × 22 | `checked`, `toggled(on)` |
| `PageHeader` | Zurück-Chevron + Titel (+ Switch) | `title`, `showSwitch`, `checked`, `toggled(on)`, `back()` |
| `ListRow` | Listenzeile 44 pt | `icon`, `iconFont`, `active`, `title`, `subtitle`, `trailing`, `busy`, `enterDelay`, `clicked()` |
| `SwitchRow` | Zeile mit Schalter | `title`, `caption`, `checked`, `toggled(on)` |
| `Stat` / `UsageHeader` / `Meter` | Stat-Raster, Titel+Wert, Auslastungsbalken | `label`/`value`, `title`/`value`/`valueColor`, `fraction`/`fillColor` |
| `IconButton` | runder 30-pt-Aktionsbutton | `icon`, `name`, `clicked()` |
| `TextField` | Eingabefeld | `text`, `placeholder`, `password`, `submitIcon`, `error`, `submitted()`, `cancelled()`, `edited()` |
| `Link` | Textlink | `text`, `clicked()` |
| `Backdrop` | Wallpaper-Messung + inotify | `luma`, `threshold`, `dark`, `set(v)`, `remeasure()` |
| `Material` | Palette-Objekt | `dark` → alle Farben |

## Andere Toolkits

`apple.css` (Web/Tauri/Electron: alle Tokens als `--apple-*`, `.apple-dark` für das
dunkle Glas, fertige `.apple-sheet/.apple-tile/.apple-capsule/.apple-slider`) und
`apple-gtk.css` (GTK4: `@define-color apple_*` + `--apple-*`). Gleiche Werte wie
`Apple.js` — Änderungen in allen drei Dateien. Motion weiterhin aus henri-ui.

Messmethode, Rohdaten und Scraper-Lücken: `~/.claude/skills/henri-ui/references/apple.md`.

## Spotlight

`Apple.spotlight` in `Apple.js` bzw. `--apple-sp-*` in beiden CSS-Dateien: die
Tahoe-Spotlight-Suche, gemessen an Apples Support-Screenshots (Skala über
SF-Pro-Textbreiten): kompakte Kapsel 330 × 48 mit 46-pt-Buttons, aufgeklappt
eine Fläche 560 breit / Radius 20 mit Suchzeile 50, Haarlinie, Filter-Kapseln
21, zweizeiligen Zeilen 49 (Titel 15, Untertitel 13, Icon 25), Auswahl als
leichte Tönung mit Haarlinie, Kürzel-Chip 24 × 17, Glas-Paletten hell (gemessen)
und dunkel (abgeleitet); dazu die Aktionsseite (`actionHeader` 49, `actionRowHeight`
36, `sectionFont` 11 — Spec-Werte, nicht gemessen). `Apple.spotlightPalette(dark)` liefert die Palette.
Referenz-Plugin: `~/.config/omarchy/plugins/henri.menu`.

## Fenster (Apps)

`Apple.window` in `Apple.js` bzw. `--apple-win-*` in beiden CSS-Dateien: die am
echten Finder gemessenen Fensterwerte (Sidebar-Karte, Toolbar-Kapseln, Listen-,
Icon- und Spaltengeometrie, Farben). Referenz-App: `~/Projects/finder` (GTK4,
`data/finder.css`). Neue Fensterflächen (Sheets, Inspector, Toolbar-Varianten)
kommen als weitere Schlüssel dazu, jeweils gemessen.

Referenz-Implementierung (Popups): `~/.config/omarchy/plugins/henri.control-center-v2/`.
Punkt-Werte werden mit `Style.space(pt)` auf die Shell-Skala gebracht.
Schriften SF Pro / SF Symbols sind lokal installiert — nie committen.
