# QML / Quickshell / Omarchy-Shell-Plugins

Plugins liegen in `~/.config/omarchy/plugins/henri.*` (gesynct nach `~/Projects/dotfiles`).
Qt 6.11, Quickshell 0.3.

## Setup — zentral importieren, NIE kopieren

```qml
import QtQuick
import qs.Commons            // Color.*, Style.*, Util.* aus dem Omarchy-Theme
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi
```

- Nackte absolute Pfade lehnt QML ab → immer `file:///…`.
- Beim Shell-Start meldet `quickshell.qmlscanner` „Ignoring unresolvable import …
  file:///…“ — harmlos (nur der Vorab-Scanner), die Imports funktionieren.
- Die Komponenten importieren selbst `qs.Commons`/`qs.Ui` → sie bekommen automatisch
  die Theme-Farben des laufenden Omarchy-Shells.
- **Änderungen an henri-ui brauchen einen Shell-Neustart** (Plugin-Hot-Reload liest nur
  Plugin-Dateien neu, zentrale Komponenten bleiben gecacht). Das erledigt
  `henri-ui-sync.path` automatisch (2 s nach der letzten Änderung). Änderungen an
  Plugin-Dateien lädt die Shell dagegen sofort selbst neu.
- `Reveal` (und damit PopupPanel/PopupCard) startet die Öffnen-Animation erst, wenn das
  Fenster seinen ersten Frame gezeigt hat (live gemessen: Control Center 77–107 ms nach
  `open`) — sonst wäre die Animation beim Erscheinen schon halb vorbei. Fallback nach
  `Motion.firstFrameTimeout`.

**Galerie** (alle Komponenten live zum Anfassen/Tunen):
`quickshell -p ~/.local/share/henri-ui/gallery/shell.qml`

**Selbsttest** (headless, mit Screenshots) — nach jeder Komponenten-Änderung:
`QT_QPA_PLATFORM=offscreen HUI_AUTOTEST=1 HUI_SHOT=/tmp/hui quickshell -p ~/.local/share/henri-ui/gallery/shell.qml`
→ keine `WARN scene`/`TypeError`-Zeilen, endet mit `HUI done`; Screenshots
`/tmp/hui-*.png` ansehen.
**Compile-Check** (vor jedem Live-Deploy — die Shell lädt Plugins bei jedem
Datei-Schreiben sofort neu, ein Fehler wäre direkt in der Bar):
`~/.local/share/henri-ui/gallery/compilecheck.sh <plugin-dir-oder-dateien>` → nur
`COMPILE RESULT 0 failed` ist ok. Braucht die laufende Wayland-Session (erzeugt keine Fenster).

Eingabe-Test (echte Tasten-/Maus-Events: Esc, Pfeile, Drill-in-Zurück, Klick ins Leere):
`QT_QPA_PLATFORM=offscreen quickshell -p ~/.local/share/henri-ui/gallery/keytest.qml`
→ muss mit `RESULT ALL PASS` enden.

## Komponenten (erst diese benutzen, dann selbst bauen)

| Komponente | Wofür | Wichtigste API |
|------------|-------|----------------|
| `HUi.PopupPanel` | **Bar-Popup** (Drop-in für Shell-`KeyboardPanel`, gleiche API) | `kind: popover\|panel` + alles von KeyboardPanel (`anchorItem`, `owner`, `bar`, `open`, `focusTarget`, `contentWidth/Height`, `fittedContent*()`); Esc/Klick daneben/Bar-Wechsel eingebaut |
| `HUi.Reveal` | Ein-/Ausblenden jeder Fläche + Esc | `open`, `kind: menu\|popover\|panel\|toast`, `origin`, `fromX/fromY`, `settled`, `shown`, `closed()`, **`dismissRequested()`** (Esc + Klick ins Leere), `closeOnEscape`, `closeOnOutsideClick`, `insideWindows` |
| `HUi.Surface` | Material (Theme-Hintergrund, Haarlinie, Radius) | `role: popups\|menu\|tooltip\|notifications`, `kind: panel\|popover\|menu\|chip`, `padding`, `contentLeftInset`… (BorderSurface) |
| `HUi.Pressable` | Basis alles Klickbaren | `clicked()`, `secondaryClicked()`, `tint`, `prominent`, `selected`, `showFill`, `pressScaleEnabled`, `contentColor`, `radius` |
| `HUi.Button` | Standard-Button | `text`, `icon` (Glyph), `prominent`, + alles von Pressable |
| `HUi.MenuList` | Komplettes macOS-Menü (Highlight sofort, kein Gleiten) | `model: [{text, icon, shortcut, enabled, danger, separator}]`, `activated(index, entry)`, `currentIndex`, `move()`, `activate()` |
| `HUi.Highlight` | Auswahl-Form für eine Gruppe | `target: <Item>`, `glide` (true = gleitet: Tabs/Segmente/Sidebar; false = springt: Menüs/Hover-Listen) — selber Koordinatenraum wie die Targets |
| `HUi.Toggle` | Schalter | `checked`, `toggled(bool)` |
| `HUi.CrossfadeText` | Text/Zahl, die sich ändert | `text`, `color`, `fontSize`, `fontWeight`, `fontFamily` |
| `HUi.Collapse` | Aufklappen / Höhe gleitet mit Inhalt | `expanded` (true lassen = Höhe folgt jeder Inhaltsänderung), `snap()` (ohne Animation auf den Zustand springen — z. B. Abschnitt zurücksetzen, während das Popup unsichtbar ist) |
| `HUi.PageStack` | Drill-in-Seiten mit Parallax | StackView: `initialItem`, `push()`, `pop()`, Höhe gleitet, Esc/← = zurück |
| `HUi.StaggerIn` | Gestaffeltes Erscheinen | `active`, `index` |
| `HUi.SpringValue` | Eigene Spring-Animation | `to`, `value`, `preset`, `epsilon`, `snap(v)` |
| `HUi.BatteryGlyph` | macOS-Menüleisten-Batterie (SF `battery`-Nachbau, Vektor) | `level` 0…1, `charging` (Blitz), `plugged` (Stecker), `ink`, `height` (12 ≈ Bar) — Füllung ≤ 20 % rot |

