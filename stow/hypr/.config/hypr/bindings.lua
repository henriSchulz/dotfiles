-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- SUPER+SHIFT+C war standardmäßig "Calendar" (webapp hey.com/calendar).
-- Jetzt startet es Claude Code im Terminal (fest auf claude, unabhängig vom
-- via `omarchy default agent` konfigurierten Default-Agent).
hl.unbind("SUPER + SHIFT + C")
o.bind("SUPER + SHIFT + C", "Claude", "omarchy-launch-tui --app-id=org.omarchy.agent claude --permission-mode auto")

-- SUPER+SHIFT+G war standardmäßig "Signal" (webapp). Jetzt startet es die
-- "agy"-CLI (Nachfolger von "gemini", das nicht mehr unterstützt wird) im
-- Terminal, nach demselben Muster wie das Claude-Binding oben.
hl.unbind("SUPER + SHIFT + G")
o.bind("SUPER + SHIFT + G", "Agy", "omarchy-launch-tui --app-id=org.omarchy.agent agy --mode accept-edits")

-- Super+Tab wie unter Windows: Super halten + Tab zeigt eine Vorschau aller
-- Workspaces (Plugin henri.workspace-switcher), jedes weitere Tab wählt den
-- nächsten, Loslassen von Super wechselt. Ersetzt Omarchys "Next/Previous workspace".
-- Die Tasten gehen als Hyprland-Ereignis (custom>>workspace-switcher …) direkt an
-- das Plugin: kein Prozess pro Taste, also keine Latenz und immer in Reihenfolge.
hl.unbind("SUPER + TAB")
hl.unbind("SUPER + SHIFT + TAB")
o.bind("SUPER + TAB", "Workspace switcher", hl.dsp.event("workspace-switcher next"))
o.bind("SUPER + SHIFT + TAB", "Workspace switcher (previous)", hl.dsp.event("workspace-switcher prev"))
-- transparent: Nach Super+Tab sperrt ("shadowt") Hyprland alle Bindings auf der
-- noch gedrückten Super-Taste — ohne das Flag feuert das Loslassen nie.
o.bind("SUPER + SUPER_L", nil, hl.dsp.event("workspace-switcher commit"), { release = true, transparent = true })
o.bind("SUPER + SHIFT + SUPER_L", nil, hl.dsp.event("workspace-switcher commit"), { release = true, transparent = true })

-- Audio, Bluetooth, Display und WLAN sind nicht mehr in der Leiste, sondern
-- im Kontrollzentrum (henri.control-center-v2). Omarchys Kürzel öffnen daher
-- jetzt die passende Seite dort; nochmal drücken schließt.
hl.unbind("SUPER + CTRL + A")
hl.unbind("SUPER + CTRL + B")
hl.unbind("SUPER + CTRL + D")
hl.unbind("SUPER + CTRL + W")
o.bind("SUPER + CTRL + A", "Sound", "omarchy-shell henri.control-center-v2 togglePage sound")
o.bind("SUPER + CTRL + B", "Bluetooth", "omarchy-shell henri.control-center-v2 togglePage bluetooth")
o.bind("SUPER + CTRL + D", "Display", "omarchy-shell henri.control-center-v2 togglePage display")
o.bind("SUPER + CTRL + W", "Wi-Fi", "omarchy-shell henri.control-center-v2 togglePage wifi")

-- Öffnet das Kontrollzentrum auf der Übersichtsseite (nicht auf einer
-- Detailseite wie die Kürzel oben); nochmal drücken schließt. Danach im
-- Popup mit Tab/Shift+Tab durch die Kacheln navigieren.
o.bind("SUPER + CTRL + G", "Control Center", "omarchy-shell henri.control-center-v2 toggle")

-- SUPER+CTRL+SPACE war Omarchys Hintergrund-Switcher (nur Bilder des Themes).
-- Jetzt öffnet es den globalen Wallpaper-Picker (Plugin henri.wallpaper,
-- Ordner ~/Pictures/Wallpaper, Auswahl bleibt über Theme-Wechsel erhalten).
hl.unbind("SUPER + CTRL + SPACE")
o.bind("SUPER + CTRL + SPACE", "Wallpaper", "omarchy-shell -q wallpaper toggle")

