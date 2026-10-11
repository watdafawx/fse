-- fse-std's clickable components (run_theme_clicks.py): a fold and a search box, driven through the same handlers a
-- click and typing run (the game takes no posted mouse input in game, and the real cursor is the player's). Writes
-- clicks-result.json. (The hover fade needs a real hover: checked by eye.)

local events = require("__fse-std__/events")
local theme = require("__fse-std__/theme")
local window = require("__fse-std__/window")

local state = { searched = {} }

script.on_init(function()
  local fp = remote.interfaces["freeplay"]
  if fp then
    if fp.set_skip_intro then remote.call("freeplay", "set_skip_intro", true) end
    if fp.set_disable_crashsite then remote.call("freeplay", "set_disable_crashsite", true) end
  end
end)

local els = {}

theme.on_search(function(_, name, text) state.searched[#state.searched + 1] = name .. ":" .. text end)

local handlers = {
  [defines.events.on_tick] = function(e)
    local p = game.get_player(1)
    if not p then return end
    if e.tick == 30 then
      remote.call("fse-std", "set_theme", 1, "vulcanus")
      local f, content = window.create(p, { name = "clicks", title = "Clicks", width = 400, height = 360, themed = true })
      f.location = { 200, 200 }
      local body = theme.fold(content, "Fine-tune", true)
      theme.add(body, { type = "label", caption = "inside the fold" }, "text")
      theme.search(content, "find", "Search")
      els.fold = body.parent.children[1].children[1]
      els.body = body
      els.field = content.children[2].children[1]
      els.clear = content.children[2].children[2]
    elseif e.tick == 60 then
      local click = theme.handlers[defines.events.on_gui_click]
      local typed = theme.handlers[defines.events.on_gui_text_changed]
      local r = {}
      click({ element = els.fold, player_index = 1, tick = e.tick })
      r.closed = not els.body.visible
      click({ element = els.fold, player_index = 1, tick = e.tick })
      r.reopened = els.body.visible
      els.field.text = "iron"
      typed({ element = els.field, player_index = 1, tick = e.tick })
      click({ element = els.clear, player_index = 1, tick = e.tick })
      r.field_cleared = els.field.text == ""
      r.searched = state.searched
      helpers.write_file("clicks-result.json", helpers.table_to_json(r), false)
    end
  end,
}

events.register({ theme.handlers, window.handlers, handlers })
