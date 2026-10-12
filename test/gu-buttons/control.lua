-- run_gu_buttons.py's driver: the top buttons (mod_gui's button flow) of pole-tidy, robo-grid and ai-crew, with and
-- without GUI Unifyer. Writes gu-buttons.txt (one "<phase> <name> style=<style> toggled=<bool>" per button), screenshots
-- gu-buttons-<phase>.png, and gu-buttons-ready.txt (resolution, scale, button order) for the runner to click by.
local mod_gui = require("mod-gui")
local WANT = { pole_tidy_auto = true, robo_grid_auto = true }  -- (what the runner clicks)
-- (a posted click the game never got: after 30 s the mod's own remote switches it on, logged as "fallback <name>",
-- so the style checks still run; the runner reports the missed click)
local FALLBACK = {
  pole_tidy_auto = function() remote.call("pole-tidy", "set_auto", true) end,
  robo_grid_auto = function() remote.call("robo-grid", "set", "auto", true) end,
}

local function log(t) helpers.write_file("gu-buttons.txt", t .. "\n", true) end
local function dump(phase, player)
  for _, b in pairs(mod_gui.get_button_flow(player).children) do
    log(phase .. " " .. b.name .. " style=" .. b.style.name .. " toggled=" .. tostring(b.toggled))
  end
end
local function shoot(phase, player)
  game.take_screenshot({ player = player, show_gui = true, path = "gu-buttons-" .. phase .. ".png",
    resolution = { 1280, 720 }, zoom = 1 })
end

script.on_event(defines.events.on_gui_click, function(e)
  if not e.element.valid then return end
  log("click " .. e.element.name)
  storage.clicked = storage.clicked or {}
  storage.clicked[e.element.name] = true
end)

script.on_event(defines.events.on_tick, function(e)
  local player = game.get_player(1)
  if not player then return end
  if e.tick == 60 then
    helpers.write_file("gu-buttons.txt", "gu " .. tostring(script.active_mods["GUI_Unifyer"]) .. "\n", false)
    dump("start", player)
    shoot("start", player)
    local names = {}
    for _, b in pairs(mod_gui.get_button_flow(player).children) do names[#names + 1] = b.name end
    local r = player.display_resolution
    helpers.write_file("gu-buttons-ready.txt",
      r.width .. " " .. r.height .. " " .. player.display_scale .. " " .. table.concat(names, " "))
  elseif e.tick > 60 and not storage.done then
    local all = true
    for name in pairs(WANT) do all = all and (storage.clicked or {})[name] == true end
    if not all and e.tick == 60 + 60 * 30 then
      for name in pairs(WANT) do
        if not (storage.clicked or {})[name] then
          FALLBACK[name]()
          log("fallback " .. name)
          storage.clicked = storage.clicked or {}
          storage.clicked[name] = true
        end
      end
      all = true
    end
    if all then storage.done = e.tick end
  elseif storage.done and e.tick == storage.done + 60 then
    dump("toggled", player)
    shoot("toggled", player)
    helpers.write_file("gu-buttons-done.txt", "done")
  end
end)
