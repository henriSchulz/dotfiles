-- Tablet mode: the Hyprland side of Velum's tablet mode (henri.tablet-v3 draws the home
-- indicator and its gestures, henri.bar-v3 the pulls from the top edge).
--
-- On:  one app per workspace, as on an iPad. The windows of one app (one class) share its
--      workspace, stacked: the layout is monocle, so each fills the screen, and the one on top is
--      in fullscreen (Hyprland has one fullscreen window per workspace; focusing another takes it
--      over, misc.on_focus_under_fullscreen = 1). A new tiled window goes to its app's workspace,
--      or, for an app not open yet, to the first free one (the view follows it); switching the mode
--      on sorts windows the same way, the app last used on a workspace keeping it. Floating windows
--      (dialogs, pickers) stay with their app. No gaps around the app, and the touchscreen is
--      mapped to the built-in panel (eDP-*).
-- Off: gaps and layout come back; windows stay where they are.
--
-- The state lives in Velum's settings, ~/.local/state/velum/settings.json ("tablet": true),
-- which every shell plugin already watches. Switch it with `tablet-mode on|off|toggle|status`
-- (~/.local/bin), which writes the key and then calls
--   hyprctl eval 'henri_tablet.set(true)'     -- or false
-- This file reads the key when it loads, so the mode survives a reload or restart.
-- Concept: ~/Documents/Notizen/Tablet-Modus Konzept.md

local M = {}
henri_tablet = M

local SETTINGS = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/velum/settings.json"

local function read_file(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read("a")
  file:close()
  return content
end

M.on = (read_file(SETTINGS) or ""):match('"tablet"%s*:%s*true') ~= nil

-- ---------------------------------------------------------------- windows

local function selector(w) return "address:" .. w.address end

-- Every app in fullscreen, as on an iPad; the ones made so carry TAG, so switching off only
-- brings those back.
local TAG = "tablet-fs"

local function has_tag(w)
  if type(w.tags) ~= "table" then return false end
  for _, tag in ipairs(w.tags) do
    if tag == TAG or tag == TAG .. "*" then return true end
  end
  return false
end

-- A floating window that is its process's only window is an app that floats on its own (1Password
-- does): in tablet mode it fills its screen like any app. Floating windows of a process that has
-- another window are its dialogs and pickers; they stay floating with it.
local function lone_app(w)
  if not w.floating or not w.mapped or not w.workspace or w.workspace.special or w.pinned then return false end
  for _, o in ipairs(hl.get_windows()) do
    if o.address ~= w.address and o.pid == w.pid and o.mapped then return false end
  end
  return true
end

local function settle_app(w)
  if lone_app(w) then
    hl.dispatch(hl.dsp.window.tag({ tag = "+" .. TAG .. "-float", window = "address:" .. w.address }))
    hl.dispatch(hl.dsp.window.float({ action = "disable", window = "address:" .. w.address }))
    return hl.get_window("address:" .. w.address) or w
  end
  return w
end

local function fill(w)
  if not w.mapped or w.floating or w.fullscreen ~= 0 or not w.workspace or w.workspace.special then return end
  hl.dispatch(hl.dsp.window.tag({ tag = "+" .. TAG, window = "address:" .. w.address }))
  hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", window = "address:" .. w.address }))
end

local function was_floating(w)
  if type(w.tags) ~= "table" then return false end
  for _, tag in ipairs(w.tags) do
    if tag == TAG .. "-float" or tag == TAG .. "-float*" then return true end
  end
  return false
end

local function unfill_all()
  for _, w in ipairs(hl.get_windows()) do
    if was_floating(w) then
      hl.dispatch(hl.dsp.window.tag({ tag = "-" .. TAG .. "-float", window = selector(w) }))
      if w.fullscreen ~= 0 then hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", window = selector(w) })) end
      hl.dispatch(hl.dsp.window.float({ action = "enable", window = selector(w) }))
    end
  end
  for _, w in ipairs(hl.get_windows()) do
    if has_tag(w) then
      if w.fullscreen ~= 0 then hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", window = selector(w) })) end
      hl.dispatch(hl.dsp.window.tag({ tag = "-" .. TAG, window = selector(w) }))
    end
  end
