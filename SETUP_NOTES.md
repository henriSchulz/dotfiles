# Dotfiles Setup — Bestandsaufnahme & Plan

Ausgangspunkt: [`omarchy_setup_guide.md`](omarchy_setup_guide.md) (Methode nach Typecraft).
Diese Datei hält fest, wie das System **tatsächlich** aussieht (Stand 2026-09-13) und wo
die Methode aus dem Guide angepasst werden muss.

---

## 1. Ist-Zustand: drei Ebenen

```
/usr/share/omarchy/          # Paket, read-only, wird bei jedem Update überschrieben
  default/hypr/*.lua           Omarchy-Defaults für Hyprland
  config/, themes/, shell/     Default-Templates, Stock-Themes

~/.config/hypr/              # eigene Ebene (40 KB)
  hyprland.lua                 bootstrap + require("default.hypr.omarchy"), danach eigene Module
  monitors.lua  input.lua  bindings.lua  looknfeel.lua  autostart.lua
  hyprsunset.conf  xdph.conf   (eigene Prozesse, nicht über hyprctl validierbar)
  input.lua.bak.1788982424     <- Altlast

~/.config/omarchy/           # eigene Ebene (237 MB)
  shell.json                   Bar / Widgets / Idle   (+ 4 .bak-Dateien)
  plugins/                     8 Plugins, 57 MB — 6 davon Git-Clones von Upstream
  themes/                      5 Themes, 181 MB — überwiegend Wallpaper + ein 70-MB-.git-Pack
  hooks/                       *.d-Verzeichnisse; 3 aktive .hook, 6 inaktive .sample
  extensions/omarchy-menu.jsonc
  branding/  themed/  defaults/agent  keystroke.json
  henri.menu.bak.1789239423    <- Altlast (88 KB)
```

### Werkzeuge
| Tool | Status |
|---|---|
| `yay`, `git`, `hyprpm`, `hyprctl`, `omarchy` | vorhanden |
| `stow` | **nicht installiert** |
| Dotfiles-Repo | **existiert noch nicht** (die Repos in `~/Work` und `~/Projects` sind fremde Projekte) |

### Plugins (`~/.config/omarchy/plugins/`)
| Plugin | Größe | Herkunft |
|---|---|---|
| `evindor.keystroke` | 28 MB | github.com/evindor/keystroke |
| `henri.keystroke` | 22 MB | Git-Clone **ohne Remote** — offene Frage |
| `io.github.andyweiboan.missioncontrol` | 2,5 MB | github.com/AndyWeiBoan/omarchy-mission-control |
| `io.github.maajix.spotlight` | 1,6 MB | github.com/maajix/omarchy-spotlight |
| `bibek.menu` | 1,3 MB | github.com/BibekBhusal0/omarchy-better-menu |
| `paudelsamir.minimize-pill` | 636 KB | github.com/paudelsamir/minimize-pill |
| `io.github.grootaiinfinity.hwmon` | 504 KB | github.com/GrootAiInfinity/omarchy-hwmon |
| `henri.menu` | 108 KB | **kein `.git`** — offene Frage |

### Themes (`~/.config/omarchy/themes/`)
`mac-transparent` 117 MB · `cupertino` 33 MB · `img-7075` 32 MB · `cupertino-dark` 732 KB · `aether` leer

---

## 2. Abweichungen vom Guide

> **§4 (`omarchy_overrides.conf` + `grep` auf die `source`-Zeile) ist auf diesem System obsolet.**
> Das ist der alte `.conf`-basierte Omarchy. Hier läuft die Lua-Variante: `hyprland.lua` lädt
> erst die Omarchy-Defaults und danach die eigenen Module. Das Override-Layering ist bereits
> eingebaut — kein Anhängen einer `source`-Zeile nötig, es wird direkt `bindings.lua`,
> `looknfeel.lua` usw. editiert.

> **§3 (GNU Stow):** `stow` muss erst installiert werden; ein Dotfiles-Repo existiert noch nicht.

