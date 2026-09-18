---
name: henri-ui
description: Henri's verbindlicher UI- und Motion-Stil (macOS-Feeling, extrem smooth) für ALLES, was eine Oberfläche hat — Omarchy-Shell-Plugins (Quickshell/QML), GTK4/libadwaita-Apps, Web/Tauri/Electron. Immer laden, bevor Buttons, Menüs, Popover, Panels, Listen, Dialoge, Toggles, Tooltips, Übergänge oder Animationen gebaut oder geändert werden, auch wenn der Nutzer den Stil nicht erwähnt. Triggers: UI, Oberfläche, Plugin, Widget, Menü, Button, Panel, Popup, Animation, Übergang, Transition, hover, smooth, style, design.
---

# Henri UI — macOS-Feeling, nichts abgehackt

Ziel: Jede App und jedes Plugin fühlt sich an wie **dasselbe Produkt**, 1:1 wie macOS:
weich, ruhig, physikalisch, jederzeit unterbrechbar. Der Nutzer will diese Regeln
**nicht jedes Mal neu erklären** — sie gelten als Default, ohne Rückfrage. Nur
abweichen, wenn er es im konkreten Fall ausdrücklich sagt.

Framework-spezifische Umsetzung (Snippets + wie man zentral einbindet):
- Omarchy-Shell-Plugins / Quickshell / QML → `references/qml.md`
- GTK4 / libadwaita (gtk-rs, PyGObject) → `references/gtk.md`
- Web / Tauri / Electron / HTML → `references/web.md`

Lies die passende Referenz, bevor du Code schreibst.

## 0. Eine zentrale Quelle — Änderungen ziehen überall mit

Henris Anforderung: Ändert er eine Richtlinie, müssen **alle** Plugins und Apps, die
danach gebaut wurden, automatisch mitziehen. Deshalb:

**Wo alles liegt** — `~/.local/share/henri-ui/` (Symlink auf
`~/Projects/dotfiles/stow/henri-ui/.local/share/henri-ui/`):

| Datei | Für | Einbinden |
|-------|-----|-----------|
| `Motion.js` | QML-Plugins: Dauern, Kurven, Spring-Presets, Radien, Skalen | `import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion` |
| `*.qml` (Reveal, Surface, Pressable, Button, MenuList, Highlight, Toggle, CrossfadeText, Collapse, PageStack, StaggerIn, SpringValue) | QML: fertige Komponenten — Katalog in `references/qml.md` | `import "file:///home/henri/.local/share/henri-ui" as HUi` |
| `gallery/shell.qml` | Alle Komponenten live + Selbsttest | `quickshell -p ~/.local/share/henri-ui/gallery/shell.qml` |
| `gtk.css` | GTK4/libadwaita-Apps | zur Laufzeit laden + FileMonitor |
| `motion.css` | Web/Tauri/Electron | zur Laufzeit laden bzw. im Build aus der Quelle ziehen |

**Regeln beim Bauen**
1. **Nie kopieren, immer zentral importieren.** Keine lokale Kopie von `Motion.js`,
   `SpringValue.qml` oder den CSS-Dateien im Projekt.
2. **Keine eigenen Zahlen im Plugin/in der App** für Dauer, Kurve, Spring, Radius,
   Press-/Enter-Skala. Fehlt ein Token, wird er **zentral** ergänzt (und in diesem
   Skill dokumentiert), dann verwendet.
3. **Wiederkehrende Komponenten zentral.** Braucht ein zweites Plugin denselben
   Baustein (Button, Menü-Container, gleitendes Highlight, Toggle, Popover-Hülle,
   Crossfade-Text …), wird er als `HUi.<Name>.qml` in `~/.local/share/henri-ui/`
   angelegt und beide Plugins nutzen ihn. So ziehen auch **Verhaltens**-Änderungen
   überall mit, nicht nur Zahlen.
4. Farben kommen ohnehin zentral aus dem Omarchy-Theme.

**Globale Schalter** (in `Motion.js`, CSS analog): `speed` (1.0 = normal, 1.2 = alles
20 % langsamer — Dauern *und* Springs) und `reduceMotion` (nur noch Crossfades).
„Alles etwas langsamer/schneller“ = nur `speed` ändern.