-- Spotlight (henri.menu). Omarchys Standard rief `omarchy-menu toggle` auf:
-- bash → jq → bash → qs-IPC-Client, zusammen ~95 ms Prozessstart, bevor die
-- Shell vom Tastendruck etwas merkte. Die Tasten gehen jetzt als Hyprland-
-- Ereignis (custom>>menu …) direkt an das Plugin — kein Prozess, keine Latenz,
-- wie beim Super+Tab-Switcher.
hl.unbind("SUPER + SPACE")
hl.unbind("SUPER + ALT + SPACE")
o.bind("SUPER + SPACE", "Spotlight", hl.dsp.event("menu toggle root"))
o.bind("SUPER + ALT + SPACE", "Apps menu", hl.dsp.event("menu toggle apps"))

-- Lautstärke/Helligkeit wie macOS (Plugin henri.osd): 16 Stufen, Alt = Viertel-
-- stufe. Die Tasten gehen als Hyprland-Ereignis (custom>>osd …) direkt an das
-- Plugin, das PipeWire bzw. die Hintergrundbeleuchtung im selben Frame setzt.
-- Omarchys Weg (bash → pactl ×4 → jq → Shell-IPC pro Tastendruck, ~150 ms)
-- ließ die Anzeige hinterherhinken und Tastenwiederholungen stauen.
for _, k in ipairs({ "XF86AudioRaiseVolume", "XF86AudioLowerVolume", "XF86AudioMute",
  "XF86MonBrightnessUp", "XF86MonBrightnessDown",
  "ALT + XF86AudioRaiseVolume", "ALT + XF86AudioLowerVolume",
  "ALT + XF86MonBrightnessUp", "ALT + XF86MonBrightnessDown" }) do
  hl.unbind(k)
end
o.bind("XF86AudioRaiseVolume", "Volume up", hl.dsp.event("osd volume up"), { locked = true, repeating = true })
o.bind("XF86AudioLowerVolume", "Volume down", hl.dsp.event("osd volume down"), { locked = true, repeating = true })
o.bind("XF86AudioMute", "Mute", hl.dsp.event("osd volume mute"), { locked = true })
o.bind("ALT + XF86AudioRaiseVolume", "Volume up precise", hl.dsp.event("osd volume up-fine"), { locked = true, repeating = true })
o.bind("ALT + XF86AudioLowerVolume", "Volume down precise", hl.dsp.event("osd volume down-fine"), { locked = true, repeating = true })
o.bind("XF86MonBrightnessUp", "Brightness up", hl.dsp.event("osd brightness up"), { locked = true, repeating = true })
o.bind("XF86MonBrightnessDown", "Brightness down", hl.dsp.event("osd brightness down"), { locked = true, repeating = true })
o.bind("ALT + XF86MonBrightnessUp", "Brightness up precise", hl.dsp.event("osd brightness up-fine"), { locked = true, repeating = true })
o.bind("ALT + XF86MonBrightnessDown", "Brightness down precise", hl.dsp.event("osd brightness down-fine"), { locked = true, repeating = true })

-- Dateimanager ist der Finder (~/Projects/finder), nicht mehr Files (Nautilus):
-- SUPER+SHIFT+F und SUPER+ALT+SHIFT+F riefen Omarchys omarchy-launch-nautilus
-- bzw. -nautilus-cwd auf. Gleiche Tasten, gleiche Bedeutung (neues Fenster,
-- bzw. neues Fenster im Arbeitsverzeichnis des aktiven Terminals), anderes
-- Programm. Den Rest (xdg-open, „Im Ordner zeigen“, Dock) stellt
-- finder/bin/finder-install um.
hl.unbind("SUPER + SHIFT + F")
hl.unbind("SUPER + ALT + SHIFT + F")
o.bind("SUPER + SHIFT + F", "File manager", { launch = "finder --new-window" })
o.bind("SUPER + ALT + SHIFT + F", "File manager (cwd)",
  [[sh -c 'exec setsid uwsm-app -- finder --new-window "$(omarchy-cmd-terminal-cwd)"']])

-- Super+Backspace in Files (Nautilus) und im Finder = in den Papierkorb, wie
-- Cmd+Backspace am Mac; in allen anderen Fenstern bleibt es Omarchys
-- Transparenz-Umschalter.
-- Nautilus bekommt Entf statt Backspace, damit der weitergereichte Tastendruck
-- nicht wieder dieses Binding trifft; henri_files.py fängt Super+Entf ab
-- (Entf allein ist ohnehin Nautilus' Papierkorb-Taste). Muster wie Omarchys
-- Super+C/V (default/hypr/bindings/clipboard.lua).
hl.unbind("SUPER + BACKSPACE")
o.bind("SUPER + BACKSPACE", "Move to Trash (Files, Finder) / Toggle window transparency", function()
  local window = hl.get_active_window()
  if window and window.class == "org.gnome.Nautilus" then
    hl.dispatch(hl.dsp.send_key_state({ mods = "", key = "Delete", state = "down" }))
    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = "", key = "Delete", state = "up" }))
    end, { timeout = 50, type = "oneshot" })
  elseif window and window.class == "de.henri.Finder" then
    -- Finder (~/Projects/finder) nimmt Strg+Entf wie Strg+Rücktaste als
    -- „In den Papierkorb“; Entf statt Rücktaste aus demselben Grund wie oben.
    hl.dispatch(hl.dsp.send_key_state({ mods = "CTRL", key = "Delete", state = "down" }))
    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = "CTRL", key = "Delete", state = "up" }))
    end, { timeout = 50, type = "oneshot" })
  else
    hl.dispatch(hl.dsp.exec_cmd("omarchy-hyprland-window-transparency-toggle"))
  end
