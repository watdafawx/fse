-- fse-std's theme service: each player's theme and colour edits (storage), the "fse-std" remote interface the
-- theme library asks, the theme window (/fse-theme), and live colours through tint.lua.
--
-- storage.fstd_theme = {
--   players = { [index] = { theme = name, edits = { [name] = { token = colour } }, vanilla_gui = bool } },
--   custom  = { [name] = { title, base = shipped theme, colors = { token = colour } } },   -- saved themes
-- }

local themes = require("themes")
local theme = require("theme")
local tint = require("tint")
local window = require("window")
local input = require("input")
local overlay = require("overlay")

local M = {}
local NAME = "fstd_theme_editor"
local applied = {}   -- player_index -> live colours written on this peer since the load (not game state)
local selected = {}  -- player_index -> the token being edited (the open window's: momentary)
local shared = {}    -- player_index -> the text "Copy as text" made (shown in the share field: momentary)

local function root()
  storage.fstd_theme = storage.fstd_theme or { players = {}, custom = {} }
  return storage.fstd_theme
end

local function pstate(index)
  local r = root()
  local p = r.players[index]
  if not p then
    p = { theme = "vanilla", edits = {}, vanilla_gui = false }
    r.players[index] = p
  end
  return p
end

local function base_of(name)
  if themes.by_name[name] then return name end
  local c = root().custom[name]
  return c and themes.by_name[c.base] and c.base or "vanilla"
end

--- a player's theme as the library wants it: {name, carrier, edits (saved theme's colours + the player's)}
function M.resolve(index)
  local p = pstate(index)
  if not (themes.by_name[p.theme] or root().custom[p.theme]) then p.theme = "vanilla" end
  local edits = {}
  local c = root().custom[p.theme]
  if c then for k, v in pairs(c.colors) do edits[k] = v end end
  for k, v in pairs(p.edits[p.theme] or {}) do edits[k] = v end
  return { name = p.theme, carrier = base_of(p.theme), edits = edits, vanilla_gui = p.vanilla_gui }
end

-- the themes to pick from: shipped, then saved ones
local function choices()
  local list = {}
  for _, t in ipairs(themes.list) do list[#list + 1] = { name = t.name, title = t.title } end
  local names = {}
  for name in pairs(root().custom) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do list[#list + 1] = { name = name, title = root().custom[name].title } end
  return list
end

local function current_color(player, token)
  local th = M.resolve(player.index)
  return themes.color(themes.by_name[th.carrier], th.edits, token)
end

-- ---------------------------------------------------------------------------------------------------------------
-- live colours

local game_dirty = {}  -- player_index -> the game's own styles need writing (this peer's own: not game state)

local function live(player, only)
  local th = M.resolve(player.index)
  local ok = tint.apply(player, th, only)
  if ok then applied[player.index] = true end
  if th.vanilla_gui then  -- (written by tick(): many styles, once things settle; one colour: just its styles)
    local d = game_dirty[player.index]
    game_dirty[player.index] = (only and (d == nil or d == only)) and only or true
  end
  return ok
end

local function probe(player)
  local th = M.resolve(player.index)
  local r = root()
  r.probes = r.probes or {}
  r.probes[player.index] = tint.probe(player, th.carrier, th.vanilla_gui)  -- (kept for a load: see on_load)
  applied[player.index] = nil
end

-- The game draws its side menu (research, menu buttons, the map's frame) once and keeps the picture: after the
-- game's own styles get new colours it is drawn again by hiding it for a tick. Scheduled a little after the next
-- colour pass, the same on every peer (game_view_settings are game state).
local REDRAW = { "show_side_menu", "show_minimap", "show_research_info" }

local function schedule_redraw(player)
  local r = root()
  r.redraw = r.redraw or {}
  r.redraw[player.index] = { at = (math.floor((game.tick + 1) / 30) + 1) * 30 + 35 }
end

local function redraw_step(tick)
  local r = root()
  for index, job in pairs(r.redraw or {}) do
    local player = game.get_player(index)
    if not (player and player.valid) then
      r.redraw[index] = nil
    elseif not job.hidden and tick >= job.at then
      local v = player.game_view_settings
      job.hidden = {}
      for _, k in ipairs(REDRAW) do
        if v[k] then job.hidden[#job.hidden + 1] = k; v[k] = false end
      end
    elseif job.hidden then
      local v = player.game_view_settings
      for _, k in ipairs(job.hidden) do v[k] = true end
      r.redraw[index] = nil
    end
  end
end

-- turns "colour the game's own windows" on or off: off gives the game's colours back before the probe forgets
-- those styles, on makes the probe hold them (both peers do the probe; only the player's own writes)
local function set_vanilla_gui(player, on)
  local p = pstate(player.index)
  if p.vanilla_gui == on then return end
  p.vanilla_gui = on
  if not on then tint.apply_game(player, M.resolve(player.index)) end
  probe(player)
  live(player)
  schedule_redraw(player)
end

-- ---------------------------------------------------------------------------------------------------------------
-- the theme window

local function hex(c)
  return string.format("#%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5),
    math.floor(c.b * 255 + 0.5))
end

local function parse_hex(s)
  s = (s or ""):gsub("^#", "")
  if not s:match("^%x%x%x%x%x%x$") then return nil end
  local n = tonumber(s, 16)
  return { r = math.floor(n / 65536) / 255, g = math.floor(n / 256) % 256 / 255, b = n % 256 / 255 }
end

local function token_title(token)
  for _, t in ipairs(themes.TOKENS) do if t[1] == token then return t[2] end end
  return token
end

-- a colour swatch: a full progress bar, whose colour Lua can set at any time
local function swatch(parent, col, width, name, height)
  local bar = parent.add({ type = "progressbar", value = 1, name = name })
  bar.style.color = { r = col.r, g = col.g, b = col.b, a = 1 }
  bar.style.width = width
  bar.style.bar_width = height or 18
  return bar
end

-- a theme's look in five colours (window, panels, buttons, accent, main action), its edits over it
local STRIP = { "win", "section", "btn", "btn_on", "ok" }
local function theme_colors(player, name)
  local c = root().custom[name]
  local base = themes.by_name[name] or themes.by_name[c and c.base or "vanilla"] or themes.by_name.vanilla
  local edits = {}
  if c then for k, v in pairs(c.colors) do edits[k] = v end end
  for k, v in pairs(pstate(player.index).edits[name] or {}) do edits[k] = v end
  return base, edits
end

local function editor(player) return player.gui.screen[NAME] end

local function fill(player)
  local frame = editor(player)
  if not frame then return end
  local content = frame.children[2]
  content.clear()
  content = theme.add(content, { type = "scroll-pane", horizontal_scroll_policy = "never" }, "scroll",
    { horizontally_stretchable = true, vertically_stretchable = true, padding = 0 })
  local th = M.resolve(player.index)
  local t = themes.by_name[th.carrier]
  local p = pstate(player.index)

  -- the themes, each with a strip of its colours
  local gallery = theme.section(content, "Theme")
  local cells = gallery.add({ type = "table", column_count = 3 })
  cells.style.horizontal_spacing = 4
  cells.style.vertical_spacing = 6
  for _, c in ipairs(choices()) do
    local cell = cells.add({ type = "flow", direction = "vertical" })
    cell.style.vertical_spacing = 2
    theme.add(cell, { type = "button", caption = c.title, toggled = c.name == th.name,
      tags = { fstd_ed = "pick", theme = c.name } }, "tab", { width = 118 })
    local strip = cell.add({ type = "flow", direction = "horizontal" })
    strip.style.horizontal_spacing = 1
    local base, edits = theme_colors(player, c.name)
    for _, tok in ipairs(STRIP) do swatch(strip, themes.color(base, edits, tok), 23, nil, 6) end
  end

  local sec = theme.section(content, "Colours", "Pick one, then set it below. Kept per theme, for you.")
  local grid = sec.add({ type = "table", column_count = 4 })
  grid.style.horizontal_spacing = 6
  grid.style.vertical_spacing = 4
  local sel = selected[player.index] or "win"
  for _, tok in ipairs(themes.TOKENS) do
    if tok.edit then
      swatch(grid, themes.color(t, th.edits, tok[1]), 24)
      theme.add(grid, { type = "button", caption = tok[2], toggled = tok[1] == sel,
        tags = { fstd_ed = "token", token = tok[1] },
        tooltip = th.edits[tok[1]] and "Edited" or "The theme's own colour" }, "tab", { minimal_width = 110 })
    end
  end

  local col = themes.color(t, th.edits, sel)
  local ed = theme.section(content, token_title(sel))
  local row = ed.add({ type = "flow", direction = "horizontal" })
  row.style.vertical_align = "center"
  swatch(row, col, 64)
  theme.add(row, { type = "textfield", text = hex(col), tags = { fstd_ed = "hex" },
    tooltip = "#rrggbb, then Enter" }, "field", { width = 90 })
  for _, ch in ipairs({ { "r", "Red" }, { "g", "Green" }, { "b", "Blue" }, { "a", "See-through" } }) do
    if ch[1] ~= "a" or t.glass then
      local f = ed.add({ type = "flow", direction = "horizontal" })
      f.style.vertical_align = "center"
      theme.add(f, { type = "label", caption = ch[2] }, "dim", { width = 80 })
      local v = ch[1] == "a" and math.floor((1 - col.a) * 255 + 0.5) or math.floor(col[ch[1]] * 255 + 0.5)
      theme.add(f, { type = "slider", minimum_value = 0, maximum_value = 255, value = v, value_step = 1,
        discrete_values = true, tags = { fstd_ed = "channel", ch = ch[1] } }, "slider", { horizontally_stretchable = true })
      theme.add(f, { type = "label", caption = tostring(v) }, "dim", { width = 30 })
    end
  end

  local foot = content.add({ type = "flow", direction = "horizontal" })
  theme.add(foot, { type = "button", caption = "Reset to default colours", tags = { fstd_ed = "reset" },
    tooltip = "This theme's colours as it ships" }, "button")
  local save = content.add({ type = "flow", direction = "horizontal" })
  theme.add(save, { type = "textfield", text = "", tags = { fstd_ed = "save_name" }, tooltip = "A name for it" },
    "field", { width = 160 })
  theme.add(save, { type = "button", caption = "Save as new theme", tags = { fstd_ed = "save" } }, "ok")

  local share = theme.section(content, "Share", "A theme as a line of text: send it, paste one to add it")
  local srow = share.add({ type = "flow", direction = "horizontal" })
  theme.add(srow, { type = "button", caption = "Copy as text", tags = { fstd_ed = "export" },
    tooltip = "This theme with your colours, as text (to the clipboard with the FSE loader)" }, "button")
  theme.add(srow, { type = "textfield", text = shared[player.index] or "", tags = { fstd_ed = "share_text" },
    tooltip = "Paste a theme's text here" }, "field", { width = 180 })
  theme.add(srow, { type = "button", caption = "Add", tags = { fstd_ed = "import" } }, "ok", { minimal_width = 60 })

  local live_ok = tint.available()
  theme.add(content, { type = "checkbox", state = p.vanilla_gui, enabled = live_ok, tags = { fstd_ed = "vanilla" },
    caption = "Colour the game's own windows too",
    tooltip = live_ok and "Inventory, crafting, every window: they get darker or change hue to match (they can't get "
      .. "lighter than the game draws them)" or "Needs the FSE loader" }, "check")
  theme.add(content, { type = "label", caption = live_ok
    and "Live colours: on (FSE). Every change shows at once."
    or "Without the FSE loader: switching themes and text colours work at once; other colours need FSE." },
    "dim", { single_line = false })
end

function M.open(player)
  if editor(player) then editor(player).destroy() end
  player.set_shortcut_toggled("fstd-theme", true)
  window.create(player, { name = NAME, title = "Theme", width = 480, height = 700, themed = true,
    min_width = 360, min_height = 400 })
  fill(player)
end

-- ---------------------------------------------------------------------------------------------------------------
-- changes

local function changed(player, opts)
  if opts.carrier then probe(player) end
  if opts.restyle then script.raise_event("fstd-theme-changed", { player_index = player.index }) end
  live(player, opts.only)
  if pstate(player.index).vanilla_gui then schedule_redraw(player) end
  if opts.refill then fill(player) end
end

function M.set_theme(player, name)
  if not (themes.by_name[name] or root().custom[name]) then return end
  local before = M.resolve(player.index).carrier
  pstate(player.index).theme = name
  changed(player, { carrier = M.resolve(player.index).carrier ~= before, restyle = true, refill = true })
end

local function is_ink(token)
  if token == "btn_on" then return true end  -- (progress bars take it as LuaStyle.color)
  for _, r in pairs(themes.ROLES) do
    if r.ink == token or r.sel_ink == token then return true end
  end
  return false
end

function M.set_color(player, token, col, refill)
  local p = pstate(player.index)
  p.edits[p.theme] = p.edits[p.theme] or {}
  p.edits[p.theme][token] = { r = col.r, g = col.g, b = col.b, a = col.a or 1 }
  changed(player, { restyle = is_ink(token), only = token, refill = refill })
end

function M.reset(player)
  pstate(player.index).edits[pstate(player.index).theme] = nil
  changed(player, { restyle = true, refill = true })
end

-- a theme as text: "fstd1" and the encoded JSON of {title, base, colors}
function M.export(player)
  local th = M.resolve(player.index)
  local c = root().custom[th.name]
  local t = { title = c and c.title or themes.by_name[th.name].title, base = th.carrier, colors = th.edits }
  return "fstd1" .. helpers.encode_string(helpers.table_to_json(t))
end

-- a theme's text back to a saved theme: its name, or nil and why not
function M.import(player, text)
  text = (text or ""):gsub("%s", "")
  if text:sub(1, 5) ~= "fstd1" then return nil, "That isn't a theme's text" end
  local json = helpers.decode_string(text:sub(6))
  local t = json and helpers.json_to_table(json)
  if type(t) ~= "table" or not themes.by_name[t.base] then return nil, "That theme's text is damaged" end
  local colors = {}
  for _, tok in ipairs(themes.TOKENS) do
    local v = type(t.colors) == "table" and t.colors[tok[1]]
    if type(v) == "table" then
      local function n(x) return type(x) == "number" and math.max(0, math.min(1, x)) or 1 end
      colors[tok[1]] = { r = n(v.r), g = n(v.g), b = n(v.b), a = n(v.a) }
    end
  end
  local r = root()
  local i = 1
  while r.custom["custom_" .. i] do i = i + 1 end
  local name = "custom_" .. i
  local title = type(t.title) == "string" and t.title:sub(1, 40) or "Shared theme"
  local taken = {}  -- (a name already in the list gets a number: "Vanilla (2)")
  for _, c in ipairs(choices()) do taken[c.title] = true end
  local base_title, k = title, 2
  while taken[title] do title = base_title .. " (" .. k .. ")"; k = k + 1 end
  r.custom[name] = { title = title, base = t.base, colors = colors }
  return name
end

function M.save_as(player, title)
  title = (title or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if title == "" then title = "My theme" end
  local th = M.resolve(player.index)
  local r = root()
  local n = 1
  while r.custom["custom_" .. n] do n = n + 1 end
  local name = "custom_" .. n
  r.custom[name] = { title = title, base = th.carrier, colors = th.edits }
  M.set_theme(player, name)
end

-- ---------------------------------------------------------------------------------------------------------------
-- events

M.handlers = {
  [defines.events.on_gui_click] = function(e)
    local el = e.element
    if not (el and el.valid and el.tags.fstd_ed) then return end
    local player = game.get_player(e.player_index)
    local what = el.tags.fstd_ed
    if what == "token" then
      selected[player.index] = el.tags.token
      fill(player)
    elseif what == "pick" then
      M.set_theme(player, el.tags.theme)
    elseif what == "export" then
      local text = M.export(player)
      shared[player.index] = text
      local copied = input.clipboard_set(text)
      fill(player)
      player.print(copied and "Theme copied to the clipboard." or "Theme text is in the field: select it, Ctrl+C.")
    elseif what == "import" then
      local name, err = M.import(player, el.parent.children[2].text)
      if name then
        shared[player.index] = nil
        M.set_theme(player, name)
      else
        player.print(err)
      end
    elseif what == "reset" then
      M.reset(player)
    elseif what == "save" then
      M.save_as(player, el.parent.children[1].text)
    end
  end,
  [defines.events.on_gui_selection_state_changed] = function(e)
    local el = e.element
    if not (el and el.valid and el.tags.fstd_ed == "theme") then return end
    local c = choices()[el.selected_index]
    if c then M.set_theme(game.get_player(e.player_index), c.name) end
  end,
  [defines.events.on_gui_value_changed] = function(e)
    local el = e.element
    if not (el and el.valid and el.tags.fstd_ed == "channel") then return end
    local player = game.get_player(e.player_index)
    local token = selected[player.index] or "win"
    local c = current_color(player, token)
    c = { r = c.r, g = c.g, b = c.b, a = c.a }
    local v = el.slider_value / 255
    if el.tags.ch == "a" then c.a = 1 - v else c[el.tags.ch] = v end
    el.parent.children[3].caption = tostring(math.floor(el.slider_value + 0.5))
    local row = el.parent.parent.children[2]  -- (the swatch and the #rrggbb field over the sliders)
    row.children[1].style.color = { r = c.r, g = c.g, b = c.b, a = 1 }
    row.children[2].text = hex(c)
    M.set_color(player, token, c, false)
  end,
  [defines.events.on_gui_confirmed] = function(e)
    local el = e.element
    if not (el and el.valid and el.tags.fstd_ed == "hex") then return end
    local player = game.get_player(e.player_index)
    local token = selected[player.index] or "win"
    local c = parse_hex(el.text)
    if not c then return end
    c.a = current_color(player, token).a
    M.set_color(player, token, c, true)
  end,
  [defines.events.on_gui_checked_state_changed] = function(e)
    local el = e.element
    if not (el and el.valid and el.tags.fstd_ed == "vanilla") then return end
    set_vanilla_gui(game.get_player(e.player_index), el.state)
  end,
  [defines.events.on_lua_shortcut] = function(e)
    if e.prototype_name ~= "fstd-theme" then return end
    local player = game.get_player(e.player_index)
    if editor(player) then
      editor(player).destroy()
      player.set_shortcut_toggled("fstd-theme", false)
    else
      M.open(player)
    end
  end,
  [defines.events.on_player_created] = function(e)
    probe(game.get_player(e.player_index))
  end,
  [defines.events.on_tick] = function(e)
    local r = storage.fstd_theme
    if r and r.redraw and next(r.redraw) then redraw_step(e.tick) end
    if tint.available() then  -- (hover fades: this peer's own player, no game state)
      local index = native.local_player()
      local player = index and applied[index] and game.get_player(index)
      if player then tint.fade_step(player, M.resolve(index), e.tick) end
    end
  end,
  -- a themed button hovered: its hover colour fades in (any mod's: hover events reach every mod)
  [defines.events.on_gui_hover] = function(e)
    local el = e.element
    local role = el and el.valid and el.tags.fstd_role
    if role and theme.FADE[role] and tint.available() and native.local_player() == e.player_index then
      tint.fade_start(role, e.tick)
    end
  end,
  [defines.events.on_player_display_scale_changed] = function(e)
    tint.forget()
    applied[e.player_index] = nil
  end,
}

-- (a load starts with the sprites as data.lua made them: the colours are written again once the probe is drawn;
-- only this peer's own player, and nothing it does is game state)
function M.tick()
  if not tint.available() then return end
  local index = native.local_player()
  local player = index and game.get_player(index)
  if not (player and player.connected) then return end
  if not applied[index] then live(player) end
  if game_dirty[index] and applied[index] then
    local th = M.resolve(index)
    local only = game_dirty[index] ~= true and game_dirty[index] or nil
    if not th.vanilla_gui or tint.apply_game(player, th, nil, only) then game_dirty[index] = nil end
  end
end

-- the overlays over the GUI: this peer's own player's (drawing is no game state)
function M.overlay_tick()
  if not overlay.available() then return end
  local index = native.local_player()
  local player = index and game.get_player(index)
  if player and player.connected then overlay.tick(player, M.resolve(index)) end
end

function M.overlay_cleanup() overlay.cleanup() end

-- the pulse role breathing (fse loader only; this peer's own player)
function M.pulse_tick(e)
  if not tint.available() then return end
  local index = native.local_player()
  local player = index and applied[index] and game.get_player(index)
  if player then tint.pulse(player, M.resolve(index), e.tick) end
end

-- On a load, before the first frame: this peer's player's colours written at once, so the game's side menu is
-- first drawn in them (it keeps that picture). Only reads storage; writes nothing that is game state.
function M.on_load()
  if not tint.available() then return end
  local index = native.local_player()
  local r = storage.fstd_theme
  local p = index and r and r.players[index]
  local pr = p and r.probes and r.probes[index]
  if not (pr and pr.valid) then return end
  local name = (themes.by_name[p.theme] or r.custom[p.theme]) and p.theme or "vanilla"
  local c = r.custom[name]
  local edits = {}
  if c then for k, v in pairs(c.colors) do edits[k] = v end end
  for k, v in pairs(p.edits[name] or {}) do edits[k] = v end
  local carrier = themes.by_name[name] and name or (c and themes.by_name[c.base] and c.base) or "vanilla"
  local th = { name = name, carrier = carrier, edits = edits, vanilla_gui = p.vanilla_gui }
  local who = { index = index }
  if tint.apply(who, th, nil, pr) then applied[index] = true end
  if th.vanilla_gui then tint.apply_game(who, th, pr) end
end

window.on_close(function(player, name)
  if name == NAME then player.set_shortcut_toggled("fstd-theme", false) end
end)

function M.init()
  root()
  for _, player in pairs(game.players) do probe(player) end
end

remote.add_interface("fse-std", {
  theme = function(index) return M.resolve(index) end,
  open_theme = function(index) M.open(game.get_player(index)) end,
  set_theme = function(index, name) M.set_theme(game.get_player(index), name) end,
  set_color = function(index, token, col) M.set_color(game.get_player(index), token, col, true) end,
  reset = function(index) M.reset(game.get_player(index)) end,
  set_vanilla_gui = function(index, on) set_vanilla_gui(game.get_player(index), on and true or false) end,
  themes = function() return choices() end,
  export_theme = function(index) return M.export(game.get_player(index)) end,
  import_theme = function(index, text) return M.import(game.get_player(index), text) end,
  -- drawing over the GUI (theme.graph, theme.glow): needs the fse loader's draw plugin
  draw_available = function() return overlay.available() end,
  overlay_add = function(el, kind, data) return overlay.add(el, kind, data) end,
  overlay_set = function(id, data) overlay.set(id, data) end,
  overlay_remove = function(id) overlay.remove(id) end,
})

commands.add_command("fse-theme", "Opens the theme window: pick a theme for every mod's windows, edit its colours",
  function(c)
    local player = c.player_index and game.get_player(c.player_index)
    if player then M.open(player) end
  end)

return M
