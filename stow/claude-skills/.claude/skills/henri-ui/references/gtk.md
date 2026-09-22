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

## 6. Fremde GTK4-Apps umstylen (Files/Nautilus)

Apps, deren Code wir nicht haben, bekommen den Stil über `~/.config/gtk-4.0/gtk.css`
(stow-Paket `gtk`). Diese Datei **importiert nur**:

1. `~/.local/share/henri-ui/gtk-tokens.css` — nur `:root`-Tokens, keine Regeln
   (`--dur-*`, `--ease-*`, `--radius-*`, `--press-scale`, `--hover-alpha` …).
   `gtk.css` (für eigene Apps) importiert dieselbe Datei.
2. `~/.local/state/henri-ui/gtk-colors.css` — von `henri-ui-gtk-colors` aus dem
   aktiven Omarchy-Theme erzeugt (`--hui-bg`, `--hui-view`, `--hui-fg`, `--hui-accent`,
   `--hui-on-accent`, `--hui-menu-selected-*` …); der Hook
   `~/.config/omarchy/hooks/theme-set.d/henri-ui-gtk-colors` erzeugt sie bei jedem
   Theme-Wechsel neu (laufende Apps übernehmen sie beim nächsten Start).
3. Pro App eine Datei (`henri-files.css`), deren Regeln **alle** auf die App gescoped
   sind (`window.nautilus-window …`) — die globale Datei ändert nie andere Apps.
   Darin libadwaita-Variablen (`--accent-bg-color`, `--sidebar-bg-color`, …) auf
   `--hui-*` legen und nur Tokens verwenden.

Files ist nach dem macOS-Finder gebaut: weißer Inhalt + Toolbar (52 px, Haarlinie),
graue Sidebar mit Akzent-Icons und grauer Auswahl, Pfadleiste als Fenstertitel,
Liste mit Zebra-Streifen und Akzent-Auswahl, Grid mit grauer Kachel + Akzent-Chip
am Namen, NSMenu-Menüs (Highlight springt sofort). Icon-Größen per gsettings
(Grid 64 px, Liste 16 px, `install/26-files-app.sh`).

Verhalten (nicht nur Aussehen) kommt aus der nautilus-python-Erweiterung
`~/.local/share/nautilus-python/extensions/henri_files.py` (stow-Paket `nautilus`).
Sie läuft im Nautilus-Prozess und greift auf dessen GTK-Widgets zu:
- **Enter = Umbenennen** (Finder), Öffnen = Doppelklick/Strg+O/Alt+↓.
- **Inline-Umbenennen:** Nautilus' Rename-Popover wird auf ein nacktes Feld exakt
  über dem Namen reduziert (`.henri-inline-rename`). Einhängen bei
  `notify::pointing-to` — *vor* dem Aufklappen; die `show`-Emission-Hook läuft erst
  nach der Platzierung. Das Popup ändert Größe/Lage nie mehr, sobald es offen ist
  (GTK zentriert auf den Anker, Hyprland verschiebt offene Popups nicht) → festes
  unsichtbares Popover, nur das Feld darin wächst. Klick daneben übernimmt (selbst per
  GIO, weil Nautilus' Accept asynchron sein kann).
- **Menü-Symbole** vor jedem Eintrag (macOS 26): beim Öffnen jedes `GtkPopoverMenu`
  ein 16-px-Symbol vor das Label (`MENU_ICONS`, englische Labels).
- **Kontextmenü:** Copy Path, Open in Terminal, Open in Claude Code, New File ▸
  (Text, Markdown, ODF-Dokument/Tabelle/Präsentation, Skripte, HTML, JSON, CSV);
  neue Dateien werden markiert und gehen direkt ins Umbenennen.

**GTK3-Apps** (Quick Look = GNOME Sushi) können keine CSS-Variablen: Vorlagen in
`~/.local/share/henri-ui/gtk3/*.in` mit `{{token}}`-Platzhaltern, gerendert von
`henri-ui-gtk-colors` (Tokens aus `gtk-tokens.css` + Theme-Farben) — z. B. zum
GTK3-Theme `HenriQuickLook`, das nur Sushi bekommt (`GTK_THEME` in
`~/.local/share/dbus-1/services/org.gnome.NautilusPreviewer.service`).

Testen, ohne Henri zu stören: auf einem versteckten Spezial-Workspace öffnen und
das Fenster direkt abgreifen:

```bash
hyprctl eval "hl.exec_cmd('nautilus --new-window ~/Projects/dotfiles', { workspace = 'special:huitest silent', float = true, size = '1100 720' })"
id=$(hyprctl clients -j | jq -r '.[] | select(.class|test("autilus")) | .stableId')
grim -T "$id" shot.png     # versteckte Fenster rendern träge: ggf. 2–5 s warten
nautilus -q
```
Unfokussiert = `:backdrop`, dort wirkt alles etwas blasser.

**Nie das Fenster fokussieren oder `wtype` schicken, während Henri arbeitet** — seine
Tasten landen dann in Nautilus (2026-09-22: „xxxxxxx" in der Suche) und meine in
seinen Fenstern. Interaktion stattdessen im Prozess auslösen: eine temporäre
Test-Erweiterung (`zz_probe.py`, nach dem Start sofort wieder löschen) holt sich
`sys.modules["henri_files"]` und ruft Funktionen/`activate_action("view.rename")`
direkt auf; `nautilus --select <datei>` liefert eine Auswahl ohne Tastatur.
