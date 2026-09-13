-- Cupertino Dark: macOS window chrome for Hyprland.
--
-- Three things make a window read as "Apple": the corner is a squircle rather
-- than a circular arc (rounding_power > 2), the window floats on a wide, soft,
-- downward shadow, and the translucent surfaces above it are blurred with a
-- little vibrancy. Colors come from colors.toml.

local active_border_color = { colors = { "rgba(0a84ffff)", "rgba(64d2ffff)" }, angle = 45 }
local inactive_border_color = "rgba(48484aaa)"

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
      color = "rgba(00000066)",
      color_inactive = "rgba(00000033)",
    },

    blur = {
      enabled = true,
      size = 6,
      passes = 3,
      new_optimizations = true,
      noise = 0.012,
      contrast = 1.05,
      brightness = 0.92,
      vibrancy = 0.17,
      vibrancy_darkness = 0.35,
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
hl.layer_rule({
  match = { namespace = "^(omarchy-menu|omarchy-image-selector|omarchy-emojis|omarchy-clipboard|omarchy-keyboard-panel)$" },
  blur = true,
  ignore_alpha = 0.1,
})