end

local function tiled(w)
  return w.mapped and not w.floating and w.workspace ~= nil and not w.workspace.special
end

-- The windows a fullscreen window covered keep their fade at 0 when the layout switch drops it, so
-- they stay invisible in the tiling. A fullscreen on and off on a workspace with more windows
-- recomputes the fade of all of them.
local function reveal_all()
  for _, ws in ipairs(hl.get_workspaces()) do
    if not ws.special and ws.windows > 1 then
      for _, w in ipairs(hl.get_workspace_windows(tostring(ws.id)) or {}) do
        if tiled(w) and w.fullscreen == 0 then
          hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", window = selector(w) }))
          hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", window = selector(w) }))
          break
        end
      end
    end
  end
end

-- The lowest workspace id without windows, skipping ids already handed out. An empty one that
-- lives on another monitor (its shown workspace) is not free: the app would land on that screen.
local function free_workspace(taken, monitor)
  local used = {}
  for _, ws in ipairs(hl.get_workspaces()) do
    local elsewhere = monitor and ws.monitor and ws.monitor.name ~= monitor.name
    if ws.windows > 0 or elsewhere then used[ws.id] = true end
  end
  for id = 1, 99 do
    if not used[id] and not taken[id] then return id end
  end
end

local function tiled_on(ws)
  local list = {}
  for _, w in ipairs(hl.get_workspace_windows(tostring(ws.id)) or {}) do
    if tiled(w) then list[#list + 1] = w end
  end
  return list
end

-- A workspace that does not exist yet comes up on the focused monitor: it is moved to the one the
-- window is on, and the view follows only then (so the window stays on its screen).
local function move_to(w, id, monitor, follow)
  hl.dispatch(hl.dsp.window.move({ workspace = tostring(id), follow = false, window = selector(w) }))
  if monitor then hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(id), monitor = monitor.name })) end
  if follow then hl.dispatch(hl.dsp.focus({ workspace = tostring(id) })) end
end

-- The app a window belongs to: its class (all terminals of one kind are one app, as on an iPad).
local function app_of(w) return w.class ~= "" and w.class or w.initial_class or "" end

