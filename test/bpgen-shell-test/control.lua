-- bpgen's web window (zzz-bpgen web.lua on fse-std's shells) in a real client: run_bpgen_shell.py drives it over the
-- web API (/api/game: this mod's "bpgen-shell-test" interface and bpgen's own), and the page through the web plugin.
script.on_init(function()
  local fp = remote.interfaces["freeplay"]
  if fp then
    if fp.set_skip_intro then remote.call("freeplay", "set_skip_intro", true) end
    if fp.set_disable_crashsite then remote.call("freeplay", "set_disable_crashsite", true) end
  end
end)

script.on_nth_tick(10, function(e)
  if storage.ready then return end
  local p = game.get_player(1)
  if not p then return end
  if p.controller_type == defines.controllers.cutscene then p.exit_cutscene() end
  p.force.research_all_technologies()
  storage.ready = e.tick
end)

local function ghosts(p)
  return #p.surface.find_entities_filtered({ type = { "entity-ghost", "tile-ghost" }, force = p.force })
end

remote.add_interface("bpgen-shell-test", {
  state = function()
    local p = game.get_player(1)
    local w = p.gui.screen.bpgen_window
    return { tick = game.tick, ready = storage.ready, lua_window = w ~= nil, lua_visible = w ~= nil and w.visible,
      ghosts = ghosts(p), opened_type = p.opened_gui_type, speed = game.speed, display_scale = p.display_scale,
      resolution = p.display_resolution, setting = p.mod_settings["bpgen-web-window"].value }
  end,
  -- another GUI over the window: the inventory ("controller") or none
  opened = function(what)
    local p = game.get_player(1)
    if what == "controller" then p.opened = defines.gui_type.controller else p.opened = nil end
    return p.opened_gui_type
  end,
})
