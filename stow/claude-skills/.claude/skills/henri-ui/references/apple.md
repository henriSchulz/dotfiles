# Apple-Look: apple-ui, Rohdaten, Messmethode

Wann: **nur** wenn Henri für eine Fläche ausdrücklich „wie echtes macOS“ will (bisher:
`henri.control-center-v2`). Dann gilt bewusst *nicht* „Farben aus dem Theme“, sondern
die gemessenen Apple-Werte. Bewegung bleibt immer henri-ui (`Motion.js`/`motion.css`).
Alles andere (Größen ≥ 20 px, Kontrast, Tastatur, Reduce Motion, Choreografie §3b) gilt
weiter.

## Geltungsbereich — Menüleisten-Popups, nicht Apps

Alles, was bisher in `apple-ui` steckt (Tokens, Geometrie, Glas-Alphas, Komponenten), ist
am **Control Center** gemessen und gilt für **Menüleisten-Popups**: Control Center,
Batterie-Menü, Wi-Fi/Bluetooth-Menüs, Popover unter einem Bar-Icon. Dort 1:1 verwenden.

**Eine App (Fenster) ist etwas anderes.** Fenster, Sidebars, Toolbars, Listen, Formulare,
Sheets und Dialoge haben unter macOS einen anderen Aufbau, andere Maße, andere
Materialien (z. B. `windowBackground`, Sidebar-Vibrancy, Toolbar-Höhe, 13-pt-Body auf
opakem Grund statt Glas). Für eine App also **nicht** die Control-Center-Kacheln,
-Radien oder -Alphas übernehmen, sondern:

1. Die passende macOS-Fläche als Referenz holen (Screenshot + AX-Tree auf dem Mac,
   Scraper in `~/Projects/MacOSUICapture`) — ohne Referenz nicht raten.
2. Nach der Messmethode unten die Werte dieser Fläche bestimmen (Geometrie aus dem
   AX-Tree, Farben/Alphas/Radien per Pixelmessung, Schriftgrößen über Cap-Höhe).
3. Die gescrapten NSColor-/Typografie-Tokens aus `macos-tokens.json` bleiben die
   Farb- und Schriftbasis (`Apple.js` → `label`, `secondaryLabel`, `separator`,
   `systemFill`, `accent`, `body` …) — die sind flächenunabhängig.
4. Die neuen Werte als **eigenen Abschnitt** in `Apple.js`/`apple.css`/`apple-gtk.css`
   ablegen (z. B. `window`, `sidebar`, `toolbar`), nicht die Popup-Werte überschreiben,
   und neue Komponenten daneben anlegen (z. B. `AUi.SidebarRow`, `AUi.Toolbar`).
5. Bewegung weiterhin henri-ui; Fenster-Choreografie (Sheets, Drill-in, Sidebar) aus
   SKILL.md §3/§3b.

Kurz: apple-ui wächst pro Fläche mit — jede Fläche bekommt ihre eigenen gemessenen
Werte, die Popup-Werte sind nur der erste Abschnitt.

## Bibliothek

`~/.local/share/apple-ui/` (dotfiles `stow/apple-ui`) — Gegenstück zu henri-ui:

| Datei | Für |
|---|---|
| `Apple.js` | QML-Tokens: NSColor-Werte, Typo-Punktgrößen, Control-Center-Geometrie, Radien, beide Glas-Paletten, `material(item)`-Lookup |
| `*.qml` | Komponenten (Katalog in `README.md`): Tile, IconTile, Badge, Slider, Capsule, Switch, Button, PageHeader, ListRow, SwitchRow, Stat, Meter, UsageHeader, IconButton, TextField, Link, Title/Subtitle/Caption/Glyph, SectionLabel, Separator, Backdrop, Material |
| `apple.css` | Web/Tauri/Electron: `--apple-*`, `.apple-dark`, fertige `.apple-*`-Klassen |
| `apple-gtk.css` | GTK4: `@define-color apple_*` + `--apple-*` |

Referenz-Plugin: `~/.config/omarchy/plugins/henri.control-center-v2/` (BarWidget + Panel).

Regeln wie bei henri-ui: zentral importieren, nie kopieren; fehlt ein Wert → in
`Apple.js` **und** beiden CSS-Dateien ergänzen, hier dokumentieren.

**Material:** `AUi.Material { dark }` als `appleMaterial` am obersten Inhalts-Item im
Popup (Komponenten laufen `parent` hoch; die Kette endet am Fenster, nicht am
QML-Root). `AUi.Backdrop` misst das Wallpaper unter dem Panel (`magick`, einmal beim
Start + inotify auf `~/.local/state/omarchy/current`) — dunkles Glas unter Luma 0.75
(Henris Wahl, sein Wallpaper misst 0.68). Sheet-Alpha ≥ 0.35, sonst greift Hyprlands
Blur (`ignore_alpha 0.3`) nicht. `HUi.PopupPanel` bekommt `cardColor: mat.sheet` und
`borderSpec: Border.flat(mat.hairline, 1)`. Punkt-Werte → `Style.space(pt)`.