**Wenn Henri eine Richtlinie ändert** („Menüs langsamer“, „Buttons ohne Scale“ …):
1. Wert-Änderung → nur in der zentralen Datei ändern (QML **und** CSS-Dateien, damit
   alle Toolkits gleich bleiben) und die Tabellen hier in SKILL.md mitziehen.
2. Verhaltens-Änderung → die zentrale Komponente ändern + Regel hier anpassen.
3. Danach Altlasten suchen, die noch nicht zentral sind, und umstellen:
   ```bash
   grep -rnE 'duration: *[0-9]|Easing\.(Out|In|InOut)(Back|Elastic|Bounce|Quad|Cubic|Quint)|response: *[0-9]|radius: *[0-9]' \
     ~/.config/omarchy/plugins/henri.* --include=*.qml
   ```
   (GTK/Web-Projekte in `~/Projects` analog auf feste ms-/cubic-bezier-/px-Werte prüfen.)
4. Omarchy-Shell neu laden, prüfen, im dotfiles-Repo committen und pushen.

## 1. Die sieben Motion-Gesetze (nicht verhandelbar)

1. **Nichts springt.** Jede sichtbare Zustandsänderung (Farbe, Größe, Position,
   Sichtbarkeit, Inhalt) wird animiert. Kein `visible = false` ohne vorheriges Ausfaden.
   Aber (Apple HIG): **häufige** Interaktionen (Hover, Tippen, Listen-Navigation)
   bekommen nur kurze, leise Übergänge (`instant`/`fast`, Farbe/Opacity) — keine
   Bewegung, kein Scale außer dem Press-Feedback. Große Bewegung nur für seltene,
   räumliche Wechsel (Popup öffnen, Drill-in, Overview). Nie warten müssen: jede
   Animation ist sofort überschreibbar.
2. **Unterbrechbar.** Eine Animation startet immer vom *aktuellen* Wert, nie vom
   Anfang. Schnelles Hin-und-Her (Hover rein/raus, Menü auf/zu) darf nie ruckeln,
   springen oder sich in einer Queue stauen. → Transitions/Behaviors statt Keyframes.
3. **Nur `transform` und `opacity` animieren.** Keine Layout-Eigenschaften pro Frame
   (width/height/margin/padding/Blur-Radius). Größenänderungen: Container mit Clip +
   Spring, Inhalt per Crossfade. Ziel: stabile 60/120 fps, kein einziger verlorener Frame.
4. **Ausblenden ist schneller als Einblenden** (≈ 0.7×). Rein: großzügig, raus: diskret.
5. **Kein Cartoon.** Kein `OutElastic`, kein `OutBounce`, kein `OutBack` mit sichtbarem
   Überschwingen. Maximal ~1–3 % Overshoot, und nur bei Dingen, die „physisch“ bewegt
   werden (Toggle-Knopf, Drag-Ende, Workspace-Wechsel).
6. **Räumlich logisch.** Dinge kommen von dort, wo sie ausgelöst wurden
   (`transformOrigin` = Anker: Menü unter dem Bar-Button wächst von oben aus diesem Button).
   Drill-in-Seiten schieben nach links, zurück nach rechts.
7. **Reduce Motion respektieren.** Ist reduzierte Bewegung aktiv: nur Crossfades, keine
   Skalierung/Verschiebung.

## 2. Motion-Tokens (überall identisch — keine Freihand-Werte!)

Nie eigene Dauern/Kurven erfinden (`duration: 137`, `Easing.OutBack` …). Immer diese
Tokens — die gültigen Werte stehen in den zentralen Dateien (§0); diese Tabellen
erklären sie und müssen bei Änderungen mitgezogen werden.

### Dauern

| Token      | ms  | Verwendung |
|------------|-----|------------|
| `instant`  | 90  | Hover-*rein*, Press-Feedback |
| `fast`     | 160 | Hover-*raus*, Farbwechsel, Icon-Crossfade, Tooltip |
| `base`     | 240 | Menüs, Popover, Dropdowns, Toggles, kleine Größenwechsel |
| `slow`     | 380 | Panels, Sheets, Seitenwechsel, Control-Center-Drill-in |
| `slower`   | 520 | Vollbild: Overview, Mission Control, Launcher |
| Exit       | ×0.7| Ausblenden = 0.7 × Einblenden-Dauer |

### Kurven (cubic-bezier)