> **§6 greift hier wörtlich.** `~/.config/omarchy/` wird *im Betrieb* beschrieben:
> `omarchy theme set` schreibt hinein, `shell.json` lädt beim Speichern neu (daher die vier
> `.bak`-Dateien), und Plugin- sowie Theme-Verzeichnisse sind selbst Git-Clones — 181 MB
> Wallpaper und ein 70-MB-Pack. Dieses Verzeichnis wird **per Skript reproduziert, nicht
> per Symlink verwaltet.**

**Aufteilungsregel: per Stow verlinken, was nur ich schreibe — per Skript erzeugen, was Omarchy schreibt.**

---

## 3. Geplante Repo-Struktur

```
~/Projects/dotfiles/
├── install_all.sh              Master, idempotent
├── install/
│   ├── 10-packages.sh          yay --noconfirm --needed
│   ├── 20-stow.sh              symlink-sichere Configs stowen
│   ├── 30-omarchy-plugins.sh   omarchy plugin install <url>  (pro Plugin, überspringt Vorhandenes)
│   ├── 40-omarchy-themes.sh    Themes klonen/verlinken, omarchy theme set
│   ├── 50-hooks.sh             omarchy hook install …
│   └── 60-hyprpm.sh            hyprpm add/enable + hyprpm update
├── stow/                       <- wird per Symlink verlinkt
│   ├── hypr/.config/hypr/*.lua
│   ├── nvim/.config/nvim/
│   ├── ghostty/ alacritty/ kitty/ foot/
│   └── starship/ btop/ lazygit/ tmux/ git/
└── omarchy/                    <- wird kopiert/erzeugt, NICHT verlinkt
    ├── shell.json
    ├── extensions/omarchy-menu.jsonc
    ├── hooks/                  die 3 echten .hook-Dateien
    └── plugins/henri.menu/     eigener Plugin-Quellcode
```

---

## 4. Offene Fragen (vor dem Bauen zu klären)

1. **Welche Configs kommen ins Repo?** Kandidaten in `~/.config`: `nvim`, vier Terminals
   (`ghostty`, `alacritty`, `kitty`, `foot`), `starship`, `btop`, `lazygit`, `tmux`, `git`.
   Alle oder eine Auswahl?
2. **`henri.keystroke` (22 MB) und `henri.menu`** — eigener Code? `henri.keystroke` ist ein
   Git-Clone ohne Remote, `henri.menu` hat gar kein `.git`. Sollen Remotes eingerichtet werden?
3. **Altlasten aufräumen?** 6 verwaiste `.bak`-Dateien:
   ```
   ~/.config/hypr/input.lua.bak.1788982424
   ~/.config/omarchy/henri.menu.bak.1789239423
   ~/.config/omarchy/shell.json.bak.1789239423
   ~/.config/omarchy/shell.json.bak.1789242328
   ~/.config/omarchy/shell.json.bak.predisable.1789243909
   ~/.config/omarchy/shell.json.bak.beforerevert.1789244080
   ```

## 5. Nächste Schritte

- [ ] `git init` in diesem Verzeichnis
- [ ] Offene Fragen oben klären
- [ ] `stow` installieren (`yay -S --noconfirm --needed stow`)
- [ ] Skelett aus Abschnitt 3 anlegen

---

# Nachtrag (2026-09-13): Befunde nach dem Diff gegen die Paket-Defaults

Jede Datei in `~/.config` wurde gegen `/usr/share/omarchy/config/` bzw. die
Paketquellen diffed. Das beantwortet die offenen Fragen aus §4 und korrigiert
drei Annahmen aus §2/§3.

## Korrekturen

1. **§3, `30-omarchy-plugins.sh`:** Der Befehl heißt `omarchy plugin add <git-url>`
   (`--enable`, `--yes`), **nicht** `omarchy plugin install`.
2. **§1/§3, `50-hooks.sh` entfällt.** Die drei „aktiven" `.hook`-Dateien sind
   byte-identisch mit `/usr/share/omarchy/install/user/first-run/`. Es sind
   Installer-Artefakte, keine eigene Konfiguration — es gibt nichts zu
   installieren.
