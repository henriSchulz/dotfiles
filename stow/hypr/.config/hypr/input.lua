-- Keep only your personal input overrides here. Uncommented settings below
-- replace Omarchy's defaults.

-- Keyboard layout and options.
-- See https://wiki.hypr.land/Configuring/Basics/Variables/#input
-- hl.config({
--   input = {
--     -- Use multiple keyboard layouts and switch between them with Left Alt + Right Alt.
--     kb_layout = "us,dk,eu",
--     kb_options = "compose:caps,shift:both_capslock_cancel,grp:alts_toggle",
--
--     -- Use a specific keyboard variant if needed (e.g. intl for international keyboards).
--     kb_variant = "intl",
--
--     -- Change speed of keyboard repeat.
--     repeat_rate = 40,
--     repeat_delay = 250,
--
--     -- Start with numlock on by default.
--     numlock_by_default = true,
--
--     -- Increase sensitivity for mouse/trackpad (default: 0).
--     sensitivity = 0.35,
--
--     -- Turn off mouse acceleration (default: adaptive).
--     accel_profile = "flat",
--
--     touchpad = {
--       -- Use natural (inverse) scrolling.
--       natural_scroll = true,
--
--       -- Use two-finger clicks for right-click instead of lower-right corner.
--       clickfinger_behavior = true,
--
--       -- Control the speed of your scrolling.
--       scroll_factor = 0.4,
--
--       -- Enable the touchpad while typing.
--       disable_while_typing = false,
--
--       -- Left-click-and-drag with three fingers.
--       drag_3fg = 1,
--     },
--   },
-- })

-- App-specific touchpad scroll speeds.
-- o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 1.5 })
-- o.window("com.mitchellh.ghostty", { scroll_touchpad = 0.2 })

-- Enable touchpad gestures for changing workspaces.
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
-- hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Enable touchpad gestures for moving focus (helpful on scrolling layout).
-- hl.gesture({ fingers = 3, direction = "left", action = function() hl.dispatch(hl.dsp.focus({ direction = "l" })) end })
-- hl.gesture({ fingers = 3, direction = "right", action = function() hl.dispatch(hl.dsp.focus({ direction = "r" })) end })

-- Deutsches Tastaturlayout. Caps Lock ist wieder Caps Lock (mit Lämpchen):
-- Omarchys Standard macht die Taste zur Compose-Taste und legt Caps Lock auf
-- beide Shift-Tasten, dann leuchtet das Lämpchen nie. Compose entfällt.
hl.config({
  input = {
    kb_layout = "de",
    kb_options = "",
    -- NumLock schaltet auf der Acer-Tastatur die Buchstaben auf Ziffernblock;
    -- Fn+F11 ist per hwdb abgeschaltet (dotfiles/system/acer-numlock).
    numlock_by_default = false,
  },
})

-- 4-Finger-Wisch hoch/runter: Mission Control.
-- Mit hyprmc (~/Projects/hyprmc, Hyprland-Plugin, README dort) zoomt Hoch aus
-- der Spur der Desktops heraus – die echten Fenster, im Compositor, ab dem
-- ersten Bild unter den Fingern; Runter zoomt in den gewählten Desktop. Fehlt
-- das Plugin (z. B. nach einem Hyprland-Update ohne
-- `~/Projects/hyprmc/scripts/install.sh`), geht der Wisch wie früher ans
-- QML-Plugin henri.missioncontrol-v3: Hoch öffnet Mission Control, Runter App
-- Exposé, Start/Update/Ende als Custom-Event über Hyprlands Event-Socket.
-- Tasten dazu: F8 / Shift+F8 / Ctrl+F8 in bindings.lua.
-- Hinweis: Ein `hyprctl reload` startet ohne Gesten und registriert sie neu
-- (geprüft 2026-09-26 in einer verschachtelten Instanz); zur Laufzeit entfernt
-- sie nur `action = "unset"`.
local function mc_event(phase, value, time_ms)
  hl.dispatch(hl.dsp.event(string.format("mission-control-gesture:%s:%s:%d",
    phase, value, math.floor(time_ms or 0))))