Stolperfalle: Kinder von `Pressable`/`Reveal`/`Collapse`/`StaggerIn` landen in einem
inneren Container — `parent.xyz` zeigt dorthin. Die Komponente per `id` ansprechen
(`color: row.contentColor`, nicht `parent.contentColor`).

Fehlt ein Baustein und wird er in ≥ 2 Plugins gebraucht → als neue `HUi.*`-Datei in
`~/.local/share/henri-ui/` anlegen, in die Galerie + Selbsttest aufnehmen, hier in der
Tabelle ergänzen.

## Bestehende Plugins migrieren (Rezept)

1. In einer Kopie arbeiten (Scratchpad), nie direkt in `~/.config/omarchy/plugins`.
2. Imports ergänzen (Motion + HUi, siehe oben).
3. `KeyboardPanel {` → `HUi.PopupPanel {` + `kind: "popover"` (Kalender, Menüs) bzw.
   `"panel"` (Control Center, große Flächen). Sonst nichts an der Popup-Logik ändern.
4. Alle festen Dauern/Kurven → Tokens. `OutBack`/`OutElastic`/Bounce-Sequenzen
   entfernen: Press-/Pop-Effekte → `HUi.SpringValue { preset: Motion.snappy }`,
   Rest → `Motion.easeOut`. Stagger-Delays → `Motion.stagger(index)`.
5. Sekundärtext per `Qt.darker/lighter(fg, x)` → `Util.alpha(fg, Motion.secondaryTextAlpha)`;
   deaktiviert/außerhalb → `Util.alpha(fg, Motion.disabledOpacity)`. (`Qt.darker` macht in
   hellen Themes dunklen Text noch dunkler.)
6. Hover-/Zustandsfarben ohne Übergang → `Behavior on color` (rein `instant`, raus
   `fast`); `"transparent"` als Ziel → `Util.alpha(farbe, 0)`.
7. Komponenten-Radien `Style.cornerRadius` → `Style.space(Motion.radius…)`.
8. Wechselnde Texte/Zahlen → `HUi.CrossfadeText`, wo es passt.
9. Funktion, Layout und Verhalten sonst **unverändert** lassen — Migration ist kein Redesign.
10. `compilecheck.sh` auf die Kopie → erst bei 0 Fehlern live kopieren (rsync), Shell-Log
    prüfen (`quickshell log -p /usr/share/omarchy/shell/shell.qml -t 50`), live öffnen
    (`omarchy-shell <ipc-target> open`) + `grim`-Screenshot ansehen, dann nach
    `~/Projects/dotfiles/omarchy/plugins/` syncen, committen, pushen.

## Abläufe als Code

### Popup aus der Bar (Menü)

```qml
HUi.Reveal {
  id: menu
  kind: "menu"
  origin: Item.Top                         // Bar unten → Item.Bottom + fromY: 4
  open: root.opened
  onDismissRequested: root.close()          // Esc + Klick ins Leere — PFLICHT bei jeder Reveal
  insideWindows: [barWindow]                // Fenster mit dem Auslöser zählt nicht als „außen“
  width: surface.implicitWidth; height: surface.implicitHeight

  HUi.Surface {
    id: surface
    anchors.fill: parent
    role: "menu"; kind: "menu"
    padding: Style.space(5)
    implicitWidth: list.implicitWidth + padding * 2
    implicitHeight: list.implicitHeight + padding * 2
    HUi.MenuList {
      id: list
      x: surface.contentLeftInset; y: surface.contentTopInset
      width: parent.width - surface.contentLeftInset - surface.contentRightInset
      focus: menu.open
      model: root.entries
      onActivated: function(index, entry) { root.close(); root.run(entry) }
    }
  }
}
```

