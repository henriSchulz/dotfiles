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

-- Super+Backspace in Files (Nautilus) = in den Papierkorb, wie Cmd+Backspace im
-- Finder; in allen anderen Fenstern bleibt es Omarchys Transparenz-Umschalter.
-- Nautilus bekommt Entf statt Backspace, damit der weitergereichte Tastendruck
-- nicht wieder dieses Binding trifft; henri_files.py fängt Super+Entf ab
-- (Entf allein ist ohnehin Nautilus' Papierkorb-Taste). Muster wie Omarchys
-- Super+C/V (default/hypr/bindings/clipboard.lua).
hl.unbind("SUPER + BACKSPACE")
o.bind("SUPER + BACKSPACE", "Move to Trash (Files) / Toggle window transparency", function()
  local window = hl.get_active_window()
  if window and window.class == "org.gnome.Nautilus" then
    hl.dispatch(hl.dsp.send_key_state({ mods = "", key = "Delete", state = "down" }))
    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = "", key = "Delete", state = "up" }))
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
-- zweiter Weg bestehen, F9 (halten) ebenfalls.

-- Sprach-Assistent (henri.assistant): SUPER+A öffnet die Karte und hört sofort
-- zu, dieselbe Tastenkombination stoppt die Aufnahme und diktiert den nächsten
-- Zug, ↵ schickt die Frage an Antigravity, Esc schließt.
--
-- Nicht auf SUPER + rechte Strg, obwohl das die naheliegende Stelle wäre: die
-- rechte Strg ist selbst ein Modifikator, die Modifikatorlage ändert sich also
-- mitten im Akkord und Hyprland wertet die Bindings dabei neu aus. Sobald SUPER
-- vor der rechten Strg losgelassen wurde, passte das Diktat-Binding darunter
-- (CTRL + Control_R) und dessen `voxtype record toggle` stoppte genau die
-- Aufnahme, die der Assistent eine Zehntelsekunde vorher gestartet hatte.
-- Eine gewöhnliche Buchstabentaste hat dieses Problem nicht.
o.bind("SUPER + A", "Voice assistant", hl.dsp.event("assistant toggle"))

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
