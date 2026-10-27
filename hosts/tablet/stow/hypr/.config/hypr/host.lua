-- Tablet only (Acer Switch Alpha 12). Loaded last by autostart.lua; stowed from
-- hosts/tablet, so the M1 never sees it.

-- Built-in panel: 2160x1440 on 250x170 mm (~219 ppi). At the shared 1.25
-- everything was too small. Integer 2 (1080x720 points) instead of the 1.6
-- tried first: the HD 520 lagged even moving the pointer, and a whole-number
-- scale spares it the fractional resampling. Matched by description: an
-- external monitor on the tablet keeps the shared rules from monitors.lua.
--
-- Turned with the device by hypr-autorotate (hosts/tablet/stow/autorotate), which calls
--   hyprctl eval 'henri_rotate.set(1)'     -- Hyprland transform 0..3
-- and keeps the last one in ~/.local/state/henri/rotation, read here so a reload keeps it.
-- Touchscreen and pen turn with the panel (same transform value, Hyprland's own matrices).
local ROTATION = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/henri/rotation"

local function saved_rotation()
  local f = io.open(ROTATION, "r")
  if not f then return 0 end
  local t = tonumber(f:read("l"))
  f:close()
  return (t and t >= 0 and t <= 3) and t or 0
end

local function panel(transform)
  hl.monitor({ output = "desc:Wistron Corporation 0x3316", mode = "preferred", position = "0x0", scale = 2, transform = transform })
end

henri_rotate = {}

function henri_rotate.set(t)
  t = tonumber(t)
  if not t or t < 0 or t > 3 then return end
  panel(t)
  hl.config({ input = { touchdevice = { transform = t }, tablet = { transform = t } } })
end

local start = saved_rotation()
panel(start)
hl.config({ input = { touchdevice = { transform = start }, tablet = { transform = start } } })

o.launch_on_start("hypr-autorotate")
