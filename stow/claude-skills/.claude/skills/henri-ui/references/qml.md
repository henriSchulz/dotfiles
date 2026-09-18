# QML / Quickshell / Omarchy-Shell-Plugins

Plugins liegen in `~/.config/omarchy/plugins/henri.*` (gesynct nach `~/Projects/dotfiles`).
Qt 6.11, Quickshell 0.3 — `FrameAnimation` ist verfügbar.

## Setup pro Plugin

Kopiere beide Dateien ins Plugin-Root (Plugins bleiben so eigenständig/veröffentlichbar):

```bash
cp ~/.claude/skills/henri-ui/assets/{Motion.js,SpringValue.qml} <plugin>/
```

```qml
import QtQuick
import qs.Commons            // Color.*, Style.* aus dem Omarchy-Theme
import "Motion.js" as Motion
// SpringValue.qml liegt im selben Ordner → direkt als Typ nutzbar
```

## Bausteine

### Farbe / Opacity (Behavior, unterbrechbar)

```qml
Behavior on color {
  ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
}
Behavior on opacity {
  NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
}
```

Hover rein schnell, raus langsamer:

```qml
color: hover.hovered ? Style.hoverFill : "transparent"
Behavior on color {
  ColorAnimation {
    duration: hover.hovered ? Motion.instant : Motion.fast
    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
  }
}
```

### Position / Scale → SpringValue (behält Geschwindigkeit beim Umlenken)

```qml
SpringValue { id: pressS; to: tap.pressed ? Motion.pressScale : 1; response: 0.40; dampingRatio: 0.85 }
scale: pressS.value
```

`Behavior on x { NumberAnimation {…} }` nur für einfache Fälle; für alles, was oft
umgelenkt wird (Highlight, Drag, Workspace-Wechsel, Popover-Scale), `SpringValue`.

### Button

```qml
Rectangle {
  id: btn
  radius: 8
  color: tap.pressed ? Style.pressedFill : hover.hovered ? Style.hoverFill : "transparent"
  scale: pressS.value
  Behavior on color {
    ColorAnimation { duration: hover.hovered ? Motion.instant : Motion.fast
      easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
  }
  SpringValue { id: pressS; to: tap.pressed ? Motion.pressScale : 1; response: 0.40; dampingRatio: 0.85 }
  HoverHandler { id: hover }
  TapHandler { id: tap; onTapped: btn.clicked() }
  signal clicked()
}
```

### Menü / Popover ein- und ausblenden (nie `visible` hart schalten)

```qml
Item {
  id: menu
  property bool open: false
  // erst nach dem Ausfaden unsichtbar machen → spart Rendering, kein Sprung
  visible: open || opacity > 0.001
  opacity: open ? 1 : 0
  transformOrigin: Item.Top            // Anker! (Bar oben → Item.Top / TopLeft / TopRight)
  scale: scaleS.value
  transform: Translate { y: offS.value }

  SpringValue { id: scaleS; to: menu.open ? 1 : Motion.exitToScale; response: 0.35 }
  SpringValue { id: offS; to: menu.open ? 0 : Motion.menuOffsetY; response: 0.35; epsilon: 0.1 }

  Behavior on opacity {
    NumberAnimation {
      duration: menu.open ? Motion.base : Motion.exit(Motion.base)
      easing.type: Easing.BezierSpline
      easing.bezierCurve: menu.open ? Motion.easeOut : Motion.easeExit
    }
  }
  // Nur aus komplett geschlossenem Zustand von kleiner Skala starten;
  // mitten im Schließen wieder öffnen = Spring dreht einfach um.
  onOpenChanged: if (open && opacity < 0.01) scaleS.snap(Motion.menuFromScale)
}
```

Popover/Panel: gleich, aber `Motion.popoverFromScale`, `response: 0.5` (gentle),
Opacity-Dauer `Motion.slow`.

### Gleitendes Auswahl-Highlight (Menüs, Listen, Tabs)

Ein einziges Rechteck hinter den Einträgen, das per Spring zur aktuellen Zeile gleitet:

```qml
Rectangle {
  id: highlight
  radius: 6
  color: Color.accent
  opacity: list.currentIndex >= 0 ? 1 : 0
  y: hlY.value
  height: hlH.value
  width: parent.width
  SpringValue { id: hlY; to: list.currentItem ? list.currentItem.y : 0; response: 0.35; epsilon: 0.3 }
  SpringValue { id: hlH; to: list.currentItem ? list.currentItem.height : 0; response: 0.35; epsilon: 0.3 }
  Behavior on opacity { NumberAnimation { duration: Motion.fast } }
}
```

Bei `ListView` alternativ `highlight:` + `highlightFollowsCurrentItem: false` und y
selbst an den Spring binden.

### Höhe eines Panels ändert sich

```qml
Item {
  clip: true
  height: hS.value
  SpringValue { id: hS; to: content.implicitHeight; response: 0.35; epsilon: 0.3 }
}
```

### Inhalt crossfaden (Zahl, Icon, Text)

Echter Crossfade = zwei Instanzen übereinander, die neue faded ein, die alte aus
(beide mit `Behavior on opacity`). Für einfachen Text reicht Aus-/Einfaden über den
aktuellen Opacity-Wert — `restart()` startet dabei vom aktuellen Wert, springt nicht:

```qml
Text {
  id: label
  property string value            // hier binden, nicht an text
  onValueChanged: swap.restart()
  SequentialAnimation {
    id: swap
    NumberAnimation { target: label; property: "opacity"; to: 0; duration: Motion.exit(Motion.fast)
      easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeExit }
    ScriptAction { script: label.text = label.value }
    NumberAnimation { target: label; property: "opacity"; to: 1; duration: Motion.fast
      easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
  }
  Component.onCompleted: text = value
}
```

### Listen

- `ListView` `add` / `remove` / `displaced` Transitions setzen:

```qml
add: Transition {
  NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.base
    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
  NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Motion.base
    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
}
displaced: Transition {
  NumberAnimation { properties: "x,y"; duration: Motion.base
    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
}
```

- Stagger beim ersten Erscheinen: `PauseAnimation { duration: Motion.stagger(index) }`.
- `Flickable`/`ListView`: `boundsBehavior: Flickable.DragAndOvershootBounds`,
  `flickDeceleration: 1500`, `maximumFlickVelocity: 4000`.

## Theme & Stil

- Farben: `Color.foreground/background/accent/muted/urgent`, Flächen `Color.popups.*`,
  `Color.menu.*`. Zustände: `Style.hoverFill`, `Style.pressedFill`, `Style.selectedFill`.
- Abstände: `Style.spacing.*` bzw. `Style.space(px)`; Schrift: `Style.font.*`.
- Radien laut SKILL.md; wo das Plugin zu Hyprland passen soll, `Style.cornerRadius`
  berücksichtigen (Hyprland-Rounding).
- Blur hinter Layer-Surfaces: Hyprland `layerrule = blur, <namespace>` +
  `ignorealpha`. Namespace der `PanelWindow` (`WlrLayershell.namespace`) setzen.

## Reduce Motion

Es gibt keinen System-Schalter; wenn ein Plugin eine Option `reduceMotion` hat,
dann: SpringValue `snap()` statt `to`, nur Opacity-Behaviors aktiv lassen.

## Verboten in Plugins

`Easing.OutBack`, `Easing.OutElastic`, `Easing.OutBounce`, `Easing.InQuad` auf
Erscheinen, Freihand-`duration`-Zahlen, `visible:` ohne Fade, `from:`-Werte in
Zustands-Animationen (erzwingen einen Sprung beim Unterbrechen — nur in
`add`-Transitions erlaubt).