| Token        | Bezier                     | Verwendung |
|--------------|----------------------------|------------|
| `easeOut`    | `0.22, 1, 0.36, 1`         | **Standard.** Alles, was erscheint oder auf Eingabe reagiert |
| `easeInOut`  | `0.45, 0, 0.15, 1`         | Sichtbares bewegt sich von A nach B (Seitenwechsel, Reorder) |
| `easeExit`   | `0.4, 0, 0.7, 0.2`         | Verschwinden (fade/scale out) |
| `linear`     | —                          | nur Fortschrittsbalken / Spinner |

### Springs (SwiftUI-Parameter, bevorzugt für Position/Scale)

Ausgerechnet (Masse 1, `stiffness = (2π/response)²`). Presets in `Motion.js`
(`Motion.smooth` …), exakte CSS-Kurven in `motion.css`.

| Token    | response | dampingRatio | stiffness | Overshoot | Einschwingen | Verwendung |
|----------|----------|--------------|-----------|-----------|--------------|------------|
| `smooth` | 0.35 s   | 1.0          | 322       | 0 %       | ~510 ms (optisch fertig ~300) | **Default** für Bewegung, Popover-Scale, Tab-/Segment-Highlight |
| `snappy` | 0.40 s   | 0.85         | 247       | 0.6 %     | ~560 ms      | Toggles, Press-Release, Drag-Ende |
| `gentle` | 0.50 s   | 1.0          | 158       | 0 %       | ~730 ms      | Große Flächen: Panels, Overview, Sheets |
| `bouncy` | 0.45 s   | 0.75         | 195       | 2.8 %     | ~570 ms      | Selten! Nur Spielerisches (Dock-Icon, Erfolg) |

Springs behalten beim Unterbrechen die Geschwindigkeit bei → das ist das
„macOS-Gefühl“. Wo das Framework echte Springs hat (libadwaita, JS), Springs nehmen.

## 3. Komponenten-Rezepte (macOS-Verhalten)

In QML sind diese Rezepte als **fertige `HUi.*`-Komponenten** umgesetzt — benutzen,
nicht nachbauen (`references/qml.md`). In GTK/Web gelten sie als Spezifikation.

**Button**
- Hover: Fill blendet ein (`instant`, easeOut), raus (`fast`). Kein Größen-Hover.
- Press: `scale 0.97` + etwas dunklerer Fill, sofort (`instant`); Loslassen springt mit
  `snappy` zurück.
- Disabled: `opacity 0.4`, weich übergeblendet.
- Fokus (Tastatur): Accent-Ring 2–3 px, faded ein (`fast`).

**Menü / Dropdown / Kontextmenü**
- Öffnen: `opacity 0→1` + `scale 0.96→1` + `translateY -4px→0`, Ursprung am Anker,
  `base` + easeOut (oder `smooth`-Spring für Scale).
- Schließen: nur `opacity→0` + `scale→0.98`, `base×0.7`, easeExit.
- Nach Klick auf einen Eintrag: Eintrag blinkt einmal kurz (Highlight aus/an, je 70 ms),
  dann erst die Aktion + Menü ausfaden — wie NSMenu.
- Maus verlässt das Menü → Highlight blendet aus. Tastatur: ↑ ↓ Home End ⏎ Esc;
  Separatoren und deaktivierte Einträge werden übersprungen.
- Hover-/Tastatur-Highlight springt **sofort** auf den Eintrag, ohne Gleiten und ohne
  Fade — wie NSMenu. (Henri: gleitender Menü-Highlight ist „too much“.) Gleiten nur
  bei Tabs, Segment-Umschaltern und Sidebars (`HUi.Highlight { glide: true }`).
- Einträge: Höhe 26 px (bei 12 pt), Radius 6, Innenabstand 10 px, Accent-Fill mit
  Hintergrundfarbe als Text für den aktiven Eintrag; Kürzel rechtsbündig in `muted`;
  destruktive Einträge in `urgent`.

**Popover / Panel / Control Center**
- Rein: `opacity` + `scale 0.95→1` vom Anker, `gentle`-Spring bzw. `slow` easeOut.
- Raus: `opacity` + `scale 0.97`, `slow×0.7`, easeExit.
- Höhe ändert sich (andere Seite, Liste klappt auf): Container animiert Höhe mit
  `smooth`, `clip: true`; Inhalt crossfadet (`fast`).
