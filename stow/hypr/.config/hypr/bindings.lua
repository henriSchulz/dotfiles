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
hl.unbind("SUPER + TAB")
hl.unbind("SUPER + SHIFT + TAB")
o.bind("SUPER + TAB", "Workspace switcher", "omarchy-shell -q workspace-switcher next")
o.bind("SUPER + SHIFT + TAB", "Workspace switcher (previous)", "omarchy-shell -q workspace-switcher prev")
o.bind("SUPER + SUPER_L", nil, "omarchy-shell -q workspace-switcher commit", { release = true })
o.bind("SUPER + SHIFT + SUPER_L", nil, "omarchy-shell -q workspace-switcher commit", { release = true })

-- Audio, Bluetooth, Display und WLAN sind nicht mehr in der Leiste, sondern
-- im Kontrollzentrum (henri.control-center). Omarchys Kürzel öffnen daher
-- jetzt die passende Seite dort; nochmal drücken schließt.
hl.unbind("SUPER + CTRL + A")
hl.unbind("SUPER + CTRL + B")
hl.unbind("SUPER + CTRL + D")
hl.unbind("SUPER + CTRL + W")
o.bind("SUPER + CTRL + A", "Sound", "omarchy-shell henri.control-center togglePage sound")
o.bind("SUPER + CTRL + B", "Bluetooth", "omarchy-shell henri.control-center togglePage bluetooth")
o.bind("SUPER + CTRL + D", "Display", "omarchy-shell henri.control-center togglePage display")
o.bind("SUPER + CTRL + W", "Wi-Fi", "omarchy-shell henri.control-center togglePage wifi")

-- SUPER+CTRL+SPACE war Omarchys Hintergrund-Switcher (nur Bilder des Themes).
-- Jetzt öffnet es den globalen Wallpaper-Picker (Plugin henri.wallpaper,
-- Ordner ~/Pictures/Wallpaper, Auswahl bleibt über Theme-Wechsel erhalten).
hl.unbind("SUPER + CTRL + SPACE")
o.bind("SUPER + CTRL + SPACE", "Wallpaper", "omarchy-shell -q wallpaper toggle")
