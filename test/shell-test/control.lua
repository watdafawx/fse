-- The shell demo (fse-std's shell.lua): a web page over the game with two engine islands, a camera of the player's
-- surface and a row of item slots. The page's buttons pan and zoom the camera and spawn chests; the mod pushes its
-- state back to the page twice a second. /shell-demo opens it (it opens by itself at tick 30 in run_shell.py).
-- remote "shell-test": state, open, close, move(anchor), opened(gui), ping (driven by run_shell.py over /api/game).
script.on_init(function()
  local fp = remote.interfaces["freeplay"]
  if fp then
    if fp.set_skip_intro then remote.call("freeplay", "set_skip_intro", true) end
    if fp.set_disable_crashsite then remote.call("freeplay", "set_disable_crashsite", true) end
  end
end)

local events = require("__fse-std__/events")
local theme = require("__fse-std__/theme")
local shell = require("__fse-std__/shell")

local NAME = "demo"
local ITEMS = { "iron-plate", "copper-plate", "steel-plate", "electronic-circuit", "iron-gear-wheel", "wooden-chest" }

local function st()
  storage.demo = storage.demo or { pan = { 0, 0 }, zoom = 0.6, chests = {}, clicks = {}, messages = 0, pings = 0,
    acks = {}, ready = 0, closed = {}, island_sizes = {} }
  return storage.demo
end

local function cam_of(player)
  local f = shell.islands(player, NAME).cam
  return f and f.valid and f.cam or nil
end

local function point(player)
  local d = st()
  return { player.position.x + d.pan[1], player.position.y + d.pan[2] }
end

local function chests()
  local n = 0
  for _, c in pairs(st().chests) do if c.valid then n = n + 1 end end
  return n
end

local function push_state(player)
  local d = st()
  local p = point(player)
  shell.send(player, NAME, { state = { tick = game.tick, x = p[1], y = p[2], chests = chests(), zoom = d.zoom,
    clicked = d.clicks[#d.clicks] } })
end

local function open(player)
  local ok, why = shell.open(player, { name = NAME, page = "__shell-test__/web/demo.html", size = { 980, 600 },
    anchor = "center" })
  if not ok then
    player.print("shell demo: " .. tostring(why))
    return false
  end
  shell.island(player, NAME, "cam", function(f)
    f.add{ type = "camera", name = "cam", position = point(player), surface_index = player.surface.index,
      zoom = st().zoom }
  end)
  shell.island(player, NAME, "slots", function(f)
    local row = f.add{ type = "flow", direction = "horizontal" }
    row.style.horizontal_spacing = 0
    for i, item in ipairs(ITEMS) do
      row.add{ type = "sprite-button", name = "slot" .. i, style = "slot_button", sprite = "item/" .. item,
        number = i * 10, tooltip = item, tags = { shell_slot = item } }
    end
  end)
  return true
end

shell.on_island(function(player, name, id, frame, w, h)
  st().island_sizes[id] = { w, h }
  if id == "cam" and frame.cam then frame.cam.style.size = { w, h } end
end)

shell.on_ready(function(player, name)
  st().ready = st().ready + 1
  push_state(player)
end)

shell.on_close(function(player, name, why)
  local c = st().closed
  c[#c + 1] = why
end)

shell.on_message(function(player, name, m)
  local d = st()
  d.messages = d.messages + 1
  d.last = m
  local cmd = m.cmd
  if cmd == "pan" then
    d.pan[1] = d.pan[1] + (m.dx or 0)
  elseif cmd == "zoom" then
    d.zoom = d.zoom >= 1.2 and 0.3 or d.zoom * 2
  elseif cmd == "spawn" then
    local p = point(player)
    local pos = player.surface.find_non_colliding_position("wooden-chest", { p[1] + 3, p[2] }, 10, 1)
    if pos then
      local c = player.surface.create_entity{ name = "wooden-chest", position = pos, force = player.force }
      if c then d.chests[#d.chests + 1] = c end
    end
  elseif cmd == "rename" then
    d.label = m.text
  elseif cmd == "ping" then
    d.pings = d.pings + 1
    shell.send(player, NAME, { pong = m.n })
  elseif cmd == "ack" then
    d.acks[#d.acks + 1] = { n = m.n, rtt_ms = m.rtt_ms, tick = game.tick }
  elseif cmd == "theme" then
    d.theme_seen = m.name
  elseif cmd == "rects" then
    d.rects = m.rects
    d.page_dpr = m.dpr
    d.page_gu = m.gu
  end
  local cam = cam_of(player)
  if cam then
    cam.position = point(player)
    cam.zoom = d.zoom
  end
  push_state(player)
end)

local own = {
  [defines.events.on_gui_click] = function(e)
    local item = e.element.valid and e.element.tags.shell_slot
    if not item then return end
    local d = st()
    d.clicks[#d.clicks + 1] = item
    local player = game.get_player(e.player_index)
    shell.send(player, NAME, { log = "clicked " .. item .. " (an engine slot, through the page's hole)" })
    push_state(player)
  end,
  [defines.events.on_tick] = function(e)
    if e.tick == 30 then
      local p = game.get_player(1)
      if p then open(p) end
    end
    if e.tick % 30 == 0 then
      for _, p in pairs(game.connected_players) do
        if shell.is_open(p, NAME) then
          local cam = cam_of(p)
          if cam then cam.position = point(p) end
          push_state(p)
        end
      end
    end
  end,
}

events.register({ theme.handlers, shell.handlers, own })

commands.add_command("shell-demo", "Opens the fse shell demo (a web page with engine islands)", function(c)
  local p = c.player_index and game.get_player(c.player_index)
  if p then
    if shell.is_open(p, NAME) then shell.close(p, NAME) else open(p) end
  end
end)

local function frame_rect(f)
  if not (f and f.valid) then return nil end
  return { x = f.location.x, y = f.location.y, visible = f.visible, name = f.name }
end

remote.add_interface("shell-test", {
  state = function()
    local p = game.get_player(1)
    local d = st()
    local isl = shell.islands(p, NAME)
    local sh = storage.fstd_shells and storage.fstd_shells[1] and storage.fstd_shells[1][NAME]
    return { tick = game.tick, open = shell.is_open(p, NAME), available = shell.available(), ready = d.ready,
      messages = d.messages, pings = d.pings, acks = d.acks, clicks = d.clicks, chests = chests(), zoom = d.zoom,
      pan = d.pan, label = d.label, theme_seen = d.theme_seen, closed = d.closed, rects = d.rects, page_dpr = d.page_dpr, page_gu = d.page_gu,
      display_scale = p.display_scale, resolution = p.display_resolution,
      islands = { cam = frame_rect(isl.cam), slots = frame_rect(isl.slots) },
      sizes = sh and sh.sizes or {}, shell_rect = sh and sh.rect, opened = p.opened and (p.opened.name or "?") or nil,
      opened_type = p.opened_gui_type, suspended = sh and sh.suspended }
  end,
  open = function() return open(game.get_player(1)) end,
  close = function() shell.close(game.get_player(1), NAME) return true end,
  move = function(anchor) shell.move(game.get_player(1), NAME, { anchor = anchor }) return true end,
  -- another GUI over the shell: the inventory ("controller") or nothing
  opened = function(what)
    local p = game.get_player(1)
    if what == "controller" then p.opened = defines.gui_type.controller else p.opened = nil end
    return p.opened_gui_type
  end,
  send = function(data) return shell.send(game.get_player(1), NAME, data) end,
})
