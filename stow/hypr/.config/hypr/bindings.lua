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

-- SUPER+SHIFT+G war standardmäßig "Signal" (webapp). Jetzt startet es Gemini
-- im Terminal, nach demselben Muster wie das Claude-Binding oben.
hl.unbind("SUPER + SHIFT + G")
o.bind("SUPER + SHIFT + G", "Gemini", "omarchy-launch-tui --app-id=org.omarchy.agent gemini --yolo")

-- Super+Tab wie unter Windows: Super halten + Tab zeigt eine Vorschau aller
-- Workspaces (Plugin henri.workspace-switcher), jedes weitere Tab wählt den
-- nächsten, Loslassen von Super wechselt. Ersetzt Omarchys "Next/Previous workspace".
hl.unbind("SUPER + TAB")
hl.unbind("SUPER + SHIFT + TAB")
o.bind("SUPER + TAB", "Workspace-Umschalter", "omarchy-shell -q workspace-switcher next")
o.bind("SUPER + SHIFT + TAB", "Workspace-Umschalter zurück", "omarchy-shell -q workspace-switcher prev")
o.bind("SUPER + SUPER_L", nil, "omarchy-shell -q workspace-switcher commit", { release = true })
o.bind("SUPER + SHIFT + SUPER_L", nil, "omarchy-shell -q workspace-switcher commit", { release = true })