end)

-- Diktat (voxtype): die rechte Strg-Taste allein schaltet die Aufnahme um.
-- Einmal tippen = Aufnahme läuft, nochmal tippen = Text wird getippt.
-- Eine Taste, kein Akkord, rechte Hand — die linke bleibt frei.
--
-- Warum hier und nicht in voxtypes eigener Hotkey-Erkennung: die liest
-- /dev/input direkt und braucht dafür Mitgliedschaft in der Gruppe "input".
-- Die fehlt, deshalb hat voxtypes Standard-Hotkey (SCROLLLOCK, den das
-- XPS 13 ohnehin nicht hat) nie ausgelöst. Über Hyprland geht es ohne root.
--
-- Nebenwirkung: Hyprland verbraucht den Tastendruck, die rechte Strg wirkt
-- also nicht mehr als Modifikator. Linke Strg ist unberührt.
-- Beide Varianten: ob Hyprland den CTRL-Modifikator beim Druck der Taste
-- selbst schon gesetzt hat, haengt an der Reihenfolge im Compositor. Die
-- Modmasken 0 und CTRL schliessen sich gegenseitig aus, es feuert also
-- immer genau eine der beiden.
o.bind("CTRL + Control_R", "Dictation toggle", "voxtype record toggle")
o.bind("Control_R", "Dictation toggle", "voxtype record toggle")

-- Verschrieben? `voxtype record cancel` wirft die laufende Aufnahme weg,
-- ohne Text einzufuegen. Omarchys Standard SUPER+CTRL+X (Toggle) bleibt als
-- zweiter Weg bestehen; Omarchys F9-Push-to-Talk ist zugunsten von App Exposé
-- abgeschaltet (siehe Mission Control unten).

-- SUPER+A = Alles auswählen, wie Cmd+A am Mac (vorher öffnete es den
-- Sprach-Assistenten henri.assistant). Muster wie Omarchys Super+C/V/X
-- (default/hypr/bindings/clipboard.lua): Ctrl+A geht direkt an die fokussierte
-- Oberfläche, Down/Up getrennt, damit die synthetische Taste nicht hängen bleibt.
o.bind("SUPER + A", "Select all", function()
  hl.dispatch(hl.dsp.send_key_state({ mods = "CTRL", key = "A", state = "down" }))
  hl.timer(function()
    hl.dispatch(hl.dsp.send_key_state({ mods = "CTRL", key = "A", state = "up" }))
  end, { timeout = 50, type = "oneshot" })
end)

-- App-Switcher wie ⌘+Tab am Mac (Plugin henri.app-switcher): Alt halten und Tab
-- zeigt eine Reihe von App-Symbolen, zuletzt benutzte zuerst; jedes weitere Tab
-- wählt die nächste App, Loslassen von Alt wechselt, Esc bricht ab. Kurzes
-- Antippen springt direkt zur vorherigen App, ohne dass die Reihe aufblitzt.
--
-- Warum Alt und nicht Fn: Fn wird auf dem XPS im Tastatur-Controller selbst
-- verarbeitet und erreicht den Kernel nie als eigene Taste (nachgemessen: Fn+Tab
-- sendet exakt denselben Code wie Tab allein), ist für Hyprland also nicht
-- bindbar. Alt liegt dafür genau dort, wo am Mac ⌘ liegt — links neben der
-- Leertaste. Ersetzt Omarchys "Focus on next window"/"Reveal active window on
-- top", die beide auf ALT+TAB lagen und Fenster statt Apps durchschalteten.
--
-- Die Tasten gehen als Hyprland-Ereignis (custom>>app-switcher …) direkt an das
-- Plugin: kein Prozess pro Taste, also keine Latenz und immer in Reihenfolge.
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")
o.bind("ALT + TAB", "App switcher", hl.dsp.event("app-switcher next"))
o.bind("ALT + SHIFT + TAB", "App switcher (previous)", hl.dsp.event("app-switcher prev"))
o.bind("ALT + ESCAPE", "App switcher (cancel)", hl.dsp.event("app-switcher cancel"))
-- transparent: Nach Alt+Tab sperrt ("shadowt") Hyprland alle Bindings auf der
-- noch gedrückten Alt-Taste — ohne das Flag feuert das Loslassen nie.
o.bind("ALT + Alt_L", nil, hl.dsp.event("app-switcher commit"), { release = true, transparent = true })
o.bind("ALT + SHIFT + Alt_L", nil, hl.dsp.event("app-switcher commit"), { release = true, transparent = true })

