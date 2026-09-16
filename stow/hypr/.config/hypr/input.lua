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

-- 4-Finger-Wisch: Mission Control (hoch = öffnen/umschalten, runter = schließen).
hl.gesture({
  fingers = 4,
  direction = "up",
  action = function() hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell toggle io.github.andyweiboan.missioncontrol '{}'")) end,
})
hl.gesture({
  fingers = 4,
  direction = "down",
  action = function() hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell hide io.github.andyweiboan.missioncontrol")) end,
})

-- 4-Finger-Wisch zur Seite: Workspace wechseln (folgt den Fingern).
hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })

-- Wischgeste feiner abstimmen (fühlt sich eher wie macOS an).
hl.config({
  gestures = {
    workspace_swipe_distance = 500,        -- längerer Weg = ruhigeres Mitgleiten
    workspace_swipe_cancel_ratio = 0.2,    -- schon ab 1/5 des Wegs wird gewechselt
    workspace_swipe_min_speed_to_force = 15, -- kurzer schneller Wisch reicht
  },
})

-- Rechtsklick wie am Mac: mit 2 Fingern klicken oder tippen.
hl.config({
  input = {
    touchpad = {
      clickfinger_behavior = true, -- 2 Finger drücken = Rechtsklick, 3 Finger = Mittelklick
      tap_to_click = true,         -- Tippen = Klick, 2 Finger tippen = Rechtsklick
    },
  },
})
