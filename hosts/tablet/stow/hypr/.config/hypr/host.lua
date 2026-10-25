-- Tablet only (Acer Switch Alpha 12). Loaded last by autostart.lua; stowed from
-- hosts/tablet, so the M1 never sees it.

-- Built-in panel: 2160x1440 on 250x170 mm (~219 ppi). At the shared 1.25
-- everything was too small. Integer 2 (1080x720 points) instead of the 1.6
-- tried first: the HD 520 lagged even moving the pointer, and a whole-number
-- scale spares it the fractional resampling. Matched by description: an
-- external monitor on the tablet keeps the shared rules from monitors.lua.
hl.monitor({ output = "desc:Wistron Corporation 0x3316", mode = "preferred", position = "0x0", scale = 2 })