end
-- Lädt das Plugin (mit Hinweis, wenn die .so fehlt). Fehlt das ganze Repo,
-- bleibt hyprmc nil und alles geht ans QML-Plugin.
local hyprmc_lua = os.getenv("HOME") .. "/Projects/hyprmc/hyprmc.lua"
local hyprmc = nil
local hyprmc_fh = io.open(hyprmc_lua, "r")
if hyprmc_fh then
  hyprmc_fh:close()
  local ok, mod = pcall(dofile, hyprmc_lua)
  if ok then hyprmc = mod() end
end
local function mc_gesture(phase, e)
  if hyprmc and hyprmc.available() then
    hyprmc.gesture(phase, e)
  else
    local dy = e.delta and e.delta.y or 0
    mc_event(phase, phase == "end" and (e.cancelled and 1 or 0) or string.format("%.3f", dy), e.time_ms)
  end
end
hl.gesture({
  fingers = 4,
  direction = "vertical",
  action = {
    start = function(e) mc_gesture("start", e) end,
    update = function(e) mc_gesture("update", e) end,
    -- Hyprland names the release callback `finish`, not `end`.
    finish = function(e) mc_gesture("end", e) end,
  },
})

-- 4-Finger-Wisch zur Seite: Workspace wechseln wie macOS Spaces (hyprswipe,
-- ~/Projects/hyprswipe, Spec: ~/Downloads/workspace-swipe-spec.md). Der Inhalt
-- klebt 1:1 an den Fingern, federt an den Rändern, und beim Loslassen übernimmt
-- eine Feder die Fingergeschwindigkeit. Alle Parameter live per
-- `hyprctl hyprswipe` / `hyprctl hyprswipe set <key> <wert>`. Fehlt das Plugin
-- (z. B. nach einem Hyprland-Update: `~/Projects/hyprswipe/scripts/install.sh`),
-- registriert der Helper Hyprlands eingebauten Workspace-Wisch als Fallback.
local hyprswipe = dofile(os.getenv("HOME") .. "/Projects/hyprswipe/hyprswipe.lua")({
  fingers = 4,
  config = { gap = 40, swipeDistance = 550 }, -- 550 Gesteneinheiten = eine Seite, wie bisher
})

-- Solange Mission Control offen ist, tauscht das Plugin diese Geste über
-- mission_control_swipe_mode(true) gegen eine Variante, die die Bewegung ans
-- Plugin schickt – dort gleitet dann die Übersicht zur Seite wie bei macOS.
-- Beim Schließen kommt mit mission_control_swipe_mode(false) die normale
-- Workspace-Geste zurück. Ein Reload setzt beides auf den Normalzustand.
local function mc_hswipe_event(phase, value, time_ms)
  hl.dispatch(hl.dsp.event(string.format("mission-control-hswipe:%s:%s:%d",
    phase, value, math.floor(time_ms or 0))))
end
-- Ist hyprmc offen (es schaltet diesen Modus selbst ein und aus), wählt die
-- Seitwärtsbewegung dort den Desktop; sonst geht sie wie bisher ans QML-Plugin.
local function mc_hswipe(phase, e)
  local dx = e.delta and e.delta.x or 0
  if hyprmc and hyprmc.session() then
    hyprmc.pan(phase, e)
  else
    mc_hswipe_event(phase, phase == "end" and (e.cancelled and 1 or 0) or string.format("%.3f", dx), e.time_ms)
  end
end
local mc_hswipe_active = false
function mission_control_swipe_mode(open)
  open = open and true or false
  if open == mc_hswipe_active then return end
  mc_hswipe_active = open
  hyprswipe.unregister()
  if open then
    hl.gesture({
      fingers = 4,
      direction = "horizontal",
      action = {
        start = function(e) mc_hswipe("start", e) end,
        update = function(e) mc_hswipe("update", e) end,
        finish = function(e) mc_hswipe("end", e) end,
      },
    })
  else
    hyprswipe.register()
  end
end

