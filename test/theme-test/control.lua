-- fse-std themes in a real client: a bpgen-like panel made with the theme library, shot in every theme; a live
-- colour edit read back from the engine; the game's own windows coloured. Writes theme-result.json and
-- theme-*.png to script-output, then theme-done.txt.

local events = require("__fse-std__/events")
local theme = require("__fse-std__/theme")
local themes = require("__fse-std__/themes")
local window = require("__fse-std__/window")

local THEMES = { "vanilla", "compact", "flat", "blueprint", "platform", "vulcanus", "gleba", "fulgora", "aquilo",
  "crt", "glass", "glassdark" }
local result = { shots = {}, checks = {} }

local function check(name, ok, detail)
  result.checks[#result.checks + 1] = { name = name, ok = ok and true or false, detail = detail }
end

local function shot(name)
  local p = game.get_player(1)
  game.take_screenshot({ player = 1, path = "theme-" .. name .. ".png", show_gui = true,
    resolution = { p.display_resolution.width, p.display_resolution.height }, zoom = 1, daytime = 0 })
  result.shots[#result.shots + 1] = name
end

-- the bpgen window's Line tab, made of themed components
local function panel(player)
  local _, content = window.create(player, { name = "theme_test_panel", title = "bpgen", width = 640, height = 470,
    themed = true, close = true })
  local top = content.add({ type = "flow", direction = "horizontal" })
  theme.tabs(top, { "Line", "Mall", "Base", "Extend", "Bus" }, 1, "tt_tab")
  local push = top.add({ type = "empty-widget" })
  push.style.horizontally_stretchable = true
  theme.add(top, { type = "checkbox", caption = "Only unlocked", state = true }, "check")
  local body = content.add({ type = "flow", direction = "horizontal" })
  local left = body.add({ type = "flow", direction = "vertical" })
  local sec = theme.section(left, "Recipe")
  local row = sec.add({ type = "flow", direction = "horizontal" })
  theme.add(theme.field(row, "Recipe"), { type = "choose-elem-button", elem_type = "recipe", recipe = "iron-gear-wheel" }, "slot")
  theme.add(theme.field(row, "Machine"), { type = "choose-elem-button", elem_type = "entity", entity = "assembling-machine-2" }, "slot")
  theme.add(theme.field(row, "Per minute"), { type = "textfield", text = "120" }, "field", { width = 70 })
  theme.add(theme.field(row, "Belt"), { type = "choose-elem-button", elem_type = "entity", entity = "transport-belt" }, "slot")
  local mods = theme.section(left, "Modules & beacons")
  local mrow = mods.add({ type = "flow", direction = "horizontal" })
  theme.add(theme.field(mrow, "Machine modules"), { type = "choose-elem-button", elem_type = "item", item = "speed-module" }, "slot")
  theme.add(theme.field(mrow, "Beacon"), { type = "choose-elem-button", elem_type = "entity" }, "slot")
  local go = left.add({ type = "flow", direction = "horizontal" })
  theme.add(go, { type = "button", caption = "Plan" }, "ok")
  theme.add(go, { type = "button", caption = "What's short?" }, "button")
  theme.add(go, { type = "button", caption = "Check my bus" }, "button")
  theme.add(left, { type = "label", caption = "Planned: 6 assemblers, 2 belts in, 1 out." }, "dim")
  local right = theme.add(body, { type = "frame", direction = "vertical" }, "deep", { width = 220, vertically_stretchable = true })
  theme.add(right, { type = "label", caption = "(the blueprint preview)" }, "dim")
  local tools = right.add({ type = "flow", direction = "horizontal" })
  theme.add(tools, { type = "button", caption = "-" }, "tool")
  theme.add(tools, { type = "button", caption = "+" }, "tool")
  theme.add(tools, { type = "button", caption = "Fit" }, "button", { minimal_width = 0 })
  theme.add(right, { type = "button", caption = "Blueprint to cursor" }, "ok")
end

-- every other component, in a second window
local function parts(player)
  local _, content = window.create(player, { name = "theme_test_parts", title = "Components", width = 560,
    height = 640, themed = true })
  local top = content.add({ type = "flow", direction = "horizontal" })
  theme.stat(top, "128/min", "Gears")
  theme.stat(top, "93%", "Uptime")
  local chips = top.add({ type = "flow", direction = "vertical" })
  theme.badge(chips, "3 short")
  theme.badge(chips, "unlocked")
  theme.add(top, { type = "button", caption = "Build it" }, "pulse")
  theme.progress(content, 0.3, { caption = "Research", text = "30%", auto = true })
  theme.progress(content, 0.85, { caption = "Belts", text = "85%" })
  theme.chart(content, { 3, 5, 8, 6, 9, 12, 10, 7, 11, 14, 13, 9, 6, 8, 12 }, { height = 50 })
  storage.graph = theme.graph(content, { 4, 6, 5, 9, 7, 11, 10, 14, 12, 15 }, { width = 480, height = 60 })
  theme.separator(content)
  theme.search(content, "test", "Search recipes")
  local row = content.add({ type = "flow", direction = "horizontal" })
  theme.list(row, { "Iron gear", "Copper cable", "Circuit", "Pipe" }, 2).style.height = 100
  local inputs = row.add({ type = "flow", direction = "vertical" })
  theme.add(inputs, { type = "checkbox", caption = "Use modules", state = true }, "check")
  theme.add(inputs, { type = "radiobutton", caption = "Belts", state = true }, "radio")
  theme.add(inputs, { type = "radiobutton", caption = "Bots", state = false }, "radio")
  theme.add(inputs, { type = "slider", minimum_value = 0, maximum_value = 10, value = 6 }, "slider")
  theme.add(inputs, { type = "drop-down", items = { "Yellow belt", "Red belt" }, selected_index = 1 }, "dropdown")
  local body = theme.fold(content, "Fine-tune", true)
  local sc = theme.add(body, { type = "scroll-pane" }, "scroll", { height = 60, horizontally_stretchable = true })
  for i = 1, 8 do theme.add(sc, { type = "label", caption = "Row " .. i }, "text") end
  local _, tabs = theme.tabbed(content, { "Input", "Output" })
  theme.add(tabs[1], { type = "label", caption = "Tab content" }, "text")
end

-- does fse-std's probe give every role's image sets (the engine paths live colours write through)?
local function role_paths(player)
  local probe = player.gui.screen.fstd_probe
  local bad = {}
  for role in pairs(themes.ROLES) do
    local el = probe["t_" .. role] or (probe["pane_t_" .. role] and probe["pane_t_" .. role]["t_" .. role])
    if el then
      for _, st in ipairs(themes.sets(role)) do
        if st.none then goto continue end
        local w = native.read(el, "guiElement.target.widget")
        local cur = type(w) == "table" and native.read(w, "style.parent")
        for _, f in ipairs(st[2]) do
          cur = type(cur) == "table" and cur.ptr and native.read(cur, f) or nil
        end
        local sp = type(cur) == "table" and cur.ptr and native.read(cur, "base.center.value.sprite")
        if not (type(sp) == "table" and sp.ptr) then
          sp = type(cur) == "table" and cur.ptr and native.read(cur, "base.top.value.sprite")  -- (no centre: a frame of edges)
        end
        if not (type(sp) == "table" and sp.ptr) then bad[#bad + 1] = role .. ":" .. table.concat(st[2], ".") end
        ::continue::
      end
    end
  end
  return bad
end

-- a frame in the game's own styles (what "colour the game's own windows" reaches)
local function vanilla_frame(player)
  local f = player.gui.screen.add({ type = "frame", name = "theme_test_vanilla", caption = "A game window", direction = "vertical" })
  local inner = f.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  inner.add({ type = "label", caption = "inside_shallow_frame" })
  inner.add({ type = "button", caption = "A game button" })
end

-- the engine's tint of a themed style's window sprite (through the probe fse-std keeps)
local function window_tint(player)
  local probe = player.gui.screen.fstd_probe
  if not probe then return nil, "no probe" end
  local w = native.read(probe.t_window, "guiElement.target.widget")
  if type(w) ~= "table" or not w.ptr then return nil, "no widget (hidden probe?)" end
  local gs = native.read(w, "style.parent.graphicalSet")
  if type(gs) ~= "table" or not gs.ptr then return nil, "no image set" end
  return native.read(gs, "base.center.value.sprite.tint")
end



local T0 = 60
local STEP = 6

local handlers = {
  [defines.events.on_tick] = function(e)
    local p = game.get_player(1)
    if not p then return end
    local t = e.tick - T0
    if t > 0 then  -- (each tick's time: which ones are slow)
      local st = native.tick_stats()
      result.slow = result.slow or {}
      if st.last_ms > 20 then result.slow[#result.slow + 1] = { t = t - 1, ms = st.last_ms } end
    end
    if t == 0 then
      panel(p)
      parts(p)
      vanilla_frame(p)
      -- a window built with the game's styles, then adopted
      local af = p.gui.screen.add({ type = "frame", name = "theme_test_adopt", caption = "Adopted", direction = "vertical" })
      local ain = af.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
      ain.add({ type = "label", caption = "A plain label" })
      local ab = ain.add({ type = "button", caption = "Wide button" })
      ab.style.width = 150
      ain.add({ type = "button", caption = "Confirm", style = "confirm_button" })
      theme.adopt(af)
      check("adopt themes a game-styled window", af.style.name:find("^fstd_") and ain.style.name:find("_inset$")
        and ab.style.name:find("_button$") and ab.style.minimal_width == 150,
        serpent.line({ af.style.name, ain.style.name, ab.style.name, ab.style.minimal_width }))
      theme.toast(p, "Blueprint copied", { seconds = 1 })
      check("toast shows", p.gui.screen["fstd_toasts_theme-test"] ~= nil)
      remote.call("fse-std", "open_theme", 1)
      local ed = p.gui.screen.fstd_theme_editor
      check("editor opens", ed ~= nil)
      check("probe made", p.gui.screen.fstd_probe ~= nil)
      -- the server's default theme: a player who never picked one follows it (99: no such player, no pick)
      local before = remote.call("fse-std", "theme", 99).name
      remote.call("fse-std", "set_default_theme", "gleba")
      local after = remote.call("fse-std", "theme", 99).name
      remote.call("fse-std", "set_default_theme", "vanilla")
      check("players without a pick follow the server's default", before == "vanilla" and after == "gleba",
        before .. " -> " .. after)
    elseif t == 1 then  -- (a tick after: window.create centres them first)
      local sc = p.display_scale
      p.gui.screen.theme_test_panel.location = { math.floor(20 * sc), math.floor(20 * sc) }
      p.gui.screen.theme_test_vanilla.location = { math.floor(20 * sc), math.floor(540 * sc) }
      p.gui.screen.theme_test_adopt.location = { math.floor(240 * sc), math.floor(540 * sc) }
      p.gui.screen.theme_test_parts.location = { math.floor(680 * sc), math.floor(20 * sc) }
      p.gui.screen.fstd_theme_editor.location = { math.floor(1260 * sc), math.floor(20 * sc) }
      result.scale = sc
      local pf = p.gui.screen.theme_test_panel
      theme.tab_rail(pf, { "Line", "Mall", "Base" }, 1, "tt_rail")
      theme.folder_tabs(p.gui.screen.theme_test_parts, { "Parts", "More" }, 1, "tt_folder", { along = -16 })
      local dock = theme.dock(pf, { size = { 260, 44 } })
      theme.add(dock, { type = "button", caption = "Blueprint" }, "ok", { minimal_width = 100 })
      theme.add(dock, { type = "button", caption = "Copy" }, "button", { minimal_width = 60 })
      theme.add(dock, { type = "button", caption = "Undo" }, "button", { minimal_width = 60 })
      theme.glow(pf)
      local rail = p.gui.screen.theme_test_panel__left
      check("tab rail sits left of the window", rail and rail.location.x < pf.location.x,
        serpent.line({ rail = rail and rail.location, win = pf.location }))
      pf.location = { pf.location.x + 30, pf.location.y + 10 }
      theme.follow(pf)
      check("attached frames follow the window", rail and rail.location.x < pf.location.x
        and p.gui.screen.theme_test_panel__bottom.location.y > pf.location.y,
        serpent.line({ rail = rail and rail.location, win = pf.location }))
      check("shortcut shows the theme window open", p.is_shortcut_toggled("fstd-theme"))
      local text = remote.call("fse-std", "export_theme", 1)
      local name = remote.call("fse-std", "import_theme", 1, text)
      check("a theme's text adds it back", type(name) == "string" and name:find("^custom_") ~= nil,
        tostring(text):sub(1, 40))
    elseif t > 0 and t <= #THEMES * STEP and t % STEP == 0 then
      local i = t / STEP
      remote.call("fse-std", "set_theme", 1, THEMES[i])
      local style = p.gui.screen.theme_test_panel.style.name
      check("panel restyled: " .. THEMES[i], style == "fstd_" .. THEMES[i] .. "_window", style)
    elseif t > STEP and t <= #THEMES * STEP + 2 and t % STEP == 2 then
      shot(THEMES[(t - 2) / STEP])
    elseif t == #THEMES * STEP + 10 then
      remote.call("fse-std", "set_theme", 1, "vulcanus")
    elseif t == #THEMES * STEP + 14 then
      local before = window_tint(p)
      remote.call("fse-std", "set_color", 1, "win", { r = 0.1, g = 0.3, b = 0.6, a = 1 })
      local after, err = window_tint(p)
      check("live tint written", type(after) == "table" and math.abs(after.b - 0.6) < 0.01,
        serpent.line({ before = before, after = after, err = err }))
      remote.call("fse-std", "set_color", 1, "caption", { r = 1, g = 1, b = 0.2, a = 1 })
    elseif t == #THEMES * STEP + 16 then
      shot("vulcanus-edited")
    elseif t == #THEMES * STEP + 20 then
      remote.call("fse-std", "reset", 1)
      local after = window_tint(p)
      check("reset gives the theme's colour back", type(after) == "table" and math.abs(after.b - 0x14 / 255) < 0.01,
        serpent.line(after))
      -- (flat game windows: a light theme reaches them too)
      local flat = settings.startup["fstd-flat-game"] and settings.startup["fstd-flat-game"].value
      result.flat = flat
      remote.call("fse-std", "set_theme", 1, flat and "aquilo" or "fulgora")
      remote.call("fse-std", "set_vanilla_gui", 1, true)
    elseif t == #THEMES * STEP + 120 then  -- (the game styles are written, the side menu drawn again)
      shot("fulgora-vanilla-gui")
      result.tick_stats = native.tick_stats()  -- (the slowest tick: the game styles' pass is in it)
    elseif t == #THEMES * STEP + 121 then
      local status = native.call("draw", "status")
      local st = status and helpers.json_to_table(status) or {}
      check("graph and glow drawn over the GUI", (st.shapes or 0) >= 5, status)
    elseif t == #THEMES * STEP + 122 then
      remote.call("fse-std", "set_vanilla_gui", 1, false)
    elseif t == #THEMES * STEP + 220 then
      shot("vanilla-gui-off")
      local bad = role_paths(p)
      check("live colours reach every role's image sets", #bad == 0, table.concat(bad, ", "))
      check("toast gone after its time", p.gui.screen["fstd_toasts_theme-test"] == nil)
      theme.confirm(p, { name = "unplace", title = "Undo", text = "Remove the 40 ghosts bpgen placed?", data = { n = 40 } })
      check("confirm opens as the opened GUI", p.opened and p.opened.name == "fstd_confirm_unplace")
    elseif t == #THEMES * STEP + 222 then
      shot("confirm")
      p.opened = nil  -- (as Esc)
    elseif t == #THEMES * STEP + 224 then
      check("Esc answers no", result.answer and result.answer.yes == false and result.answer.n == 40,
        serpent.line(result.answer))
      remote.call("fse-std", "set_vanilla_gui", 1, true)
    elseif t == #THEMES * STEP + 260 then  -- (an edit with the game's windows coloured: only its styles redone)
      remote.call("fse-std", "set_color", 1, "btn", { r = 0.5, g = 0.4, b = 0.9, a = 1 })
      result.edit_from = t
    elseif t == #THEMES * STEP + 299 then
      helpers.write_file("theme-result.json", helpers.table_to_json(result), false)
    elseif t == #THEMES * STEP + 300 then  -- (a save to load in a second run: colours written on the load)
      storage.saved_at = e.tick
      game.auto_save("theme-reload")
    elseif t == #THEMES * STEP + 301 then
      helpers.write_file("theme-done.txt", "1", false)
    elseif storage.saved_at and e.tick == storage.saved_at + 30 then
      shot("after-load")
      helpers.write_file("theme-done2.txt", "1", false)
    end
  end,
}

script.on_init(function()
  local fp = remote.interfaces["freeplay"]
  if fp then
    if fp.set_skip_intro then remote.call("freeplay", "set_skip_intro", true) end
    if fp.set_disable_crashsite then remote.call("freeplay", "set_disable_crashsite", true) end
  end
end)

theme.on_confirm(function(player, name, yes, data)
  result.answer = { name = name, yes = yes, n = data and data.n }
end)

events.register({ theme.handlers, window.handlers, handlers })
