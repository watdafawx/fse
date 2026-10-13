-- drives the fse hub in a real client: the Hub tab with the profiler, the Mods, Startup and Get mods tabs once
-- their data is in (screenshots), an install from the catalog (run_hub.py's local index), then a web page in the
-- panel over the game. Also: the button lit while the hub is open and unlit at once when it closes, the view rail
-- (docked) and the row of tabs inside (Docked off, Aquilo: hub-inside-aquilo.png), the settings panel
-- (hub-settings.png), the install result as a toast to the player who clicked
-- (no crash-site intro: it pauses the game and waits for the player to press Tab)
script.on_init(function()
  local fp = remote.interfaces["freeplay"]
  if fp then
    if fp.set_skip_intro then remote.call("freeplay", "set_skip_intro", true) end
    if fp.set_disable_crashsite then remote.call("freeplay", "set_disable_crashsite", true) end
  end
end)

local mod_gui = require("mod-gui")
local step, waited = "hub", 0
local function lit()
  local b = remote.call("fse-hub", "button_state", 1)
  return b and (b.toggled or b.style:find("_selected$") ~= nil)
end
local function tabs()
  local t = remote.call("fse-hub", "tabs", 1)
  return t and (t.where .. " " .. t.n) or "none"
end

local function shot(name)
  local p = game.get_player(1)
  game.take_screenshot({ player = 1, show_gui = true, path = name,
    resolution = { p.display_resolution.width, p.display_resolution.height }, zoom = 1 })
end

local function log(text) helpers.write_file("hub-result.txt", text .. "\n", true) end

-- the window and its rail inside the screen (pixels), at the scale it is drawn at
local function on_screen()
  local g = remote.call("fse-hub", "geometry", 1)
  if not g then return "no window" end
  local sc = g.ds * g.scale
  local ok = g.x >= 0 and g.y >= 0 and g.x + g.w * sc <= g.res_w + 1 and g.y + g.h * sc <= g.res_h + 1
    and (g.rail_x == nil or g.rail_x >= 0)
  return string.format("scale %s (game %s): on screen %s (window %d,%d %dx%d px, rail x %s, screen %dx%d)",
    g.scale, g.ds, tostring(ok), g.x, g.y, math.floor(g.w * sc), math.floor(g.h * sc), tostring(g.rail_x), g.res_w, g.res_h)
end

script.on_event(defines.events.on_tick, function(e)
  local p = game.get_player(1)
  if e.tick == 60 then
    helpers.write_file("hub-result.txt", "", false)
    remote.call("fse-hub", "open", 1, "hub")
    if native then native.call("profiler", "start") end
  elseif e.tick == 260 then
    log("mod-gui button: " .. tostring(mod_gui.get_button_flow(p).fse_hub_button ~= nil))
    log("hub open: " .. tostring(p.gui.screen.fse_hub ~= nil))
    log("update check: " .. tostring(remote.call("fse-hub", "loaded", "update")))
    log("update row: " .. tostring(remote.call("fse-hub", "update_row", 1)))
    log("button lit while open: " .. tostring(lit()))
    log("view tabs: " .. tabs())
    shot("hub-ingame.png")
  elseif e.tick == 285 then
    remote.call("fse-hub", "settings", 1)
    log("settings open: " .. tostring(p.gui.screen["fse_hub__menu"] ~= nil))
    shot("hub-settings.png")
  elseif e.tick == 320 then
    remote.call("fse-hub", "close", 1)
    log("closed: button unlit at once: " .. tostring(not lit()) .. ", rail gone: "
      .. tostring(remote.call("fse-hub", "tabs", 1) == nil and p.gui.screen["fse_hub__left"] == nil))
  elseif e.tick > 340 and (step == "hub" or step == "mods" or step == "startup" or step == "catalog") then
    if step == "hub" then step = "mods"; waited = 0; remote.call("fse-hub", "open", 1, "mods") return end
    waited = waited + 1
    local got = remote.call("fse-hub", "loaded", step)
    if got or waited > 1800 then
      log(step .. " data: " .. tostring(got) .. " after " .. waited .. " ticks")
      step = step .. "-shot"; waited = 0
    end
  elseif step == "mods-shot" or step == "startup-shot" or step == "catalog-shot" then
    waited = waited + 1
    local tab = step:sub(1, -6)
    if waited == 30 then
      shot("hub-" .. tab .. ".png")  -- (taken at the end of this tick: switch tabs on a later one)
    elseif waited == 32 then
      if tab == "mods" then
        step = "startup"; waited = 0; remote.call("fse-hub", "open", 1, "startup")
      elseif tab == "startup" then
        step = "catalog"; waited = 0; remote.call("fse-hub", "open", 1, "catalog")
      else
        step = "install"; waited = 0; remote.call("fse-hub", "install", "hub-demo", 1)
      end
    end
  elseif step == "install" then
    waited = waited + 1
    local got = remote.call("fse-hub", "loaded", "install")
    if got or waited > 1800 then
      log("install: " .. tostring(got) .. " after " .. waited .. " ticks")
      step = "install-shot"; waited = 0
    end
  elseif step == "install-shot" then
    waited = waited + 1
    if waited == 120 then
      log("catalog after install: " .. tostring(remote.call("fse-hub", "loaded", "catalog")))
      log("hub-needs install button: " .. tostring(remote.call("fse-hub", "button", 1, "hub-needs")))
      log("install told as a toast: " .. tostring(p.gui.screen["fstd_toasts_fse-hub"] ~= nil))
      shot("hub-catalog-installed.png")
    elseif waited == 122 then
      -- Docked off (the tabs inside), a light theme
      remote.call("fse-std", "set_theme", 1, "aquilo")
      remote.call("fse-hub", "docked", 1, false)
      remote.call("fse-hub", "open", 1, "mods")
      log("docked off: " .. tabs())
    elseif waited == 150 then
      shot("hub-inside-aquilo.png")
    elseif waited == 175 then
      remote.call("fse-hub", "docked", 1, true)
      remote.call("fse-std", "set_theme", 1, "vanilla")
      step = "scale"; waited = 0
    end
  elseif step == "scale" then
    -- fse-std's window scale 150 %: the hub (and its rail) drawn bigger, capped to fit, kept on the screen
    waited = waited + 1
    if waited == 1 then
      remote.call("fse-std", "set_window_scale", 1, 150)
      remote.call("fse-hub", "open", 1, "hub")
    elseif waited == 30 then
      log("window scale 150: " .. on_screen())
      shot("hub-scale150.png")
    elseif waited == 55 then
      remote.call("fse-hub", "settings", 1)
    elseif waited == 60 then
      log("settings at 150: " .. tostring(remote.call("fse-hub", "geometry", 1).menu))
      shot("hub-scale150-settings.png")
    elseif waited == 85 then
      remote.call("fse-hub", "settings", 1)  -- (closes them)
      remote.call("fse-std", "set_window_scale", 1, 100)
    elseif waited == 90 then
      log("window scale back to 100: " .. on_screen())
      step = "panel"; waited = 0
      log("web.open: " .. tostring(native.call("web", "open", "mods.html")))
    end
  elseif step == "panel" then
    waited = waited + 1
    if waited == 600 then helpers.write_file("hub-done.txt", "1", false) end
  end
end)