-- The workspace of app `app` on `monitor` (from a window other than `skip`): where a new window of it goes.
-- When the app has windows on several workspaces, `here` (the one the new window came to) wins if it
-- holds one, else the one used last; taking the first in Hyprland's list sent a new terminal from a
-- terminal workspace to an older one elsewhere. Named workspaces (a rig's, "spare") are not the mode's.
local function app_workspace(app, monitor, skip, here)
  local best
  for _, o in ipairs(hl.get_windows()) do
    if o.address ~= skip and tiled(o) and app_of(o) == app and o.workspace.id > 0
       and (not monitor or not o.monitor or o.monitor.name == monitor.name) then
      if o.workspace.id == here then return here end
      if not best or (o.focus_history_id or 1e9) < (best.focus_history_id or 1e9) then best = o end
    end
  end
  return best and best.workspace.id
end

-- The window on top of a workspace: the one last used there, or else its first tiled window;
-- never `skip` (a window just moved away, still in the workspace's list for a moment).
local function top_of(ws, skip)
  local list = {}
  for _, w in ipairs(tiled_on(ws)) do if w.address ~= skip then list[#list + 1] = w end end
  if ws.last_window then
    for _, w in ipairs(list) do if w.address == ws.last_window.address then return w end end
  end
  return list[1]
end

-- Every app gets one workspace on its screen: its windows gather where the one used last is
-- (unless another app was used there later), the others go to free workspaces.
local function spread()
  local wins = {}
  for _, w in ipairs(hl.get_windows()) do if tiled(w) then wins[#wins + 1] = w end end
  table.sort(wins, function(a, b) return (a.focus_history_id or 1e9) < (b.focus_history_id or 1e9) end)
  local home, owner, taken = {}, {}, {}
  for _, w in ipairs(wins) do
    local monitor = w.monitor or w.workspace.monitor
    local key = app_of(w) .. "@" .. (monitor and monitor.name or "")
    if not home[key] then
      local here = w.workspace.id
      if owner[here] == nil then home[key] = here
      else
        home[key] = free_workspace(taken, monitor)
        if not home[key] then return end
      end
      owner[home[key]] = key
      taken[home[key]] = true
    end
    if home[key] ~= w.workspace.id then move_to(w, home[key], monitor, false) end
  end
end

-- Every workspace's top window in fullscreen (the others fill it through the monocle layout).
function M.fill_all()
  for _, w in ipairs(hl.get_windows()) do settle_app(w) end
  for _, ws in ipairs(hl.get_workspaces()) do
    if not ws.special then
      local top = top_of(ws)
      if top then fill(hl.get_window(selector(top)) or top) end
    end
  end
end

hl.on("window.open", function(w)
  if not M.on then return end
  w = settle_app(w)
  -- it may come in fullscreen already (it took it over from the app it opened over): sort it anyway
  if not tiled(w) then return end
  local monitor = w.monitor or w.workspace.monitor
  local app = app_of(w)
  local strangers = false
  for _, o in ipairs(tiled_on(w.workspace)) do
    if o.address ~= w.address and app_of(o) ~= app then strangers = true end
  end
  local came = w.workspace.id
  local target = app_workspace(app, monitor, w.address, came)
  if not target and strangers then target = free_workspace({}, monitor) end
  if target and target ~= came then
    move_to(w, target, monitor, true)
    -- Hyprland took the app the window came over out of fullscreen: give it back
    local left = hl.get_workspace(tostring(came))
    local top = left and top_of(left, w.address)
    if top then fill(top) end
  end
  fill(hl.get_window(selector(w)) or w)
end)

-- Hyprland 0.56's monocle hides the windows under the visible one with an alpha of 0 and skips that
-- while a window of the workspace is in fullscreen, and a focus on a workspace not shown yet does
-- not reach it at all; the fullscreen hand-over (on_focus_under_fullscreen) then left the focused
-- window invisible, and its hidden fade could outlive the mode. So a focus on a workspace with more
-- than one window takes it out of fullscreen, focuses it again now that its workspace is shown (the
-- monocle makes it the visible one) and fills it. Deferred: a focus on another workspace switches
-- there only after this event.
local healing = false

local function heal(address)
  local w = hl.get_window("address:" .. address)
  local active = hl.get_active_window()
  -- only the window still focused (a later focus has its own turn)
  if not M.on or not w or not active or active.address ~= address or not tiled(w) or #tiled_on(w.workspace) < 2 then return end
  healing = true
  for _, o in ipairs(tiled_on(w.workspace)) do
    if o.fullscreen ~= 0 then hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", window = selector(o) })) end
  end
  hl.dispatch(hl.dsp.focus({ window = "address:" .. address }))
  fill(hl.get_window("address:" .. address) or w)
  healing = false
end

hl.on("window.active", function(w)
  if not M.on or healing or not w or not w.address then return end
  local address = w.address
  hl.timer(function() heal(address) end, { timeout = 1, type = "oneshot" })
end)

-- ---------------------------------------------------------------- config

-- The gaps as they were before the mode came on (from the config: Omarchy + looknfeel.lua).
local saved = nil

local function internal_output()
  for _, m in ipairs(hl.get_monitors()) do
    if m.name:match("^eDP") then return m.name end
  end
end

-- Omarchy's per-workspace layouts (SUPER+L, kept as one file per workspace id) beat general.layout:
-- while the mode is on, every numbered workspace gets monocle under the same selector (a rule for
-- a selector already known is updated in place; a range rule would win for good, rules cannot be
-- taken back), and off, Omarchy's files are read again, the rest gets the layout of before.
local LAYOUTS = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/omarchy/workspace-layouts"
local MAX_WS = 99

local function layout_rules(on, before)
  for id = 1, MAX_WS do
    local file = LAYOUTS .. "/" .. id .. ".lua"
    if on then hl.workspace_rule({ workspace = tostring(id), layout = "monocle" })
    elseif read_file(file) then pcall(dofile, file)
    else hl.workspace_rule({ workspace = tostring(id), layout = before }) end
  end
end

-- seconds a resting pointer stays visible in tablet mode
local TABLET_CURSOR_IDLE = 3

local function apply_config()
  local panel = internal_output()
  if panel then hl.config({ input = { touchdevice = { output = panel } } }) end
  if M.on then
    if not saved then
      saved = { gaps_in = hl.get_config("general.gaps_in"), gaps_out = hl.get_config("general.gaps_out"),
                layout = hl.get_config("general.layout"), border = hl.get_config("general.border_size"),
                under_fs = hl.get_config("misc.on_focus_under_fullscreen"),
                aspect = hl.get_config("layout.single_window_aspect_ratio"),
                cursor_idle = hl.get_config("cursor.inactive_timeout") }
    end
    -- every app fills its screen: no gaps or borders, no square single window (Omarchy's toggle),
    -- an app's windows stacked (monocle), and the one focused takes over the fullscreen. Switching
    -- the layout takes every window out of fullscreen; the callers fill them again (refill).
    hl.config({ general = { gaps_in = 0, gaps_out = 0, border_size = 0, layout = "monocle" },
                misc = { on_focus_under_fullscreen = 1 },
                layout = { single_window_aspect_ratio = { 0, 0 } } })
    -- a finger hides the pointer already (cursor:hide_on_touch, on by default); the touchpad's
    -- pointer goes too once it rests, as on an iPad with a Magic Keyboard
    hl.config({ cursor = { hide_on_touch = true, inactive_timeout = TABLET_CURSOR_IDLE } })
    layout_rules(true)
  elseif saved then
    layout_rules(false, saved.layout or "dwindle")
    hl.config({ general = { gaps_in = saved.gaps_in, gaps_out = saved.gaps_out, border_size = saved.border,
                            layout = saved.layout or "dwindle" } })
    if saved.under_fs ~= nil then hl.config({ misc = { on_focus_under_fullscreen = saved.under_fs } }) end
    if saved.aspect then hl.config({ layout = { single_window_aspect_ratio = saved.aspect } }) end
    hl.config({ cursor = { inactive_timeout = saved.cursor_idle or 0 } })
    saved = nil
  end
end

-- The window mode "macos" (window-mode.lua) floats every window; on an iPad every app fills the
-- screen. It steps aside to "tiling" while tablet mode is on and comes back when it goes off; which
-- one it was is kept in a file, so a restart in tablet mode still knows.
local WM_WAS = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/henri/tablet-window-mode"

local function write_file(path, content)
  local file = io.open(path, "w")
  if not file then return end
  file:write(content)
  file:close()
end

local function wm_tile()
  if henri_wm and henri_wm.mode == "macos" then
    write_file(WM_WAS, "macos\n")
    henri_wm.set("tiling")
  end
end

local function wm_restore()
  local was = (read_file(WM_WAS) or ""):match("macos")
  os.remove(WM_WAS)
  if was and henri_wm then henri_wm.set("macos") end
end

-- The layout switch lands after this call returns and takes the windows out of fullscreen then:
-- fill them now and once more when it has.
local function refill()
  M.fill_all()
  hl.timer(function() if M.on then M.fill_all() end end, { timeout = 100, type = "oneshot" })
end

function M.set(on)
  on = on == true or on == "on" or on == "true"
  if on == M.on then
    -- already on: tidy up anyway (windows that came while it was off, or shared a workspace)
    if on then spread(); M.fill_all() end
    return
  end
  M.on = on
  if on then
    apply_config()
    wm_tile()
    spread()
    refill()
  else
    -- out of fullscreen before the layout changes: the layout switch drops it on its own, and the
    -- windows it covered then stayed invisible
    unfill_all()
    apply_config()
    wm_restore()
    -- once the layout switch has landed (after this call returns)
    hl.timer(function() if not M.on then reveal_all() end end, { timeout = 100, type = "oneshot" })
  end
end

function M.toggle() M.set(not M.on) end

-- On load (start or reload) take the config's own values as the saved ones — once all of it has
-- loaded: Omarchy's toggles (single-window aspect ratio) come after this file.
local fresh = true
local function apply_fresh()
  if not fresh then return end
  fresh = false
  if M.on then
    saved = nil
    apply_config()
    refill()
  end
end
hl.on("config.reloaded", apply_fresh)
hl.on("hyprland.start", apply_fresh)
