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

-- Deutsches Tastaturlayout.
hl.config({
  input = {
    kb_layout = "de",
    kb_options = "compose:caps,shift:both_capslock_cancel",
  },
})

-- 4-Finger-Wisch hoch/runter: Mission Control (henri.missioncontrol).
-- Folgt den Fingern: Start/Update/Ende gehen als Custom-Event über Hyprlands
-- Event-Socket an das Plugin, das die Animation live mitführt und beim
-- Loslassen je nach Weg und Tempo öffnet oder schließt.
-- Hinweis: Gesten lassen sich nicht per `hyprctl reload` entfernen – nach
-- Änderungen ab- und wieder anmelden.
local function mc_event(phase, value, time_ms)
  hl.dispatch(hl.dsp.event(string.format("mission-control-gesture:%s:%s:%d",
    phase, value, math.floor(time_ms or 0))))
end
hl.gesture({
  fingers = 4,
  direction = "vertical",
  action = {
    start = function(e) mc_event("start", string.format("%.3f", e.delta and e.delta.y or 0), e.time_ms) end,
    update = function(e) mc_event("update", string.format("%.3f", e.delta and e.delta.y or 0), e.time_ms) end,
    -- Hyprland names the release callback `finish`, not `end`.
    finish = function(e) mc_event("end", e.cancelled and 1 or 0, e.time_ms) end,
  },
})

-- 4-Finger-Wisch zur Seite: Workspace wechseln (folgt den Fingern).
-- Solange Mission Control offen ist, tauscht das Plugin diese Geste über
-- mission_control_swipe_mode(true) gegen eine Variante, die die Bewegung ans
-- Plugin schickt – dort gleitet dann die Übersicht zur Seite wie bei macOS.
-- Beim Schließen kommt mit mission_control_swipe_mode(false) die normale
-- Workspace-Geste zurück. Ein Reload setzt beides auf den Normalzustand.
local function mc_hswipe_event(phase, value, time_ms)
  hl.dispatch(hl.dsp.event(string.format("mission-control-hswipe:%s:%s:%d",
    phase, value, math.floor(time_ms or 0))))
end
local mc_hswipe_active = false
function mission_control_swipe_mode(open)
  open = open and true or false
  if open == mc_hswipe_active then return end
  mc_hswipe_active = open
  hl.gesture({ fingers = 4, direction = "horizontal", action = "unset" })
  if open then
    hl.gesture({
      fingers = 4,
      direction = "horizontal",
      action = {
        start = function(e) mc_hswipe_event("start", string.format("%.3f", e.delta and e.delta.x or 0), e.time_ms) end,
        update = function(e) mc_hswipe_event("update", string.format("%.3f", e.delta and e.delta.x or 0), e.time_ms) end,
        finish = function(e) mc_hswipe_event("end", e.cancelled and 1 or 0, e.time_ms) end,
      },
    })
  else
    hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
  end
end
hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })

-- Wischgeste feiner abstimmen (fühlt sich eher wie macOS an).
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

-- Ziehen ohne Drücken, damit die Wippen-Mechanik des XPS-Trackpads
-- (oben schwer bis gar nicht klickbar) beim Markieren keine Rolle spielt.
--   * 3 Finger auflegen und bewegen = gedrückt halten und ziehen
--     (greift dank gepatchtem libinput auch bei schnellem Losziehen,
--     siehe ~/Projects/dotfiles/packages/libinput-3fg-drag)
--     (Text markieren, Screenshot-Bereich aufziehen, Fenster verschieben).
--     Kurz absetzen und weiterziehen geht; losgelassen wird nach ~0,7 s.
--   * Doppeltippen und beim zweiten Tipp liegen lassen = ziehen; mit
--     drag_lock darf der Finger kurz hoch, um nachzusetzen.
-- Beschleunigungskurve nur fürs Trackpad: langsame Bewegungen werden
-- gebremst (präzises Markieren), schnelle deutlich beschleunigt – wie am Mac.
-- Punkte = Ausgabetempo bei Eingabetempo 0, 1, 2 … (Einheiten/ms).
-- Zu schnell/langsam? Alle Punkte ab dem zweiten gleichmäßig skalieren.
hl.device({
  name = "dll0945:00-06cb:cde6-touchpad",
  drag_3fg = 1,
  tap_and_drag = true,
  drag_lock = 1,
  accel_profile = "custom 1 0 0.7 1.8 3.3 5.2 7.5 10.2",
})