- Drill-in-Seite: neue Seite kommt von rechts (`translateX 100%→0`), alte Seite geht
  30 % nach links + faded auf 0 (Parallax), `slow` easeInOut. Zurück = gespiegelt.

**Toggle / Switch**
- Knopf gleitet mit `snappy`; Track-Farbe crossfadet (`fast`). Beim Drücken wird der
  Knopf 10–15 % breiter (wie iOS/macOS).

**Liste / Grid**
- Neue Einträge: Höhe von 0 aufklappen (`smooth`) + Inhalt faden; Entfernen gespiegelt.
- Erstes Erscheinen: Stagger 15 ms pro Eintrag, maximal 10 Einträge gestaffelt, Rest gleichzeitig.
- Reorder: Einträge gleiten (`smooth`) an ihre neue Position, nie springen.
- Scrollen: kinetisch mit Rubber-Band-Overshoot am Rand (wo der Toolkit es kann).

**Tooltip**
- 500 ms Verzögerung, dann faden (`fast`). Danach Folge-Tooltips ohne Verzögerung,
  solange die Maus innerhalb ~1 s weiterwandert.

**Inhalt wechselt (Zahl, Text, Icon, Bild)**
- Crossfade (`fast`). Icons zusätzlich `scale 0.8→1`. Zahlen nie hart umspringen.

**Toast / Notification**
- Rein: von der Bildschirmkante gleiten + faden, `gentle`. Raus: zurück zur Kante,
  schneller. Nachrückende Einträge gleiten nach (`smooth`).

**Vollbild (Overview, Mission Control, Launcher)**
- Hintergrund dimmt/blurt per Opacity eines vorgerenderten Layers (Blur-Radius nie
  animieren). Fenster/Kacheln skalieren von ihrer echten Position aus, `gentle`.

## 3b. Abläufe (Choreografie — immer gleich, in jedem Plugin)

1. **Öffnen** (Bar-Button → Popup): Button gibt Press-Feedback → Fläche erscheint per
   Reveal vom Anker (Menü `smooth`/`base`, Panel `gentle`/`slow`) → Inhalt (Kacheln,
   Zeilen) gleichzeitig gestaffelt (15 ms, max. 10) → Tastaturfokus auf das erste
   sinnvolle Element. Teure Arbeit erst, wenn die Fläche „settled“ ist.
2. **Auswählen im Menü:** Highlight folgt Maus/Tastatur sofort (kein Gleiten) → Klick/⏎ → Blinken →
   Aktion auslösen + Menü schließt (Exit, 0.7×).
3. **Drill-in** (Detailseite): neue Seite von rechts, alte 30 % nach links + Fade,
   `slow` easeInOut, Höhe gleitet mit. Zurück: Button „‹“, Esc oder ← — gespiegelt.
4. **Schließen:** Esc, Klick daneben oder erneuter Klick auf den Auslöser → Exit ohne
   Stagger, alles gemeinsam, schneller als der Eintritt. Fokus zurück zum Auslöser.
5. **Wechsel zwischen Popups** (Maus gleitet in der Bar zum Nachbarn): altes schließt,
   neues öffnet **gleichzeitig** — nie auf das Ende der Exit-Animation warten.
6. **Wert ändert sich:** Text/Zahl crossfadet, Schalter gleitet, Fortschritt animiert
   linear; nie hartes Umspringen.
7. **Liste ändert sich:** Neue Zeilen klappen auf + faden, entfernte klappen zu,
   Nachbarn gleiten nach (`smooth`).
8. **Warten/Laden:** Unter 300 ms nichts anzeigen; danach dezenter Spinner/Fortschritt
   per Fade. Inhalt, der ankommt, crossfadet den Platzhalter.
9. **Fehler:** Feld rötet sich per Farb-Fade; bei falscher Eingabe (Passwort) ein
   kurzes horizontales Schütteln (3 Ausschläge, ±6 px, ~300 ms) — das einzige erlaubte
   „Wackeln“, wie bei macOS.

## 4. Visueller Stil (macOS-nah)

- **Farben immer aus dem Omarchy-Theme**, nie hart codiert
  (QML: `Color.*`/`Style.*` aus `qs.Commons`; sonst `~/.local/state/omarchy/current/theme/colors.toml`).
  So passen alle Apps zueinander und wechseln mit dem Theme.
