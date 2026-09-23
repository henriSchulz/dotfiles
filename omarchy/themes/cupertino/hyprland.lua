-- Cupertino: macOS window chrome for Hyprland.
--
-- Three things make a window read as "Apple": the corner is a squircle rather
-- than a circular arc (rounding_power > 2), the window floats on a wide, soft,
-- downward shadow, and the translucent surfaces above it are blurred with a
-- little vibrancy. Colors come from colors.toml.

local active_border_color = { colors = { "rgba(0071e3ff)", "rgba(5ac8faff)" }, angle = 45 }
local inactive_border_color = "rgba(d2d2d7cc)"

hl.config({
  general = {
    border_size = 2,

    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },

  decoration = {
    -- Squircle: rounding_power 4 approximates Apple's continuous corner.
    rounding = 14,
    rounding_power = 4,

    shadow = {
      enabled = true,
      range = 30,
      render_power = 3,
      offset = "0 8",
      color = "rgba(0000002e)",
      color_inactive = "rgba(00000014)",
    },

    blur = {
      enabled = true,
      size = 6,
      passes = 3,
      new_optimizations = true,
      noise = 0.012,
      contrast = 1.05,
      brightness = 1.0,
      vibrancy = 0.25,
      vibrancy_darkness = 0.0,
      popups = true,
      popups_ignorealpha = 0.2,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },
})

-- Vibrancy for the shell's own surfaces: the bar and every menu-style panel
-- run translucent in shell.*.toml, so give them something to blur.
hl.layer_rule({ match = { namespace = "omarchy-bar" }, blur = true, ignore_alpha = 0.1 })
-- Spotlight (namespace omarchy-menu) is deliberately left out: Henri wants it
-- to come up with no background blur.
hl.layer_rule({
  match = { namespace = "^(omarchy-image-selector|omarchy-emojis|omarchy-clipboard|omarchy-keyboard-panel)$" },
  blur = true,
  ignore_alpha = 0.1,
})
