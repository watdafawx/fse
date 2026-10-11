-- fse-std's themes in multiplayer (run_mp.py --mod theme-mp --expect "themes done"): once the client's player
-- joins, every theme feature runs at fixed ticks on every peer; the server (headless: no colours written) and the
-- client (a real window: colours written) must keep the same state, without a desync.

local events = require("__fse-std__/events")
local theme = require("__fse-std__/theme")
local window = require("__fse-std__/window")

local STEP = 120

local function steps(p)
  local i = p.index
  return {
    function()
      remote.call("fse-std", "set_theme", i, "vulcanus")
      remote.call("fse-std", "open_theme", i)
      local _, c = window.create(p, { name = "mp_panel", title = "MP panel", width = 420, height = 320, themed = true })
      local sec = theme.section(c, "Recipe")
      theme.add(sec, { type = "button", caption = "Plan" }, "ok")
      theme.progress(c, 0.4, { caption = "Research", text = "40%", auto = true })
      theme.graph(c, { 1, 3, 2, 5, 4 }, { width = 300, height = 50 })
      local f = p.gui.screen.mp_panel
      theme.glow(f)
      theme.tab_rail(f, { "A", "B" }, 1, "mp_rail")
      theme.dock(f, { size = { 200, 40 } })
      theme.toast(p, "hello", { seconds = 2 })
      local v = p.gui.screen.add({ type = "frame", name = "mp_vanilla", caption = "Plain" })
      v.add({ type = "button", caption = "A button" })
      theme.adopt(v)
    end,
    function()
      remote.call("fse-std", "set_color", i, "win", { r = 0.2, g = 0.3, b = 0.5, a = 1 })
      remote.call("fse-std", "set_vanilla_gui", i, true)
    end,
    function()
      local text = remote.call("fse-std", "export_theme", i)
      local name = remote.call("fse-std", "import_theme", i, text)
      remote.call("fse-std", "set_theme", i, name)
      theme.confirm(p, { name = "mp", text = "Sure?" })
    end,
    function()
      remote.call("fse-std", "set_theme", i, "glass")
      remote.call("fse-std", "set_vanilla_gui", i, false)
      remote.call("fse-std", "reset", i)
      storage.done = true
    end,
  }
end

local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

local function state()
  local p = game.get_player(1)
  local th = p and remote.call("fse-std", "theme", 1) or {}
  local probe = p and p.gui.screen.fstd_probe
  local r = storage.fstd_theme or {}
  return ("theme %s carrier %s game %s overlays %d probe %d screen %d redraw %d side %s custom %d%s"):format(
    tostring(th.name), tostring(th.carrier), tostring(th.vanilla_gui),
    count(storage.fstd_overlays and storage.fstd_overlays.list), probe and #probe.children or -1,
    p and #p.gui.screen.children or -1, count(r.redraw), p and tostring(p.game_view_settings.show_side_menu) or "?",
    count(r.custom), storage.done and " themes done" or "")
end

local handlers = {
  [defines.events.on_player_joined_game] = function(e)
    if e.player_index == 1 and not storage.joined then storage.joined = e.tick end
  end,
  [defines.events.on_tick] = function(e)
    local p = game.get_player(1)
    if storage.joined and p and p.connected then
      local k = (e.tick - storage.joined) / STEP
      local list = steps(p)
      if k >= 1 and k == math.floor(k) and list[k] then list[k]() end
    end
    if e.tick % 300 == 0 then
      local text = ("tick %d %s"):format(e.tick, state())
      helpers.write_file("mp-server.txt", text .. "\n", true, 0)
      for _, pl in pairs(game.connected_players) do
        helpers.write_file("mp-player-" .. pl.index .. ".txt", text .. "\n", true, pl.index)
      end
    end
  end,
}

events.register({ theme.handlers, window.handlers, handlers })
