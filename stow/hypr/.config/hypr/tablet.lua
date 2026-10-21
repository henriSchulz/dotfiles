-- Tablet mode: the Hyprland side of Velum's tablet mode (henri.tablet-v3 draws the home
-- indicator and its gestures, henri.bar-v3 the pulls from the top edge).
--
-- On:  one app per workspace, as on an iPad. A new tiled window that would share its
--      workspace moves to the first free one (and the view follows it); switching the mode on
--      spreads windows that share a workspace the same way, keeping the one last used there.
--      Floating windows (dialogs, pickers) stay with their app. No gaps around the app, and
--      the touchscreen is mapped to the built-in panel (eDP-*).
-- Off: the gaps come back; windows stay where they are.
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

local function tiled(w)
  return w.mapped and not w.floating and w.workspace ~= nil and not w.workspace.special
end

-- The lowest workspace id without windows, skipping ids already handed out.
local function free_workspace(taken)
  local used = {}
  for _, ws in ipairs(hl.get_workspaces()) do
    if ws.windows > 0 then used[ws.id] = true end
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

-- Every workspace keeps one tiled window; the others go to free workspaces.
local function spread()
  local taken = {}
  for _, ws in ipairs(hl.get_workspaces()) do
    if not ws.special and ws.windows > 1 then
      local list = tiled_on(ws)
      if #list > 1 then
        local keep = ws.last_window and ws.last_window.address or list[1].address
        for _, w in ipairs(list) do
          if w.address ~= keep then
            local id = free_workspace(taken)
            if not id then return end
            taken[id] = true
            hl.dispatch(hl.dsp.window.move({ workspace = tostring(id), follow = false, window = selector(w) }))
          end
        end
      end
    end
  end
end

hl.on("window.open", function(w)
  if not M.on or not tiled(w) or w.fullscreen ~= 0 then return end
  local others = 0
  for _, o in ipairs(tiled_on(w.workspace)) do
    if o.address ~= w.address then others = others + 1 end
  end
  if others == 0 then return end
  local id = free_workspace({})
  if id then
    hl.dispatch(hl.dsp.window.move({ workspace = tostring(id), follow = true, window = selector(w) }))
  end
end)

-- ---------------------------------------------------------------- config

-- The gaps as they were before the mode came on (from the config: Omarchy + looknfeel.lua).
local saved = nil

local function internal_output()
  for _, m in ipairs(hl.get_monitors()) do
    if m.name:match("^eDP") then return m.name end
  end
end

local function apply_config()
  local panel = internal_output()
  if panel then hl.config({ input = { touchdevice = { output = panel } } }) end
  if M.on then
    if not saved then
      saved = { gaps_in = hl.get_config("general.gaps_in"), gaps_out = hl.get_config("general.gaps_out") }
    end
    hl.config({ general = { gaps_in = 0, gaps_out = 0 } })
  elseif saved then
    hl.config({ general = { gaps_in = saved.gaps_in, gaps_out = saved.gaps_out } })
    saved = nil
  end
end

function M.set(on)
  on = on == true or on == "on" or on == "true"
  if on == M.on then return end
  M.on = on
  apply_config()
  if on then spread() end
end

function M.toggle() M.set(not M.on) end

-- On load (start or reload) the config has just set its own gaps: take them as the saved ones.
if M.on then apply_config() end
