-- Window mode: Omarchy tiling or macOS-style free-floating windows.
--
-- "tiling": Omarchy as usual (dwindle/scrolling per workspace).
-- "macos":  every new window floats. Apps reopen where they were last closed
--           (a second window of the same app cascades), a window dragged
--           against the left/right screen edge fills that half and against
--           the top edge fills the screen, SUPER+ALT+F zooms like the green
--           button, SUPER+M minimizes into omadock.
--
-- The mode is global and persists across reloads and restarts. Switch it with
--   hyprctl eval 'henri_wm.set("macos")'    -- or "tiling", henri_wm.toggle()
-- (the control center's Tiling tile does exactly that).
--
-- Windows floated by this mode carry TAG, so switching back re-tiles exactly
-- those and leaves Omarchy's own floating windows (pickers, dialogs) alone.
-- Tags survive `hyprctl reload`.
--
-- Never move/resize from `window.open_early`: the window isn't in the layout
-- yet and Hyprland 0.56 aborts. `window.open` is safe.

local M = {}
henri_wm = M

local MOD = henri_wm_mod or "SUPER"
local TAG = "macos-float"
local STATE_DIR = henri_wm_state_dir
  or ((os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/henri")
local MODE_FILE = STATE_DIR .. "/window-mode"
local GEOMETRY_FILE = STATE_DIR .. "/window-geometry"

-- A drag that ends this close to a screen edge snaps (logical px).
local EDGE = 3
-- Offset for a new window that would land exactly on a sibling.
local CASCADE = 28

-- ---------------------------------------------------------------- state

local function read_file(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read("a")
  file:close()
  return content
end

local function write_file(path, content)
  local file = io.open(path, "w")
  if not file then
    os.execute("mkdir -p '" .. STATE_DIR:gsub("'", "'\\''") .. "'")
    file = io.open(path, "w")
  end
  if not file then return end
  file:write(content)
  file:close()
end

M.mode = (read_file(MODE_FILE) or ""):match("^%s*macos") and "macos" or "tiling"

-- Last closed geometry per window class, relative to its monitor.
local geometry = {}
for line in (read_file(GEOMETRY_FILE) or ""):gmatch("[^\n]+") do
  local class, x, y, w, h = line:match("^(.-)\t(-?%d+)\t(-?%d+)\t(%d+)\t(%d+)$")
  if class then
    geometry[class] = { x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h) }
  end
end

local function save_geometry()
  local lines = {}
  for class, g in pairs(geometry) do
    lines[#lines + 1] = string.format("%s\t%d\t%d\t%d\t%d", class, g.x, g.y, g.w, g.h)
  end
  table.sort(lines)
  write_file(GEOMETRY_FILE, table.concat(lines, "\n") .. "\n")
end

-- ---------------------------------------------------------------- helpers

local function selector(w)
  return "address:" .. w.address
end

local function has_tag(w)
  if type(w.tags) ~= "table" then return false end
  for _, tag in ipairs(w.tags) do
    if tag == TAG or tag == TAG .. "*" then return true end
  end
  return false
end

local function box_of(w)
  return { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }
end

local function gap(key, side)
  local value = hl.get_config(key)
  if type(value) == "table" then return value[side] or 0 end
  return tonumber(value) or 0
end

-- Area a window may fill: the monitor minus the bar and outer gaps.
local function work_area(monitor)
  local reserved = monitor.reserved or {}
  local left = (reserved.left or 0) + gap("general.gaps_out", "left")
  local right = (reserved.right or 0) + gap("general.gaps_out", "right")
  local top = (reserved.top or 0) + gap("general.gaps_out", "top")
  local bottom = (reserved.bottom or 0) + gap("general.gaps_out", "bottom")
  return {
    x = monitor.x + left,
    y = monitor.y + top,
    w = math.floor(monitor.width / monitor.scale) - left - right,
    h = math.floor(monitor.height / monitor.scale) - top - bottom,
  }
end

local function clamp(box, area)
  local w = math.min(box.w, area.w)
  local h = math.min(box.h, area.h)
  return {
    x = math.max(area.x, math.min(box.x, area.x + area.w - w)),
    y = math.max(area.y, math.min(box.y, area.y + area.h - h)),
    w = w,
    h = h,
  }
end

local function apply(w, box)
  box = { x = math.floor(box.x), y = math.floor(box.y), w = math.floor(box.w), h = math.floor(box.h) }
  hl.dispatch(hl.dsp.window.resize({ x = box.w, y = box.h, window = selector(w) }))
  hl.dispatch(hl.dsp.window.move({ x = box.x, y = box.y, window = selector(w) }))
end

local function same_box(a, b, tolerance)
  tolerance = tolerance or 4
  return math.abs(a.x - b.x) <= tolerance and math.abs(a.y - b.y) <= tolerance
    and math.abs(a.w - b.w) <= tolerance and math.abs(a.h - b.h) <= tolerance
end

local function remember(w)
  if not w.floating or w.fullscreen ~= 0 or not w.monitor or (w.class or "") == "" then return end
  local monitor = w.monitor
  geometry[w.class] = { x = w.at.x - monitor.x, y = w.at.y - monitor.y, w = w.size.x, h = w.size.y }
end

-- Where a floating window of this class should go: its remembered spot,
-- cascaded past siblings already there, or centered at a comfortable size.
local function initial_box(w, area)
  local saved = geometry[w.class]
  if not saved then
    local width = math.min(w.size.x, math.floor(area.w * 0.7))
    local height = math.min(w.size.y, math.floor(area.h * 0.75))
    return { x = area.x + (area.w - width) / 2, y = area.y + (area.h - height) / 2, w = width, h = height }
  end

  local monitor = w.monitor
  local box = clamp({ x = monitor.x + saved.x, y = monitor.y + saved.y, w = saved.w, h = saved.h }, area)
  local siblings = hl.get_windows({ class = w.class })
  for _ = 1, 20 do
    local taken = false
    for _, other in ipairs(siblings) do
      if other.address ~= w.address and other.floating
        and math.abs(other.at.x - box.x) < CASCADE / 2 and math.abs(other.at.y - box.y) < CASCADE / 2 then
        taken = true
        break
      end
    end
    if not taken then break end
    box.x = box.x + CASCADE
    box.y = box.y + CASCADE
  end
  return clamp(box, area)
end

local function eligible(w)
  return w.mapped and not w.floating and w.fullscreen == 0 and not w.pinned
end

local function float(w)
  hl.dispatch(hl.dsp.window.float({ action = "enable", window = selector(w) }))
  hl.dispatch(hl.dsp.window.tag({ tag = "+" .. TAG, window = selector(w) }))
end

-- Position the last drag/snap/zoom left a window in, per address. A release
-- only counts as the end of a drag if the window moved since then, so a plain
-- click near the screen edge never snaps anything.
local settled = {}
-- Geometry before a zoom or snap, per address, for the way back.
local unzoomed = {}

local function settle(w)
  local fresh = hl.get_window(selector(w)) or w
  settled[w.address] = { x = fresh.at.x, y = fresh.at.y }
end

-- ---------------------------------------------------------------- mode

local function apply_mode_config()
  -- Magnetic edges between floating windows and the screen, like macOS.
  hl.config({ general = { snap = { enabled = M.mode == "macos" } } })
end

function M.set(mode)
  if mode ~= "macos" and mode ~= "tiling" then return end
  if mode == M.mode then return end
  M.mode = mode
  write_file(MODE_FILE, mode .. "\n")

  if mode == "macos" then
    -- Plan every box before floating anything: each float re-tiles the
    -- windows still in the layout.
    local planned = {}
    for _, w in ipairs(hl.get_windows()) do
      if eligible(w) and w.monitor then
        local area = work_area(w.monitor)
        -- Leave the window where the layout had it (clamped, since scrolling
        -- keeps columns off screen) unless the app has a remembered spot.
        planned[#planned + 1] = { w, geometry[w.class] and initial_box(w, area) or clamp(box_of(w), area) }
      end
    end
    for _, entry in ipairs(planned) do
      float(entry[1])
      apply(entry[1], entry[2])
      settle(entry[1])
    end
  else
    for _, w in ipairs(hl.get_windows()) do
      if has_tag(w) then
        remember(w)
        hl.dispatch(hl.dsp.window.tag({ tag = "-" .. TAG, window = selector(w) }))
        if w.floating then
          hl.dispatch(hl.dsp.window.float({ action = "disable", window = selector(w) }))
        end
      end
    end
    save_geometry()
    settled = {}
    unzoomed = {}
  end

  apply_mode_config()
end

function M.toggle()
  M.set(M.mode == "macos" and "tiling" or "macos")
end

apply_mode_config()

-- ---------------------------------------------------------------- zoom & snap

-- The green button: fill the work area, or go back to the previous size.
function M.zoom()
  local w = hl.get_active_window()
  if not w then return end
  if not w.floating or not w.monitor then
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized" }))
    return
  end

  local area = work_area(w.monitor)
  local previous = unzoomed[w.address]
  if previous and same_box(box_of(w), area) then
    unzoomed[w.address] = nil
    apply(w, previous)
    settle(w)
  else
    unzoomed[w.address] = box_of(w)
    apply(w, area)
    settle(w)
  end
end

local function snap_box(area, side)
  if side == "top" then return area end
  local half = math.floor((area.w - gap("general.gaps_in", "left")) / 2)
  if side == "left" then
    return { x = area.x, y = area.y, w = half, h = area.h }
  end
  return { x = area.x + area.w - half, y = area.y, w = half, h = area.h }
end

-- Snap a floating window to "left", "right" or "top" of its monitor.
function M.snap(side, w)
  w = w or hl.get_active_window()
  if not w or not w.floating or not w.monitor then return end
  local box = snap_box(work_area(w.monitor), side)
  -- Keep the size from before the first snap, so the next zoom (or a drag
  -- out and SUPER+ALT+F) can bring it back.
  if not unzoomed[w.address] then unzoomed[w.address] = box_of(w) end
  apply(w, box)
  settle(w)
end

-- Called on every left-button release. Snaps when a macOS-mode window was
-- just dragged and the pointer let go at a screen edge.
function M.drag_released()
  if M.mode ~= "macos" then return end
  local w = hl.get_active_window()
  if not w or not w.floating or not has_tag(w) or not w.monitor then return end

  local last = settled[w.address]
  local moved = not last or last.x ~= w.at.x or last.y ~= w.at.y
  settle(w)
  if not moved then return end

  local cursor = hl.get_cursor_pos()
  if not cursor then return end
  local monitor = w.monitor
  local left = monitor.x
  local right = monitor.x + monitor.width / monitor.scale
  local top = monitor.y

  if cursor.x <= left + EDGE then
    M.snap("left", w)
  elseif cursor.x >= right - 1 - EDGE then
    M.snap("right", w)
  elseif cursor.y <= top + EDGE then
    M.snap("top", w)
  end
end

-- ---------------------------------------------------------------- events

hl.on("window.open", function(w)
  if M.mode ~= "macos" or not eligible(w) or not w.monitor then return end
  local box = initial_box(w, work_area(w.monitor))
  float(w)
  apply(w, box)
  settle(w)
end)

hl.on("window.close", function(w)
  settled[w.address] = nil
  unzoomed[w.address] = nil
  if has_tag(w) then
    remember(w)
    save_geometry()
  end
end)

-- ---------------------------------------------------------------- bindings

hl.bind("mouse:272", function() M.drag_released() end,
  { release = true, ignore_mods = true, non_consuming = true, transparent = true })

hl.unbind(MOD .. " + ALT + F")
hl.bind(MOD .. " + ALT + F", function() M.zoom() end, { description = "Zoom window (macOS) / full width" })

hl.bind(MOD .. " + M", hl.dsp.exec_cmd("qs -p /usr/share/omarchy/shell ipc call omadock minimizeActive"),
  { description = "Minimize window to dock" })
