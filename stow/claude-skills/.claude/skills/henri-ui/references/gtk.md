# GTK4 / libadwaita (gtk-rs, PyGObject)

Installiert: GTK 4.22, libadwaita 1.9. GTK-CSS kann `transition`, `cubic-bezier()`,
`transform`/`transform-origin` und CSS-Variablen (`var()`). libadwaita hat echte
Springs (`Adw.SpringAnimation`).

## 1. CSS-Tokens — zentral laden, NIE kopieren

Die Tokens liegen in `~/.local/share/henri-ui/gtk.css` (einzige Quelle). Jede App lädt
genau diese Datei zur Laufzeit und beobachtet sie, damit Änderungen überall ankommen:

```rust
let path = glib::home_dir().join(".local/share/henri-ui/gtk.css");
let provider = gtk::CssProvider::new();
provider.load_from_path(&path);
gtk::style_context_add_provider_for_display(
    &gdk::Display::default().unwrap(), &provider,
    gtk::STYLE_PROVIDER_PRIORITY_APPLICATION);
// FileMonitor auf `path` → bei Änderung provider.load_from_path(&path)
```

App-eigenes CSS danach laden und dort nur `var(--dur-*)`, `var(--radius-*)` usw.
verwenden, keine eigenen Zahlen. Fehlt die Datei (fremder Rechner), läuft die App mit
libadwaita-Defaults weiter — kein Absturz.

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