-- Mission Control (henri.missioncontrol) auf F8: die einzige noch freie Taste.
-- Weder Omarchy noch diese Datei hatten F8 belegt, und auch die Medienfunktion
-- der Taste auf dem XPS 13 (Display umschalten, Keysym XF86Display) war ohne
-- Binding -- je nach Fn-Lock kommt das eine oder das andere Keysym an, deshalb
-- beide. F9 (und Shift+F8) = App Exposé (nur die Fenster der aktiven App, über
-- alle Desktops), Ctrl+F8 = Schreibtisch anzeigen. Nochmal drücken schließt,
-- eine andere Variante wechselt den Modus, ohne zu schließen. Als
-- Hyprland-Ereignis direkt ans Plugin, wie Spotlight und die Switcher: kein
-- Prozess pro Taste. F9 hatte Omarchy mit voxtype-Push-to-Talk belegt
-- (default/hypr/bindings/voxtype.lua, Druck = start, Loslassen = stop); das
-- fliegt hier raus, Diktat läuft über die rechte Strg und SUPER+CTRL+X.
o.bind("F8", "Mission Control", hl.dsp.event("mission-control toggle"))
hl.unbind("F9")
o.bind("F9", "App Exposé", hl.dsp.event("mission-control toggle app"))
o.bind("SHIFT + F8", "App Exposé", hl.dsp.event("mission-control toggle app"))
o.bind("CTRL + F8", "Show Desktop", hl.dsp.event("mission-control toggle desktop"))
o.bind("XF86Display", "Mission Control", hl.dsp.event("mission-control toggle"))
o.bind("SHIFT + XF86Display", "App Exposé", hl.dsp.event("mission-control toggle app"))
o.bind("CTRL + XF86Display", "Show Desktop", hl.dsp.event("mission-control toggle desktop"))

-- Die F8-Taste selbst (ohne Fn) ist auf dem XPS 13 9310 in der Firmware als
-- Windows+P verdrahtet (Dells "Display umschalten") -- per evdev gemessen:
-- Scancode 0xdb (LEFTMETA) + 0x19 (P), von einem echten Super+P nicht zu
-- unterscheiden; nur Fn+F8 sendet F8. Also bekommt Super+P Mission Control
-- (Omarchys "Pseudo window" darauf entfällt) und Super+Shift+P App Exposé
-- (Omarchys "Google Photos"-Webapp entfällt). Super+Ctrl+P bleibt Omarchys
-- Power-Menü; Schreibtisch anzeigen liegt daher nur auf Ctrl+Fn+F8.
hl.unbind("SUPER + P")
hl.unbind("SUPER + SHIFT + P")
o.bind("SUPER + P", "Mission Control", hl.dsp.event("mission-control toggle"))
o.bind("SUPER + SHIFT + P", "App Exposé", hl.dsp.event("mission-control toggle app"))

-- Dock (henri.dock): Fenster minimieren wie Cmd+M, Dock ein-/ausblenden wie
-- Wahl+Cmd+D, Tastatursteuerung wie Ctrl+F3. Als Hyprland-Ereignis direkt ans
-- Plugin (custom>>dock …), kein Prozess pro Taste. Super+Shift+M bleibt
-- Omarchys Musik-Taste; die Zeitlupe (Shift) gibt es nur per IPC
-- (`omarchy-shell dock minimizeActiveSlow`).
o.bind("SUPER + M", "Minimize window into the Dock", hl.dsp.event("dock minimize"))
o.bind("SUPER + ALT + D", "Toggle Dock hiding", hl.dsp.event("dock toggle-autohide"))
o.bind("SUPER + D", "Show or hide the Dock", hl.dsp.event("dock toggle"))
o.bind("CTRL + F3", "Focus the Dock", hl.dsp.event("dock focus"))
