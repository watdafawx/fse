-- Shells: a mod window that is a web page over the game (the fse loader's web plugin: a WebView2 window owned by the
-- game window), with holes ("engine islands") where the game's own GUI shows through. The page owns the layout,
-- look, scale and animation; under each hole sits a bare screen frame of this mod holding engine widgets only (a
-- camera, slots, choose-elem buttons, a minimap), moved to the hole's place whenever the page moves it.
--
--   local shell = require("__fse-std__/shell")
--   events.register({ shell.handlers, ... })        -- (it polls the page's messages every tick while a shell is open)
--   if shell.available() then
--     shell.open(player, { name = "planner", page = "__my-mod__/web/planner.html", size = { 900, 560 } })
--     local frame = shell.island(player, "planner", "preview", function(f)
--       f.add{ type = "camera", position = player.position, style = "fstd_shell_camera" }   -- (any engine widgets)
--     end)
--   end
--   shell.on_message(function(player, name, data) ... end)    -- page's fse.send(data), on the game thread
--   shell.send(player, "planner", { count = 3 })               -- page's fse.on(fn(data))
--   shell.on_ready(function(player, name) ... end)              -- page loaded (again after a live reload): send state
--   shell.on_close(function(player, name, why) ... end)         -- why: "esc", "page", "close", "mod", "no WebView2: ..."
--   shell.on_island(function(player, name, id, frame, w, h) ... end)  -- an island got another size (GUI units)
--
-- open(player, opts): name, page ("__mod__/path.html": a file of an unzipped mod; "shell/demo.html": fse's web
-- folder), size = {w, h} in GUI units at 100 % (default 640 x 420), anchor ("center", "top", "bottom", "left",
-- "right", "top-left", "top-right", "bottom-left", "bottom-right", "fill"), offset = {x, y} and margin (GUI units),
-- or rect = {x, y, w, h} in pixels; scale (the shell's own, 1 = 100 %; default fse-std's Window size setting), on top
-- of the game's GUI scale; radius (GUI units: rounded corners); esc (default true); visible (default true); yield
-- (with esc = false, a companion kept open while the player plays: true hides it while another GUI is the player's
-- opened one - the inventory, a machine, a picker - and brings it back when that closes; default false).
-- Opening a shell that is open updates it (another page loads; the same page stays).
--   shell.close(player, name), shell.show(player, name, visible), shell.move(player, name, opts) (opts as open's),
--   shell.is_open(player, name), shell.islands(player, name) -> { id = frame }, shell.status() (native, for tests),
--   shell.remove_island(player, name, id) (its frame destroyed), shell.rect(player, name) -> {x, y, w, h} pixels
--
-- Units: the page's CSS pixel is one GUI unit at the shell's scale (its WebView2 zoom is set so); one game GUI unit
-- is var(--fse-gu) CSS px (1 / the shell's scale), so size an island for engine widgets with calc(40 * var(--fse-gu))
-- per slot. Islands are frames with style "invisible_frame": their content stretches to them (stretchable styles), or
-- on_island sizes it.
--
-- The game's own GUI and a shell: the shell is a window above the game, so a game window opening under it would be
-- hidden. A shell is the player's opened GUI (like fse-std windows: Esc and E close it while the game has the
-- keyboard; Esc in the page closes it too). When another GUI replaces it (an entity clicked through a gap, the
-- inventory opened by script), the shell and its islands hide until that GUI closes, then come back. Game tooltips
-- of island widgets show inside the hole only (the page draws over the rest): give island widgets short tooltips,
-- or show richer ones in the page. A companion (esc = false) stays over the game's windows unless it asks to yield.
--
-- Single player only: the page runs on this computer alone, so what it sends would change the game on one peer
-- (a desync). available() is false in multiplayer (as fse-hub); shells then don't open, and saved ones stay closed.
-- Shells are this peer's windows: a save keeps which are open (storage), and they open again on the first tick after
-- loading.

local theme = require("__fse-std__/theme")
local themes = require("__fse-std__/themes")

local M = {}
local OWNER = script.mod_name
local OWNER_JSON = '{"owner": ' .. string.format("%q", OWNER) .. "}"
local listeners = { message = {}, ready = {}, close = {}, island = {} }
local resumed = false   -- (this Lua state opened the saved shells again: after a load the windows are gone)

function M.on_message(fn) listeners.message[#listeners.message + 1] = fn end
function M.on_ready(fn) listeners.ready[#listeners.ready + 1] = fn end
function M.on_close(fn) listeners.close[#listeners.close + 1] = fn end
function M.on_island(fn) listeners.island[#listeners.island + 1] = fn end

local function fire(list, ...)
  for _, fn in ipairs(list) do fn(...) end
end

local has
--- the fse loader is there with a web plugin that has shells
function M.native()
  if has == nil then
    has = false
    if type(native) == "table" and type(native.plugins) == "function" and type(native.call) == "function" then
      local ok, list = pcall(native.plugins)
      if ok and type(list) == "table" and type(list.web) == "table" then
        for _, f in pairs(list.web) do
          if f == "shell_open" then has = true end
        end
      end
    end
  end
  return has
end

--- shells work here: the loader on this computer, single player, not the main menu's simulation
function M.available()
  return M.native() and not game.is_multiplayer() and not script.level.is_simulation
end

local function call(fn, t)
  local out, err = native.call("web", fn, helpers.table_to_json(t))
  if out == nil then log("[" .. OWNER .. "] shell: " .. fn .. ": " .. tostring(err)) end
  return out, err
end

local function all() storage.fstd_shells = storage.fstd_shells or {} return storage.fstd_shells end
local function list_of(index)
  local a = all()
  a[index] = a[index] or {}
  return a[index]
end
local function get(player, name)
  local a = storage.fstd_shells
  return a and a[player.index] and a[player.index][name]
end

local function round(x) return math.floor(x + 0.5) end

-- the shell's scale on top of the game's: its own, else fse-std's Window size setting
local function own_scale(player, opts) return opts.scale or theme.setting_scale(player) end
local function px_scale(player, opts) return player.display_scale * own_scale(player, opts) end

local H = { left = 0, ["top-left"] = 0, ["bottom-left"] = 0, right = 1, ["top-right"] = 1, ["bottom-right"] = 1 }
local V = { top = 0, ["top-left"] = 0, ["top-right"] = 0, bottom = 1, ["bottom-left"] = 1, ["bottom-right"] = 1 }

--- where opts puts a shell: {x, y, w, h} in pixels of the game window
local function rect_for(player, opts)
  local r = opts.rect
  if r then return { r[1] or r.x, r[2] or r.y, r[3] or r.w or r.width, r[4] or r.h or r.height } end
  local f = px_scale(player, opts)
  local res = player.display_resolution
  local m = round((opts.margin or 0) * f)
  local a = opts.anchor or "center"
  if a == "fill" then return { m, m, math.max(64, res.width - 2 * m), math.max(64, res.height - 2 * m) } end
  local size = opts.size or { 640, 420 }
  local w = math.min(round((size[1] or size.width) * f), res.width)
  local h = math.min(round((size[2] or size.height) * f), res.height)
  local off = opts.offset or { 0, 0 }
  local ox, oy = round((off[1] or off.x or 0) * f), round((off[2] or off.y or 0) * f)
  local hx, vy = H[a], V[a]
  local x = hx == 0 and m or hx == 1 and res.width - w - m or round((res.width - w) / 2)
  local y = vy == 0 and m or vy == 1 and res.height - h - m or round((res.height - h) / 2)
  return { x + ox, y + oy, w, h }
end

--- the player's fse-std theme as the page's CSS variables get it
local function theme_payload(player)
  local t = theme.of(player)
  local th = themes.by_name[t.carrier] or themes.by_name.vanilla
  local colors = {}
  for _, tok in ipairs(themes.TOKENS) do
    local c = themes.color(th, t.edits, tok[1])
    if c then colors[tok[1]] = { c.r, c.g, c.b, c.a or 1 } end
  end
  return { name = t.name, carrier = t.carrier, shape = th.shape, pad = th.pad, gap = th.gap, mono = th.mono == true,
    light = th.light == true, glass = th.glass == true, colors = colors }
end

local function native_open(player, name, s)
  local th = theme_payload(player)
  local f = px_scale(player, s.opts)
  call("shell_open", { owner = OWNER, name = name, page = s.page, rect = s.rect, scale = f,
    gu = 1 / own_scale(player, s.opts), esc = s.opts.esc ~= false, radius = round((s.opts.radius or 0) * f),
    theme = th, bg = th.colors.win, visible = s.visible and not s.suspended })
end

-- the island frames at the holes' places (pixels from the page), hidden when the shell or the hole is
local function place_islands(player, name, s)
  local ds = player.display_scale
  local on = s.shown and s.visible and not s.suspended
  for id, f in pairs(s.islands) do
    if f.valid then
      local r = s.layout and s.layout[id]
      if on and r and r[3] > 0 and r[4] > 0 then
        f.location = { r[1], r[2] }
        local w, h = math.max(1, round(r[3] / ds)), math.max(1, round(r[4] / ds))
        local old = s.sizes[id]
        if not old or old[1] ~= w or old[2] ~= h then
          f.style.width, f.style.height = w, h
          s.sizes[id] = { w, h }
          fire(listeners.island, player, name, id, f, w, h)
        end
        if not f.visible then
          f.visible = true
          f.bring_to_front()
        end
      elseif f.visible then
        f.visible = false
      end
    end
  end
end

local function anchor_of(player, name, s)
  if s.anchor and s.anchor.valid then return s.anchor end
  local key = "fstd_shell_" .. OWNER .. "_" .. name
  local el = player.gui.screen[key]
  if el then el.destroy() end
  -- (an empty, see-through frame: the player's opened GUI, so Esc and E close the shell as they close game windows)
  s.anchor = player.gui.screen.add{ type = "frame", name = key, style = "invisible_frame",
    tags = { fstd_shell = name } }
  s.anchor.style.size = 0
  s.anchor.location = { 0, 0 }
  return s.anchor
end

local function take_opened(player, name, s)
  if s.opts.esc == false then return end
  if player.opened_gui_type == defines.gui_type.none then
    player.opened = anchor_of(player, name, s)
    s.has_opened = true
  end
end

--- opens (or updates) a shell; false and why when shells don't work here
function M.open(player, opts)
  if not M.available() then return false, "shells need the fse loader's web plugin, in single player" end
  local name = assert(opts.name, "shell.open: name")
  local list = list_of(player.index)
  local s = list[name] or { islands = {}, sizes = {} }
  list[name] = s
  s.page = assert(opts.page or s.page, "shell.open: page")
  s.opts = { size = opts.size, anchor = opts.anchor, offset = opts.offset, margin = opts.margin, rect = opts.rect,
    scale = opts.scale, radius = opts.radius, esc = opts.esc, yield = opts.yield }
  if not s.moved then s.rect = rect_for(player, s.opts) end
  s.visible = opts.visible ~= false
  s.suspended = false
  resumed = true  -- (its window is made now: nothing saved to open again in this session)
  take_opened(player, name, s)
  native_open(player, name, s)
  return true
end

function M.is_open(player, name) return get(player, name) ~= nil end
function M.islands(player, name) local s = get(player, name) return s and s.islands or {} end
--- where the shell is now, {x, y, w, h} in pixels of the game window (moved or resized in the page too), or nil
function M.rect(player, name)
  local s = get(player, name)
  return s and s.rect and { s.rect[1], s.rect[2], s.rect[3], s.rect[4] } or nil
end

--- closes a shell: its window, its islands; on_close hears why ("mod" when not given)
function M.close(player, name, why)
  local list = storage.fstd_shells and storage.fstd_shells[player.index]
  local s = list and list[name]
  if not s then return end
  list[name] = nil
  for _, f in pairs(s.islands) do
    if f.valid then f.destroy() end
  end
  if s.anchor and s.anchor.valid then
    if player.opened == s.anchor then player.opened = nil end
    s.anchor.destroy()
  end
  if M.native() then call("shell_close", { owner = OWNER, name = name }) end
  fire(listeners.close, player, name, why or "mod")
end

function M.show(player, name, visible)
  local s = get(player, name)
  if not s then return end
  s.visible = visible ~= false
  if s.visible then take_opened(player, name, s) end
  call("shell_set", { owner = OWNER, name = name, visible = s.visible and not s.suspended })
  place_islands(player, name, s)
end

--- moves / resizes a shell (opts as open's: size, anchor, offset, margin, rect, scale, radius)
function M.move(player, name, opts)
  local s = get(player, name)
  if not s then return end
  for _, k in pairs({ "size", "anchor", "offset", "margin", "rect", "scale", "radius" }) do
    if opts[k] ~= nil then s.opts[k] = opts[k] end
  end
  if opts.rect == nil and (opts.anchor or opts.size or opts.offset) then s.opts.rect = nil end
  s.moved = false
  s.rect = rect_for(player, s.opts)
  local f = px_scale(player, s.opts)
  call("shell_set", { owner = OWNER, name = name, rect = s.rect, scale = f, radius = round((s.opts.radius or 0) * f) })
  call("shell_send", { owner = OWNER, name = name, env = { t = "scale", gu = 1 / own_scale(player, s.opts) } })
end

--- data (any JSON-able value) to the page: its fse.on handlers get it
function M.send(player, name, data)
  if not get(player, name) then return false end
  return call("shell_send", { owner = OWNER, name = name, env = { t = "msg", data = data } }) ~= nil
end

--- a shell's island: a bare screen frame (style invisible_frame) kept under the page's <engine-island id=id>;
--- `build(frame)` fills it the first time
function M.island(player, name, id, build)
  local s = assert(get(player, name), "shell.island: no shell " .. tostring(name))
  local f = s.islands[id]
  if f and f.valid then return f end
  local key = "fstd_island_" .. OWNER .. "_" .. name .. "_" .. id
  local old = player.gui.screen[key]
  if old then old.destroy() end
  f = player.gui.screen.add{ type = "frame", name = key, style = "invisible_frame", direction = "vertical",
    tags = { fstd_shell = name, fstd_island = id } }
  f.style.padding = 0
  f.visible = false
  s.islands[id] = f
  s.sizes[id] = nil
  if build then build(f) end
  place_islands(player, name, s)
  return f
end

--- an island no longer needed: its frame destroyed (shell.island makes it again)
function M.remove_island(player, name, id)
  local s = get(player, name)
  local f = s and s.islands[id]
  if not s then return end
  if f and f.valid then f.destroy() end
  s.islands[id], s.sizes[id] = nil, nil
end

--- the web plugin's view of every shell (windows, regions, holes, keyboard, lag): for tests and debugging
function M.status()
  if not M.native() then return nil end
  local out = native.call("web", "shell_status", "")
  return out and helpers.json_to_table(out)
end

-- ---- events ------------------------------------------------------------------------------------------------------

local function suspend(player, name, s, on)
  s.suspended = on
  call("shell_set", { owner = OWNER, name = name, visible = s.visible and not on })
  if not on then take_opened(player, name, s) end
  place_islands(player, name, s)
end

-- the player a shell event is for (single player: the one who has a shell of that name)
local function owner_of(name)
  local lp = native.local_player and native.local_player()
  local a = storage.fstd_shells or {}
  if lp and a[lp] and a[lp][name] then return game.get_player(lp), a[lp][name] end
  for index, list in pairs(a) do
    if list[name] then return game.get_player(index), list[name] end
  end
end

local function dispatch(ev)
  local player, s = owner_of(ev.shell)
  if not (player and s) then return end
  local name = ev.shell
  if ev.type == "layout" then
    if ev.rect then
      if s.rect and (ev.rect[1] ~= s.rect[1] or ev.rect[2] ~= s.rect[2] or ev.rect[3] ~= s.rect[3] or ev.rect[4] ~= s.rect[4]) then
        s.moved = true  -- (dragged in the page: kept, not anchored again)
      end
      s.rect = ev.rect
    end
    s.layout = ev.islands or {}
    s.shown = ev.shown
    place_islands(player, name, s)
  elseif ev.type == "message" then
    fire(listeners.message, player, name, ev.data)
  elseif ev.type == "ready" then
    call("shell_send", { owner = OWNER, name = name, env = { t = "theme", theme = theme_payload(player) } })
    fire(listeners.ready, player, name)
  elseif ev.type == "visible" then
    s.visible = ev.visible
    place_islands(player, name, s)
  elseif ev.type == "closed" then
    M.close(player, name, ev.why)
  end
end

local function tick()
  local a = storage.fstd_shells
  if not a or next(a) == nil or not M.available() then return end
  if not resumed then
    resumed = true
    for index, list in pairs(a) do
      local player = game.get_player(index)
      for name, s in pairs(list) do
        if player then native_open(player, name, s) end
      end
    end
  end
  -- (the shell is no longer the opened GUI: Esc or E closed it, or another GUI took its place, by the player or a
  -- script (which raises no event): then it hides until that one closes)
  for index, list in pairs(a) do
    local player = game.get_player(index)
    for name, s in pairs(list) do
      local kind = player and player.opened_gui_type
      if not player then
      elseif s.has_opened and not (kind == defines.gui_type.custom and player.opened == s.anchor) then
        s.has_opened = false
        -- (opened_gui_type, not opened: the inventory and other game screens read as opened == nil)
        if kind ~= defines.gui_type.none then suspend(player, name, s, true) else M.close(player, name, "esc") end
      elseif s.suspended and kind == defines.gui_type.none then
        suspend(player, name, s, false)
      elseif s.opts.yield and not s.has_opened and not s.suspended and kind ~= defines.gui_type.none then
        suspend(player, name, s, true)  -- (a companion making way for another GUI: back when it closes)
      end
    end
  end
  local text = native.call("web", "shell_take", OWNER_JSON)
  if text and text ~= "[]" then
    for _, ev in ipairs(helpers.json_to_table(text) or {}) do dispatch(ev) end
  end
end

local function each_shell(index, fn)
  local list = storage.fstd_shells and storage.fstd_shells[index]
  local player = game.get_player(index)
  if not (list and player) then return end
  for name, s in pairs(list) do fn(player, name, s) end
end

local function rescale(e)
  if not M.available() then return end
  each_shell(e.player_index, function(player, name, s)
    if s.moved then  -- (kept where the player dragged it, inside the window)
      local res = player.display_resolution
      s.rect[1] = math.max(0, math.min(s.rect[1], res.width - 64))
      s.rect[2] = math.max(0, math.min(s.rect[2], res.height - 64))
    else
      s.rect = rect_for(player, s.opts)
    end
    local f = px_scale(player, s.opts)
    call("shell_set", { owner = OWNER, name = name, rect = s.rect, scale = f, radius = round((s.opts.radius or 0) * f) })
    call("shell_send", { owner = OWNER, name = name, env = { t = "scale", gu = 1 / own_scale(player, s.opts) } })
  end)
end

M.handlers = {
  [defines.events.on_tick] = tick,
  ["fstd-theme-changed"] = function(e)
    if not M.available() then return end
    each_shell(e.player_index, function(player, name)
      call("shell_send", { owner = OWNER, name = name, env = { t = "theme", theme = theme_payload(player) } })
    end)
  end,
  ["fstd-scale-changed"] = rescale,
  [defines.events.on_player_display_scale_changed] = rescale,
  [defines.events.on_player_display_resolution_changed] = rescale,
}

return M