Schriften: SF Pro + SF Symbols lokal (`~/.local/share/fonts/sf/`), **nie committen**;
Codepoint-Tabelle im Memory `sf-symbols-font`.

## Rohdaten (alle lokal, nicht in Git)

| Pfad | Inhalt |
|---|---|
| `~/macos-scrape/dist/macos-tokens.json` | Distillat: `colors` (NSColor, light), `typography` (pointSize/lineHeight/capHeight), `metrics`, `controlSizes`, `motion` |
| `~/macos-scrape/dist/macos-tokens.css`, `MacOSReference.qml`, `MacOSPreview.qml` | dieselben Werte als CSS / QML |
| `~/macos-scrape/<Run>/` (z. B. `20260925T204357Z`) | Roh-Run des Scrapers |
| `~/macos-scrape/controlCenter-fixed/` | **Referenz-Screenshot** des echten Control Centers: `screen.png` (2880×1800, 2x), `ax.json` (Accessibility-Tree mit Frames in pt), Crops `cc-crop.png`, `cc-corner-zoom.png`, `cc-slider-zoom.png` |
| `~/Projects/MacOSUICapture/` | Der Scraper (Swift, auf dem MacBook per SSH, siehe Memory `macbook-ssh-access`): `run_all.sh`, `distill_tokens.py`, `macos-style-scraper-spezifikation.md` |

Neue Fläche nachbauen (Spotlight, Notification Center, Popover …): erst auf dem Mac
Screenshot + AX-Tree ziehen (Scraper bzw. `screencapture` + Accessibility-Dump), dann
unten messen, dann in `Apple.js` ergänzen — nicht schätzen.

## Messmethode (so ist das Control Center entstanden)

1. **Geometrie aus `ax.json`** — Frames sind Punkte (×2 = Pixel im Screenshot).
   Kachelgrößen, Abstände, Slider-Position, Button-Maße direkt übernehmen.
2. **Farben/Alphas per Pixelmessung** mit ImageMagick, nie nach Augenmaß:
   ```bash
   # Mittelwert einer Region (x y w h in Pixeln)
   magick screen.png -crop 40x100+2508+150 +repage -scale 1x1! \
     -format '%[fx:int(255*r)],%[fx:int(255*g)],%[fx:int(255*b)]' info:
   # Alpha eines weißen Overlays: a = (innen − außen) / (255 − außen), pro Kanal
   ```
   Kachel über Sheet: Weiß α 0,15 · Haarlinie: Weiß α ≈ 0,5 auf 0,5 pt → 0,28 auf 1 px ·
   Slider-Track: Schwarz α 0,20 · Kreis „aus“: Weiß α 0,25 · Kapsel: Weiß α 0,25.
3. **Radius**: Profil der Kante zeilenweise (erste helle Spalte pro Zeile), Kreis
   anpassen — 64-pt-Kachel ≈ 22 pt (gerade Kante ~21 pt). `metrics` des Scrapers hat
   **keine** Radien.
4. **Schriftgröße über die Cap-Höhe**: weiße Zeilen eines Großbuchstabens zählen, /2,
   mit `typography.*.capHeight` vergleichen (9 pt → 13 pt headline). Zeilenabstand
   aus dem Screenshot ist unzuverlässig.
5. **Ergebnis prüfen**: Plugin per IPC öffnen, `grim`, Crop mit `magick -gravity
   NorthEast -crop`, gegen `cc-crop.png` legen — Struktur *und* Farbe.
   Ohne Fokus-Klau: `omarchy-shell <plugin> page <name>` / `setBackdropLuma 0.2`.

## Bekannte Lücken des Scrapers (Stand 2026-09-26)

- Light/Dark identisch (Appearance-Umschaltung greift nicht) → die dunkle Palette
  ist am Screenshot gemessen, nicht gescrapt.
- `toolbarHeight.*` immer 0; keine Radien in `metrics`.
- 7/9 benannte Akzentfarben lassen sich unter macOS 26 nicht per `defaults write`
  setzen; `controlAccentColor` liefert Graphit — Apple-Blau ist `controlAccentBlueColor`.
- Glas-Material (Vibrancy) ist nicht messbar per NSColor; nur per Screenshot.
- Es gibt nur das Control Center als Referenz-Screenshot; andere Flächen erst scrapen.
