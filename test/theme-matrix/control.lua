-- run_theme_matrix.py's driver: each of our themed windows opened under each fse-std theme (config.lua, written by
-- the runner) and screenshot to script-output/theme-matrix/<theme>-<window>.png. Results in theme-matrix.txt
-- ("ok ..." / "FAIL ..." / "SKIP ..." lines), then theme-matrix-done.txt.
local config = require("config")

local function log(t) helpers.write_file("theme-matrix.txt", t .. "\n", true) end

local function destroy(player, name)
  local el = player.gui.screen[name]
  if el and el.valid then el.destroy() end
end

-- a window: the mod's remote interface, how to open and close it, the screen element it makes
local WINDOWS = {
  srq = { iface = "srq", element = "urq_window",
    open = function(player) remote.call("srq", "show", player.index, "logistics-2") end,
    close = function(player) remote.call("srq", "hide", player.index) end },
  demo = { iface = "fse-std-demo", element = "fstd_demo",
    open = function(player) remote.call("fse-std-demo", "open", player.index) end,
    close = function(player) destroy(player, "fstd_demo") end },
  picker = { iface = "fse-std", element = "fstd_theme_editor",
    open = function(player) remote.call("fse-std", "open_theme", player.index) end,
    close = function(player)
      destroy(player, "fstd_theme_editor")
      pcall(player.set_shortcut_toggled, "fstd-theme", false)
    end },
  bpgen = { iface = "bpgen", element = "bpgen_window",
    open = function(player) remote.call("bpgen", "open_window", player.index) end,
    close = function(player) destroy(player, "bpgen_window") end },
}

local function setup(player)
  -- the research queue with something in it (as srq-guitest does)
  if remote.interfaces["srq"] then
    local force = player.force.name
    pcall(remote.call, "srq", "add", force, "goals", "logistic-science-pack")
    pcall(remote.call, "srq", "add", force, "goals", "fast-inserter")
    pcall(remote.call, "srq", "push", force, "steel-processing")
  end
end

-- the steps, one every few ticks: {tick offset, fn}
local function plan()
  local steps, t = {}, 0
  local function at(dt, fn) t = t + dt steps[#steps + 1] = { tick = t, fn = fn } end
  local known = {}
  for _, c in pairs(remote.call("fse-std", "themes")) do known[c.name] = true end
  for _, th in ipairs(config.themes) do
    if not known[th] then
      at(1, function() log("FAIL theme " .. th .. ": fse-std has no such theme") end)
    else
      at(5, function(player)
        remote.call("fse-std", "set_theme", player.index, th)
        local now = remote.call("fse-std", "theme", player.index).name
        log((now == th and "ok   " or "FAIL ") .. "theme " .. th .. " set (resolves to " .. tostring(now) .. ")")
      end)
      for _, wname in ipairs(config.windows) do
        local w = WINDOWS[wname]
        if not w then
          at(1, function() log("FAIL window " .. wname .. ": unknown") end)
        else
          at(10, function(player)
            if not remote.interfaces[w.iface] then
              log("SKIP " .. th .. " " .. wname .. ": no remote interface " .. w.iface)
              return
            end
            local ok, err = pcall(w.open, player)
            if not ok then log("FAIL " .. th .. " " .. wname .. " open: " .. tostring(err)) end
          end)
          at(10, function(player)
            if not remote.interfaces[w.iface] then return end
            local el = player.gui.screen[w.element]
            log(((el and el.valid and el.visible) and "ok   " or "FAIL ") .. th .. " " .. wname .. " open ("
              .. w.element .. ")")
            game.take_screenshot({ player = player, show_gui = true, resolution = config.resolution or { player.display_resolution.width, player.display_resolution.height }, zoom = 1,
              path = "theme-matrix/" .. th .. "-" .. wname .. ".png" })
            log("shot theme-matrix/" .. th .. "-" .. wname .. ".png")
          end)
          at(10, function(player)
            if not remote.interfaces[w.iface] then return end
            local ok, err = pcall(w.close, player)
            if not ok then log("FAIL " .. th .. " " .. wname .. " close: " .. tostring(err)) end
          end)
        end
      end
    end
  end
  at(30, function() helpers.write_file("theme-matrix-done.txt", "done") end)
  return steps
end

local steps, start
script.on_event(defines.events.on_tick, function(e)
  local player = game.get_player(1)
  if not player then return end
  if not start then
    if e.tick < 60 then return end
    start = e.tick
    helpers.write_file("theme-matrix.txt", "", false)
    setup(player)
    steps = plan()
  end
  for _, s in ipairs(steps) do
    if e.tick - start == s.tick then s.fn(player) end
  end
end)