**Esc & Klick ins Leere:** Reveal holt sich beim Öffnen den Tastaturfokus und meldet Esc
sowie Klicks außerhalb als `dismissRequested()` — im selben Fenster über eine
unsichtbare Klick-Fläche (Klick wird verschluckt, Klicks auf die Fläche selbst gehen
durch), in andere Fenster/den Desktop über `HyprlandFocusGrab` (steckt in Reveal —
nicht zusätzlich selbst anlegen). Das Fenster mit dem Auslöser (z. B. die Bar) in
`insideWindows` eintragen, sonst schließt der Klick auf den Auslöser über den Grab und
öffnet es direkt wieder. Es setzt `open` nie selbst (würde das Binding `open: root.opened`
brechen und den Panel-Zustand desynchronisieren) → immer
`onDismissRequested: root.close()` bzw. `open = false` bei imperativer Steuerung.
Damit Tasten überhaupt ankommen, braucht das Fenster Tastaturfokus:
`PanelWindow` → `WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand` (bzw.
`Exclusive` für Launcher).

Im `PopupWindow`/`PanelWindow`: Fenster `visible: menu.shown`, damit es erst nach dem
Ausblenden verschwindet. Keine zusätzliche Opacity-Animation auf der Karte (die
`PopupCard` der Shell faded selbst mit 140 ms — für neue Plugins HUi.Reveal + eigenes
`PopupWindow` bevorzugen).

### Panel mit Kacheln (Control Center)

```qml
HUi.Reveal {
  id: panel; kind: "panel"; open: root.opened; origin: Item.TopRight
  HUi.Surface {
    kind: "panel"
    HUi.PageStack {
      id: pages
      initialItem: Grid {
        Repeater {
          model: tiles
          HUi.StaggerIn { active: panel.open; index: model.index; Tile { … } }
        }
      }
    }
  }
}
```

Teure Arbeit (Scans, Polling, große Modelle) erst bei `panel.settled` starten.

### Wert ändert sich

`HUi.CrossfadeText { text: volume + " %" }`, Schalter `HUi.Toggle`. Icons: zwei Glyphs
übereinander mit Opacity-Behavior (oder CrossfadeText mit der Icon-Schrift).

### Auswahl in eigenen Listen / Tabs

```qml
Item {
  HUi.Highlight { target: col.children[currentIndex] || null; glide: false }  // Tabs: true
  Column { id: col; … }        // bei 0,0 im selben Parent wie der Highlight
}
```

`ListView`: `HUi.Highlight` in `contentItem` legen, `target: list.currentItem`.

## Low-Level (nur wenn keine Komponente passt)

```qml
Behavior on color {
  ColorAnimation {
    duration: hovered ? Motion.instant : Motion.fast
    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
  }
}
HUi.SpringValue { id: s; to: target; preset: Motion.snappy }   // Default: Motion.smooth
```

- Hover-Fills als `Util.alpha(tint, 0)` statt `"transparent"` (sonst blendet es über Schwarz).
- `from:` nur in `add`-Transitions; in Zustandswechseln erzwingt es Sprünge.
- Keine `XAnimator`/`OpacityAnimator` für Zustände: sie schreiben den Endwert nicht
  zuverlässig zurück (im Test blieb eine Seite unsichtbar). `NumberAnimation` nehmen.

Listen-Transitions:

```qml
add: Transition {
  NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.base
    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
  NumberAnimation { property: "scale"; from: Motion.menuFromScale; to: 1; duration: Motion.base
    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
}
displaced: Transition {
  NumberAnimation { properties: "x,y"; duration: Motion.base
    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
}
```

`Flickable`/`ListView`: `boundsBehavior: Flickable.DragAndOvershootBounds`,
`flickDeceleration: Motion.flickDeceleration`, `maximumFlickVelocity: Motion.maximumFlickVelocity`.

## Theme & Stil

- Farben: `Color.foreground/background/accent/urgent`, Flächen `Color.popups.*`,
  `Color.menu.*`. Sekundärtext `Util.alpha(Color.foreground, Motion.secondaryTextAlpha)`
  (nicht `Color.muted`), Text auf Akzent `Motion.onColor(Color.accent)`. Schrift: `Style.font.*`, Abstände `Style.spacing.*` / `Style.space(px)`.
- Alle px-Tokens aus `Motion.js` durch `Style.space()` schicken (skaliert mit der Schrift).
- Blur hinter Layer-Surfaces: Hyprland `layerrule = blur, <namespace>` + `ignorealpha`.

## Reduce Motion / Tempo

`Motion.reduceMotion = true` → alle Komponenten nur noch Crossfades.
`Motion.speed = 1.2` → alles 20 % langsamer. Beides zentral, wirkt nach Shell-Reload überall.

## Verboten in Plugins

`Easing.OutBack`, `Easing.OutElastic`, `Easing.OutBounce`, Freihand-`duration`-Zahlen,
eigene `response`-Werte, `visible:` ohne Fade, lokale Kopien der henri-ui-Dateien,
eigene Nachbauten von Button/Menü/Toggle/Highlight, wenn die HUi-Komponente reicht.