3. **§3, `60-hyprpm.sh` entfällt.** `hyprpm list` scheitert mit
   „state store doesn't exist" — hyprpm wurde auf diesem System nie
   initialisiert, es sind keine Plugins vorhanden.
4. **§1, Themes:** Nur `mac-transparent` ist ein Git-Clone mit Remote.
   `cupertino`, `cupertino-dark` und `img-7075` haben **kein** `.git` und sind
   handgebaut — sie müssen ins Repo, nicht geklont werden. `aether` ist leer:
   `aether` ist ein Pacman-Paket, kein User-Theme.

## Frage 1 — Welche Configs kommen ins Repo?

**Empirisch beantwortet: nur die, die sich unterscheiden.** Und das sind fast
keine.

| Datei | Ergebnis |
|---|---|
| `hypr/input.lua` | **abweichend** — +8 Zeilen deutsches Tastaturlayout |
| `git/config` | **abweichend** — Identität + Credential-Helper |
| `nvim/` | eigene LazyVim-Config, Omarchy liefert keine |
| `alacritty`, `btop`, `foot`, `ghostty`, `kitty`, `lazygit`, `tmux` | **stock**, byte-identisch |
| `hypr/{hyprland,monitors,bindings,looknfeel,autostart}.lua`, `hyprsunset.conf`, `xdph.conf`, `.luarc.json` | **stock**, byte-identisch |
| `starship` | existiert gar nicht (nur das Paket-Default) |

Die Stock-Dateien wurden **nicht** aufgenommen. Sie per Stow zu verlinken würde
die heutigen Defaults als Symlink einfrieren und künftige Paket-Updates
aussperren — genau das, was §4 des Guides vermeiden will. Sobald eine davon
wirklich angepasst wird, kommt sie dazu.

Ebenfalls nicht aufgenommen: `extensions/omarchy-menu.jsonc` (nur Kommentare,
kein aktiver Eintrag) und `branding/{about,screensaver}.txt` (Kopien von
`icon.txt` / `logo.txt` aus dem Paket).

## Frage 2 — `henri.keystroke` und `henri.menu`

- **`henri.menu`** ist ein Clone des eingebauten `omarchy.menu`
  (`"clonedFrom": "omarchy.menu"`), aber stark verändert: 658 Diff-Zeilen in
  `Menu.qml`, 85 in `MenuModel.js`, plus eine eigene `FuzzySearch.js`.
  → **Als Quellcode im Repo** (108 KB). `omarchy plugin clone` würde die
  Änderungen verlieren.
- **`henri.keystroke`** ist ein sauberer 2-Commit-Fork von
  `evindor.keystroke` 1.4.2, der die Codex- gegen die Claude-Code-Integration
  tauscht. Arbeitsverzeichnis clean, Branch `master`, kein Remote.
  → **Braucht ein eigenes Repo**, nicht 22 MB vendored hier. Danach:
  `HENRI_KEYSTROKE_URL=<url> ./install_all.sh 30`. Schritt 30 warnt bis dahin
  und läuft weiter.

## Frage 3 — Altlasten

**Nicht gelöscht.** Sie stehen in `.gitignore` (`*.bak*`,
`*.pre-dotfiles.*`) und landen damit nie im Repo. Das Aufräumen im laufenden
System ist eine separate Entscheidung — die sechs Dateien liegen weiter an
ihrem Platz.

## Paketliste

174 explizit installierte Pakete, minus die 206 aus
`omarchy-{base,other}.packages` = 19 Zusätze. Davon gehören 6 nicht in ein
Dotfiles-Repo (`efibootmgr`, `intel-ucode`, `mkinitcpio`, `sudo` = Basissystem;
`omarchy`, `omarchy-keyring`, `omarchy-settings` = Omarchy selbst). Bleiben 12
echte Zusätze + `stow`. Siehe `packages/packages.txt`.

## Größe

Naiv kopiert wären es 237 MB. Das Repo liegt bei **~1,8 MB**: die 32-MB-Datei
`IMG_7075.png` (ein privates Foto, in *beiden* Themes identisch — gleiche MD5)
bleibt aus dem öffentlichen Repo heraus und wird von Schritt 40 aus
`~/Wallpapers/` platziert.
