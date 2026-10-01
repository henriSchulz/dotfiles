-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

local omarchy_gdk_scale = 2
local omarchy_monitor_scale = "auto"

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Spare virtual output (hypr-spare-output, started from autostart.lua): keeps
-- Hyprland alive when the only monitor is unplugged — without any output,
-- 0.56.2 crashes on the next window capture. It sits far away so the pointer
-- cannot reach it, runs at 30 Hz and only redraws on change, and owns the
-- workspace "spare" so it never takes a numbered one. The real monitor is
-- pinned to 0x0: "auto" would place it right next to the spare one. The name
-- starts with HEADLESS because plugins (henri.dock) skip such outputs when
-- they pick their screen.
hl.monitor({ output = "DP-1", mode = "preferred", position = "0x0", scale = omarchy_monitor_scale })
-- Same size as the real monitor, so windows keep their layout when they land
-- here — and ipadcast (~/Projects/m1-power/ipadcast) mirrors this output to
-- the iPad while the real monitor is unplugged, which makes it the display.
hl.monitor({ output = "HEADLESS-SPARE", mode = "1920x1080@30", position = "20000x20000", scale = 1 })
hl.workspace_rule({ workspace = "name:spare", monitor = "HEADLESS-SPARE", default = true, persistent = true })

-- Configure a specific monitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })
