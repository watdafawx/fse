-- fse-std upgraded under a save (run_upgrade.py): the save is made with fse-std from before themes and loaded with
-- this one. This mod works with both: phase 1 opens an old-style window and saves; phase 2 (after the load)
-- checks that the themes came up for the existing player.

script.on_init(function()
  local fp = remote.interfaces["freeplay"]
  if fp then
    if fp.set_skip_intro then remote.call("freeplay", "set_skip_intro", true) end
    if fp.set_disable_crashsite then remote.call("freeplay", "set_disable_crashsite", true) end
  end
end)

-- (phase 2 starts when the save comes back with another fse-std)
script.on_configuration_changed(function() storage.upgraded = game.tick end)

local window = require("__fse-std__/window")  -- (fse-std has it before themes too)

local result = {}
local function check(name, ok, detail) result[#result + 1] = { name = name, ok = ok and true or false, detail = detail } end

script.on_event(defines.events.on_tick, function(e)
  local p = game.get_player(1)
  if not p then return end
  if not storage.saved_at then
    if e.tick == 60 then
      window.create(p, { name = "upgrade_old_window", title = "Made before themes" })
    elseif e.tick == 90 then
      storage.saved_at = e.tick
      game.auto_save("upgrade")
      helpers.write_file("upgrade-done1.txt", "1", false)
    end
  elseif storage.upgraded and e.tick == storage.upgraded + 30 then
    local i = remote.interfaces["fse-std"]
    check("the theme service is there", i and i.theme ~= nil)
    check("the existing player got a probe", p.gui.screen.fstd_probe ~= nil)
    check("the old window is still there", p.gui.screen.upgrade_old_window ~= nil)
    local ok, err = pcall(function()
      local th = remote.call("fse-std", "theme", 1)
      assert(th.carrier == "vanilla", "theme " .. tostring(th.carrier))
      remote.call("fse-std", "open_theme", 1)
      remote.call("fse-std", "set_theme", 1, "gleba")
    end)
    check("theme window opens and a theme is picked", ok and p.gui.screen.fstd_theme_editor ~= nil, err)
    game.take_screenshot({ player = 1, path = "upgrade-after.png", show_gui = true,
      resolution = { p.display_resolution.width, p.display_resolution.height } })
  elseif storage.upgraded and e.tick == storage.upgraded + 40 then
    helpers.write_file("upgrade-result.json", helpers.table_to_json(result), false)
    helpers.write_file("upgrade-done2.txt", "1", false)
  end
end)