-- Eingebauten Wisch feiner abstimmen (nur noch als Fallback ohne Plugin).
hl.config({
  gestures = {
    workspace_swipe_distance = 550,        -- kürzerer Weg = weniger Wischen pro Workspace (vorher 850)
    workspace_swipe_cancel_ratio = 0.1,    -- schon ab 1/10 des Wegs wird gewechselt
    workspace_swipe_min_speed_to_force = 6, -- auch ein kurzer, mäßig schneller Wisch reicht
  },
})

-- Rechtsklick wie am Mac: mit 2 Fingern klicken oder tippen.
hl.config({
  input = {
    touchpad = {
      clickfinger_behavior = true, -- 2 Finger drücken = Rechtsklick, 3 Finger = Mittelklick
      tap_to_click = true,         -- Tippen = Klick, 2 Finger tippen = Rechtsklick
      natural_scroll = true,       -- Scrollrichtung wie am Mac (Inhalt folgt den Fingern)
    },
  },
})

-- Ziehen ohne Drücken (eingeführt für die Wippen-Mechanik des XPS-Trackpads,
-- oben schwer bis gar nicht klickbar; bleibt auf dem M1, wie am Mac).
--   * 3 Finger auflegen und bewegen = gedrückt halten und ziehen
--     (greift dank gepatchtem libinput auch bei schnellem Losziehen,
--     siehe ~/Projects/dotfiles/packages/libinput-3fg-drag)
--     (Text markieren, Screenshot-Bereich aufziehen, Fenster verschieben).
--     Kurz absetzen und weiterziehen geht; losgelassen wird nach ~0,7 s.
--   * Doppeltippen und beim zweiten Tipp liegen lassen = ziehen; mit
--     drag_lock darf der Finger kurz hoch, um nachzusetzen.
-- Keine eigene Beschleunigungskurve: die des XPS (custom 1 0 0.7 1.8 3.3 5.2
-- 7.5 10.2) war auf dessen Touchpad abgestimmt und macht den Zeiger auf dem
-- M1-Trackpad viel zu schnell. libinputs Standard (adaptive) gilt.
for _, name in ipairs({
  "apple-spi-trackpad",                     -- M1 MacBook Air (the XPS was dll0945:00-06cb:cde6-touchpad)
  "chicony-acer-hawaii-keyboard-touchpad",  -- Acer Switch Alpha 12, keyboard cover
}) do
  hl.device({
    name = name,
    drag_3fg = 1,
    tap_and_drag = true,
    drag_lock = 1,
  })
end

-- Tastaturbeleuchtung (henri.kbdlight): jeder Tastendruck meldet sich als
-- Custom-Event beim Shell-Dienst, der die Beleuchtung einblendet und seine
-- Ausschalt-Uhr neu startet. Höchstens ein Event pro Sekunde -- genauer muss
-- die Uhr nicht sein, und Tippen kostet so nichts. Über Hyprland statt
-- /dev/input, weil das ohne Gruppe "input" und ohne root geht.
-- (Die Zeit im Event taugt nicht zum Drosseln: bei send_shortcut steht sie.)
local kbdlight_last = 0
hl.on("input.keyboard.key", function(_, _, state)
  if state ~= 1 then return end
  local now = os.time()
  if now == kbdlight_last then return end
  kbdlight_last = now
  hl.dispatch(hl.dsp.event("kbdlight key"))
end)

-- 3-Finger-Pinch: Launchpad (henri.launchpad-v3) wie am Mac. Zusammenziehen
-- öffnet, Auseinanderziehen schließt. Als Hyprland-Ereignis direkt ans Plugin
-- (custom>>launchpad open|close), kein Prozess pro Geste. Die 4-Finger-Gesten
-- oben (Mission Control, Workspaces) bleiben unberührt.
hl.gesture({ fingers = 3, direction = "pinchin", action = function() hl.dispatch(hl.dsp.event("launchpad open")) end })
hl.gesture({ fingers = 3, direction = "pinchout", action = function() hl.dispatch(hl.dsp.event("launchpad close")) end })