- **Radien:** Fenster/Panels 14, Popover/Menüs 10, Buttons/Felder 8, Menü-Einträge 6,
  kleine Chips 5. Konzentrisch: innerer Radius = äußerer − Innenabstand.
- **Material:** Panels/Menüs leicht transparent (Hintergrund-Alpha ~0.85) + Blur hinter
  der Fläche (Hyprland-`layerrule blur` bzw. Compositor), dünne Haarlinie
  1 px `foreground` @ α 0.10, weicher Schatten (y 8, blur 24, α 0.18–0.25).
- **Zustände (Fill-Alpha auf foreground):** normal 0, hover 0.08, pressed 0.14,
  selected = Accent. (In Shell-Plugins: die `Style.*Fill`-Tokens verwenden.)
- **Typo:** Theme-Font, klare Hierarchie über Gewicht statt Größe (Titel 600,
  Text 400, sekundär = `muted`-Farbe).
- **Abstände:** 4-px-Raster (4/8/12/16/20/24). In Shell-Plugins `Style.spacing.*`.
- Icons: dünn, einfarbig (Symbolic), gleiche Strichstärke überall.
- **Größen (Apple HIG, Desktop):** Controls 28 px hoch (Klickfläche), nie unter 20 px;
  Fließtext = Theme-Body, nie unter 10 pt; dünne/leichte Schnitte nicht für kleinen Text.
- **Kontrast:** Text ≤ 17 pt mindestens 4.5 : 1, großer/fetter Text und Glyph-Icons
  3 : 1 — gegen die tatsächliche Theme-Hintergrundfarbe prüfen (auch `muted`-Text!).
- Nichts nur über Farbe vermitteln (Status = Farbe + Icon/Text). Jedes Icon-only-Control
  braucht einen Tooltip/Accessible-Namen. Alles per Tastatur bedienbar.

## 5. Performance-Regeln (smooth = keine Frame-Drops)

- Keine teure Arbeit beim Animationsstart (Dateien lesen, Prozesse starten, große
  Modelle bauen) — vorher laden oder nach Animationsende.
- Komplexe Ebenen während der Animation als Layer rendern (QML `layer.enabled`,
  CSS `will-change: transform, opacity` nur während der Animation).
- Popups vorab instanziieren und nur ein-/ausblenden, statt sie bei jedem Öffnen neu zu bauen.
- Blur/Schatten nicht animieren; stattdessen Opacity einer fertigen Ebene.

## 6. Review mit dem `apple-design`-Skill

Nach dem Bauen einer neuen Oberfläche (oder wenn Henri „review“ sagt) den Skill
`apple-design` als Prüfer nutzen: Accessibility, Plattform-Konventionen, Craft.
Rangfolge bei Widersprüchen: **henri-ui gewinnt** (Henris bewusste Entscheidungen,
z. B. Animations-Werte, Theme-Farben statt Apple-Systemfarben). Findet der Review einen
echten Mangel, der für alle gilt (z. B. zu kleine Klickflächen), wird er **zentral**
behoben (Token/Komponente), nicht nur im einen Plugin.

## 7. Checkliste vor dem Abschluss

- [ ] Zentral importiert (§0), keine lokale Kopie; keine eigenen Zahlen für Dauer/Kurve/Spring/Radius
- [ ] Vorhandene `HUi.*`-Komponenten benutzt; neuer wiederkehrender Baustein → zentral angelegt
- [ ] Komponenten geändert → Galerie-Selbsttest läuft ohne Warnungen, Screenshots angesehen
- [ ] Abläufe aus §3b eingehalten (Öffnen, Auswählen, Drill-in, Schließen, Wechsel)
- [ ] Größen/Kontrast laut §4 (Controls ≥ 20 px, Text ≥ 10 pt, 4.5 : 1)
- [ ] Kein Element erscheint/verschwindet ohne Übergang
- [ ] Schnelles Hover-Wackeln / Auf-Zu-Spam getestet: kein Springen, keine Queue
- [ ] Nur transform/opacity pro Frame animiert
- [ ] Exit schneller als Enter; Ursprung am Anker
- [ ] Farben aus dem Theme, Radien laut Tabelle
- [ ] Reduce-Motion-Pfad vorhanden
- [ ] Bestehenden Code, den du anfasst, auf die Tokens umstellen (z. B. `Easing.OutBack`,
      `Easing.OutElastic`, Freihand-Dauern ersetzen)
