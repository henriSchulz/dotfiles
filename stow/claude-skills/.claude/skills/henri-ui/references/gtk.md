# GTK4 / libadwaita (gtk-rs, PyGObject)

Installiert: GTK 4.22, libadwaita 1.9. GTK-CSS kann `transition`, `cubic-bezier()`,
`transform`/`transform-origin` und CSS-Variablen (`var()`). libadwaita hat echte
Springs (`Adw.SpringAnimation`).

## 1. CSS-Tokens (einmal pro App laden, `gtk::CssProvider`, Priorität APPLICATION)

```css
:root {
  --dur-instant: 90ms;
  --dur-fast: 160ms;
  --dur-base: 240ms;
  --dur-slow: 380ms;
  --ease-out: cubic-bezier(0.22, 1, 0.36, 1);
  --ease-in-out: cubic-bezier(0.45, 0, 0.15, 1);
  --ease-exit: cubic-bezier(0.4, 0, 0.7, 0.2);

  --radius-panel: 14px;
  --radius-popover: 10px;
  --radius-control: 8px;
  --radius-row: 6px;
}

button, row, .card, menuitem, modelbutton {
  transition: background-color var(--dur-fast) var(--ease-out),
              color var(--dur-fast) var(--ease-out),
              box-shadow var(--dur-fast) var(--ease-out),
              opacity var(--dur-base) var(--ease-out),
              transform var(--dur-fast) var(--ease-out);
}
button:hover, row:hover, modelbutton:hover { transition-duration: var(--dur-instant); }
button:active { transform: scale(0.97); transition-duration: var(--dur-instant); }

button   { border-radius: var(--radius-control); }
popover > contents { border-radius: var(--radius-popover); }
popover modelbutton, popover row { border-radius: var(--radius-row); }
```

Falls eine GTK-Version `var()` in `transition` ablehnt (Warnung im Terminal), die
Werte direkt einsetzen — Tokens bleiben dieselben Zahlen.

## 2. Farben aus dem Omarchy-Theme

Beim Start `~/.local/state/omarchy/current/theme/colors.toml` lesen (Keys: `accent`,
`background`, `foreground`, `muted`, `selection`, `mode = "light"|"dark"`), daraus CSS
erzeugen und die libadwaita-Variablen überschreiben:

```css
:root {
  --accent-bg-color: <accent>;
  --accent-color: <accent>;
  --window-bg-color: <background>;
  --window-fg-color: <foreground>;
  --view-bg-color: <background>;
  --popover-bg-color: <background>;
  --headerbar-bg-color: <background>;
  --dim-opacity: 0.55;
}
```

`Adw.StyleManager::color-scheme` nach `mode` setzen. Datei mit `gio::FileMonitor`
beobachten → bei Theme-Wechsel Provider neu laden (live, ohne Neustart).

## 3. Springs & Animationen im Code (libadwaita)

Spring-Presets (aus SKILL.md, `stiffness = (2π/response)²`, Masse 1):

| Preset | `SpringParams::new(damping_ratio, mass, stiffness)` |
|--------|------------------------------------------------------|
| smooth | `(1.0, 1.0, 322.0)` |
| snappy | `(0.85, 1.0, 247.0)` |
| gentle | `(1.0, 1.0, 158.0)` |
| bouncy | `(0.75, 1.0, 195.0)` |

```rust
let weak = widget.downgrade();
let target = adw::CallbackAnimationTarget::new(move |v| {
    if let Some(w) = weak.upgrade() { w.set_opacity(v); }
});
let anim = adw::SpringAnimation::builder()
    .widget(&widget)
    .value_from(widget.opacity())          // immer vom aktuellen Wert!
    .value_to(1.0)
    .spring_params(&adw::SpringParams::new(1.0, 1.0, 322.0))
    .target(&target)
    .build();
anim.set_initial_velocity(prev_velocity);  // beim Umlenken Geschwindigkeit übernehmen
anim.play();
```

Zeitbasierte Animationen (`Adw.TimedAnimation`) — Easing-Mapping:

| Token      | `adw::Easing` |
|------------|---------------|
| easeOut    | `EaseOutQuint` |
| easeInOut  | `EaseInOutCubic` |
| easeExit   | `EaseInCubic` |

Verboten: `EaseOutBack`, `EaseOutElastic`, `EaseOutBounce` und alle `*Back/*Elastic/*Bounce`.

## 4. Übergänge zwischen Ansichten

- `gtk::Stack`: `StackTransitionType::Crossfade` (Standard) oder `SlideLeftRight` für
  Drill-in, `transition_duration(380)`.
- `gtk::Revealer`: `SlideDown` + `Crossfade` kombinieren (zwei Revealer oder
  Revealer + Opacity), `transition_duration(240)`.
- Drill-in-Navigation: `adw::NavigationView` (hat bereits macOS-/iOS-artige Springs +
  Swipe-Back) statt eigenem Stack.
- Dialoge: `adw::Dialog` (animiert selbst), keine eigenen `gtk::Window`-Popups.
- Listen mit vielen Einträgen: `GtkGridView`/`GtkListView`; Einträge beim Erscheinen
  per CSS `opacity`-Transition einblenden, nicht per Code pro Item.

## 5. Kinetik

`gtk::ScrolledWindow` hat Kinetic Scrolling + Overshoot eingebaut — nicht
deaktivieren. `set_kinetic_scrolling(true)`.
