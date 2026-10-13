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
theme.window = theme.window or window  -- (theme.confirm and menu give Esc back through it)

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
    p = { edits = {}, vanilla_gui = false }  -- (theme nil: the server's default, fstd-default-theme)
    r.players[index] = p
  end
  return p
end

-- the theme a player who never picked one gets (a map setting)
local function default_theme(custom)
  local set = settings.global["fstd-default-theme"]
  local v = set and set.value
  return (themes.by_name[v] or (custom and custom[v])) and v or "vanilla"
end

-- a player's theme name: their pick, or the server's default (reads only: safe from this peer's own code)
local function name_of(p, custom)
  local n = p and p.theme
  if n and (themes.by_name[n] or (custom and custom[n])) then return n end
  return default_theme(custom)
end

local function base_of(name)
  if themes.by_name[name] then return name end
  local c = root().custom[name]
  return c and themes.by_name[c.base] and c.base or "vanilla"
end

--- a player's theme as the library wants it: {name, carrier, edits (saved theme's colours + the player's)}
function M.resolve(index)
  -- (reads only: this runs from this peer's own colour code too, which must never change game state)
  local r = storage.fstd_theme or { players = {}, custom = {} }
  local p = r.players[index] or { edits = {} }
  local name = name_of(p, r.custom)
  local edits = {}
  local c = r.custom[name]
  if c then for k, v in pairs(c.colors) do edits[k] = v end end
  for k, v in pairs(p.edits[name] or {}) do edits[k] = v end
  local carrier = themes.by_name[name] and name or (c and themes.by_name[c.base] and c.base) or "vanilla"
  return { name = name, carrier = carrier, edits = edits, vanilla_gui = p.vanilla_gui }
end

-- the themes to pick from: shipped, then saved ones
local function choices()
  local list = {}
  for _, t in ipairs(themes.list) do
    list[#list + 1] = { name = t.name, title = t.title, label = { "fstd-theme-name." .. t.name } }
  end
  local names = {}
  for name in pairs(root().custom) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local c = root().custom[name]
    local title, label = c.title, c.title
    if not title then  -- (one named after the theme it was made from: "Custom (Vanilla)", translated)
      local base = themes.by_name[c.base] or themes.by_name.vanilla
      local n = c.n and c.n > 1 and (" (" .. c.n .. ")") or ""
      title = "Custom (" .. base.title .. ")" .. n
      label = { "", { "fstd.custom-of", { "fstd-theme-name." .. base.name } }, n }
    end
    list[#list + 1] = { name = name, title = title, label = label }
  end
  return list
end

-- a new custom theme's number among those made from the same theme without a name of their own (1, 2, ...)
local function next_n(base)
  local n = 0
  for _, c in pairs(root().custom) do
    if not c.title and c.base == base then n = math.max(n, c.n or 1) end
  end
  return n + 1
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

local function token_title(token) return { "fstd-token." .. token } end

-- a colour swatch: a full progress bar, whose colour Lua can set at any time (tags: a click picks what it shows)
local function swatch(parent, col, width, name, height, tags)
  local bar = parent.add({ type = "progressbar", value = 1, name = name, tags = tags })
  bar.style.color = { r = col.r, g = col.g, b = col.b, a = 1 }
  bar.style.width = width
  bar.style.bar_width = height or 18
  return bar
end
local function recolor(bar, col) bar.style.color = { r = col.r, g = col.g, b = col.b, a = 1 } end

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

local CHANNELS = { { "r", { "fstd.red" } }, { "g", { "fstd.green" } }, { "b", { "fstd.blue" } },
  { "a", { "fstd.see-through" } } }
local function channel_value(col, ch)
  return ch == "a" and math.floor((1 - col.a) * 255 + 0.5) or math.floor(col[ch] * 255 + 0.5)
end

-- the window's parts by name (nil when it isn't open)
local function parts(player)
  local frame = editor(player)
  local pane = frame and frame.children[2].fstd_ed_pane
  if not pane then return nil end
  local share = pane.fstd_ed_share and pane.fstd_ed_share.fstd_fold_body
  return { pane = pane, gallery = pane.fstd_ed_gallery.fstd_ed_cells, mine = pane.fstd_ed_gallery.fstd_ed_mine,
    tokens = pane.fstd_ed_colours.fstd_ed_tokens, ed = pane.fstd_ed_editor, share = share and share.children[2] and share.children[2].fstd_ed_share_row,
    vanilla = pane.fstd_ed_vanilla }
end

-- the theme buttons of the gallery: shipped ones, then the player's saved ones
local function cells_of(w)
  local out = {}
  for _, t in ipairs({ w.gallery, w.mine }) do
    for _, c in pairs(t and t.valid and t.children or {}) do out[#out + 1] = c end
  end
  return out
end

-- what changes as the player picks and edits, written into the open window in place (the view stays where it is)
local function update(player)
  local w = parts(player)
  if not w then return end
  local th = M.resolve(player.index)
  local t = themes.by_name[th.carrier]
  for _, cell in ipairs(cells_of(w)) do
    local name = cell.tags.theme
    cell.children[1].toggled = name == th.name
    local base, edits = theme_colors(player, name)
    for i, bar in ipairs(cell.children[2].children[1].children) do recolor(bar, themes.color(base, edits, STRIP[i])) end
  end
  local sel = selected[player.index] or "win"
  for _, tok in ipairs(themes.TOKENS) do
    local b = tok.edit and w.tokens["b_" .. tok[1]]
    if b then
      b.toggled = tok[1] == sel
      b.tooltip = th.edits[tok[1]] and { "fstd.edited" } or { "fstd.not-edited" }
      recolor(w.tokens["f_" .. tok[1]].children[1], themes.color(t, th.edits, tok[1]))
    end
  end
  local col = themes.color(t, th.edits, sel)
  w.ed.children[1].caption = token_title(sel)
  recolor(w.ed.fstd_ed_row.children[1].fstd_ed_swatch, col)
  w.ed.fstd_ed_row.fstd_ed_hex.text = hex(col)
  for _, ch in ipairs(CHANNELS) do
    local row = w.ed["fstd_ed_ch_" .. ch[1]]
    row.visible = ch[1] ~= "a" or t.glass or false
    local v = channel_value(col, ch[1])
    row.fstd_ed_slider.slider_value = v
    row.fstd_ed_value.caption = tostring(v)
  end
  w.vanilla.state = pstate(player.index).vanilla_gui
end

local function fill(player)
  local frame = editor(player)
  if not frame then return end
  local content = frame.children[2]
  content.clear()
  content = theme.add(content, { type = "scroll-pane", name = "fstd_ed_pane", horizontal_scroll_policy = "never" },
    "scroll", { horizontally_stretchable = true, vertically_stretchable = true, padding = 0 })
  local th = M.resolve(player.index)
  local t = themes.by_name[th.carrier]
  local p = pstate(player.index)

  -- the themes, each with a strip of its colours (framed: light colours show on a light theme; a click picks it)
  local gallery = theme.section(content, { "fstd.theme" }, nil, "fstd_ed_gallery")
  theme.apply(gallery, "section", { horizontally_stretchable = true })  -- (the pane's width, not more)
  -- (cells of one fixed width, the strip as wide as the button: three always fit the panel, monospace ones too)
  local function table_of(name, columns)
    local t = gallery.add({ type = "table", name = name, column_count = columns })
    t.style.horizontal_spacing = 4
    t.style.vertical_spacing = 6
    return t
  end
  local cells, mine = table_of("fstd_ed_cells", 3), nil
  for _, c in ipairs(choices()) do
    if not themes.by_name[c.name] and not mine then  -- (the player's saved themes: a row of their own)
      theme.add(gallery, { type = "label", caption = { "fstd.your-themes" } }, "dim")
      mine = table_of("fstd_ed_mine", 2)  -- (wider: names of the player's own)
    end
    local cell = (mine or cells).add({ type = "flow", direction = "vertical", tags = { theme = c.name } })
    cell.style.vertical_spacing = 2
    local pick = { fstd_ed = "pick", theme = c.name }
    theme.add(cell, { type = "button", caption = c.label, toggled = c.name == th.name, tags = pick, tooltip = c.label },
      "tab", { width = mine and 170 or 114, left_padding = 2, right_padding = 2 })
    local border = cell.add({ type = "frame", style = "fstd_swatch_frame", tags = pick })
    local strip = border.add({ type = "flow", direction = "horizontal" })
    strip.style.horizontal_spacing = 0
    local base, edits = theme_colors(player, c.name)
    for _, tok in ipairs(STRIP) do swatch(strip, themes.color(base, edits, tok), 21, nil, 10, pick) end
  end

  local sec = theme.section(content, { "fstd.colours" }, { "fstd.colours-tooltip" }, "fstd_ed_colours")
  theme.apply(sec, "section", { horizontally_stretchable = true })  -- (the pane's width, not more)
  local grid = sec.add({ type = "table", name = "fstd_ed_tokens", column_count = 4 })
  grid.style.horizontal_spacing = 6
  grid.style.vertical_spacing = 4
  local sel = selected[player.index] or "win"
  for _, tok in ipairs(themes.TOKENS) do
    if tok.edit then
      local pick = { fstd_ed = "token", token = tok[1] }
      local f = grid.add({ type = "frame", name = "f_" .. tok[1], style = "fstd_swatch_frame", tags = pick })
      swatch(f, themes.color(t, th.edits, tok[1]), 24, nil, nil, pick)
      theme.add(grid, { type = "button", name = "b_" .. tok[1], caption = token_title(tok[1]), toggled = tok[1] == sel,
        tags = pick, tooltip = th.edits[tok[1]] and { "fstd.edited" } or { "fstd.not-edited" } }, "tab",
        { minimal_width = 110 })
    end
  end

  -- the selected colour's editor, right under its list (in view without scrolling)
  local col = themes.color(t, th.edits, sel)
  local ed = theme.section(content, token_title(sel), nil, "fstd_ed_editor")
  theme.apply(ed, "section", { horizontally_stretchable = true })  -- (the pane's width, not more)
  local row = ed.add({ type = "flow", name = "fstd_ed_row", direction = "horizontal" })
  row.style.vertical_align = "center"
  local sf = row.add({ type = "frame", style = "fstd_swatch_frame" })
  swatch(sf, col, 64, "fstd_ed_swatch")
  theme.add(row, { type = "textfield", name = "fstd_ed_hex", text = hex(col), tags = { fstd_ed = "hex" },
    tooltip = { "fstd.hex-tooltip" } }, "field", { width = 90 })
  local push = row.add({ type = "empty-widget" })
  push.style.horizontally_stretchable = true
  theme.add(row, { type = "button", caption = { "fstd.reset" }, tags = { fstd_ed = "reset" },
    tooltip = { "fstd.reset-tooltip" } }, "button")
  for _, ch in ipairs(CHANNELS) do
    local f = ed.add({ type = "flow", name = "fstd_ed_ch_" .. ch[1], direction = "horizontal",
      visible = ch[1] ~= "a" or t.glass or false })
    f.style.vertical_align = "center"
    theme.add(f, { type = "label", caption = ch[2] }, "dim", { width = 80 })
    local v = channel_value(col, ch[1])
    theme.add(f, { type = "slider", name = "fstd_ed_slider", minimum_value = 0, maximum_value = 255, value = v,
      value_step = 1, discrete_values = true, tags = { fstd_ed = "channel", ch = ch[1] } }, "slider",
      { horizontally_stretchable = true })
    theme.add(f, { type = "label", name = "fstd_ed_value", caption = tostring(v) }, "dim", { width = 30 })
  end

  -- saving and sharing: rarely used, folded (open while it holds a theme's text)
  local share = theme.fold(content, { "fstd.share" }, shared[player.index] ~= nil, "fstd_ed_share")
  theme.apply(share.parent, "section", { horizontally_stretchable = true })  -- (the pane's width, not more)
  local nf = theme.field(share, { "fstd.save-name" }, { "fstd.save-name-tooltip" })
  local save = nf.add({ type = "flow", direction = "horizontal" })
  save.style.vertical_align = "center"
  theme.add(save, { type = "textfield", name = "fstd_ed_save_name", text = "", tags = { fstd_ed = "save_name" },
    tooltip = { "fstd.save-name-tooltip" } }, "field", { width = 180 })
  theme.add(save, { type = "button", caption = { "fstd.save" }, tags = { fstd_ed = "save" } }, "ok_small")
  local sf = theme.field(share, { "fstd.share-text" }, { "fstd.share-tooltip" })
  local srow = sf.add({ type = "flow", name = "fstd_ed_share_row", direction = "horizontal" })
  srow.style.vertical_align = "center"
  theme.add(srow, { type = "button", caption = { "fstd.export" }, tags = { fstd_ed = "export" },
    tooltip = { "fstd.export-tooltip" } }, "button")
  theme.add(srow, { type = "textfield", name = "fstd_ed_share_text", text = shared[player.index] or "",
    tags = { fstd_ed = "share_text" }, tooltip = { "fstd.import-tooltip" } }, "field", { width = 150 })
  theme.add(srow, { type = "button", caption = { "fstd.import" }, tags = { fstd_ed = "import" },
    tooltip = { "fstd.import-tooltip" } }, "ok_small", { minimal_width = 60 })

  -- every window's size (the player's setting fstd-window-scale): drawn at it at once
  local size = theme.style(content.add({ type = "flow", direction = "horizontal" }), { vertical_align = "center" })
  theme.add(size, { type = "label", caption = { "fstd.window-scale" }, tooltip = { "fstd.window-scale-tooltip" } }, "text")
  local items, pick = {}, 1
  local now = math.floor(theme.setting_scale(player) * 100 + 0.5)
  for i, c in ipairs(themes.SCALE_CHOICES) do
    items[i] = { "fstd.percent", c }
    if c == now then pick = i end
  end
  theme.add(size, { type = "drop-down", name = "fstd_ed_scale", items = items, selected_index = pick,
    tags = { fstd_ed = "scale" }, tooltip = { "fstd.window-scale-tooltip" } }, "dropdown")

  local live_ok = tint.available()
  theme.add(content, { type = "checkbox", name = "fstd_ed_vanilla", state = p.vanilla_gui, enabled = live_ok,
    tags = { fstd_ed = "vanilla" }, caption = { "fstd.game-windows" },
    tooltip = live_ok and { "fstd.game-windows-tooltip" } or { "fstd.needs-fse" } }, "check")
  theme.add(content, { type = "label", caption = live_ok and { "fstd.live-on" } or { "fstd.live-off" } },
    "dim", { single_line = false })
  theme.scale_tree(frame)  -- (the swatches and tables: plain elements, at the window's scale)
end

-- the window as it should be: in place when the same themes are listed, else made again
local function refresh(player)
  local w = parts(player)
  local list = choices()
  local cells = w and cells_of(w)
  if w and #cells == #list then
    local same = true
    for i, c in ipairs(list) do
      if cells[i].tags.theme ~= c.name then same = false end
    end
    if same then return update(player) end
  end
  fill(player)
end

function M.open(player)
  if editor(player) then editor(player).destroy() end
  player.set_shortcut_toggled("fstd-theme", true)
  -- (tall enough for the editor's sliders under the gallery, where the screen has room: at its scale)
  local _, want = window.scale(player, NAME)
  local fit = math.floor(player.display_resolution.height / (player.display_scale * want)) - 120
  window.create(player, { name = NAME, title = { "fstd.theme-window" }, width = 480,
    height = math.max(400, math.min(900, fit)), themed = true, min_width = 360, min_height = 400 })
  fill(player)
end

-- ---------------------------------------------------------------------------------------------------------------
-- changes

local function changed(player, opts)
  if opts.carrier then probe(player) end
  if opts.restyle then script.raise_event("fstd-theme-changed", { player_index = player.index }) end
  live(player, opts.only)
  if pstate(player.index).vanilla_gui then schedule_redraw(player) end
  if opts.refill then refresh(player) end
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
  local name = name_of(p, root().custom)
  p.edits[name] = p.edits[name] or {}
  p.edits[name][token] = { r = col.r, g = col.g, b = col.b, a = col.a or 1 }
  changed(player, { restyle = is_ink(token), only = token, refill = refill })
end

function M.reset(player)
  local p = pstate(player.index)
  p.edits[name_of(p, root().custom)] = nil
  changed(player, { restyle = true, refill = true })
end

-- a theme as text: "fstd1" and the encoded JSON of {title, base, colors}
function M.export(player)
  local th = M.resolve(player.index)
  local c = root().custom[th.name]
  local t = { title = c and c.title or nil, base = th.carrier, colors = th.edits }  -- (no title: "Custom (<base>)")
  return "fstd1" .. helpers.encode_string(helpers.table_to_json(t))
end

-- a theme's text back to a saved theme: its name, or nil and why not
function M.import(player, text)
  text = (text or ""):gsub("%s", "")
  if text:sub(1, 5) ~= "fstd1" then return nil, { "fstd.not-a-theme" } end
  local json = helpers.decode_string(text:sub(6))
  local t = json and helpers.json_to_table(json)
  if type(t) ~= "table" or not themes.by_name[t.base] then return nil, { "fstd.damaged-theme" } end
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
  -- (a shipped theme's name, or none: named after the theme it was made from, "Custom (Vanilla)")
  local title = type(t.title) == "string" and t.title:gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 40) or ""
  for _, s in ipairs(themes.list) do if s.title == title then title = "" end end
  if title == "" then
    r.custom[name] = { base = t.base, n = next_n(t.base), colors = colors }
    return name
  end
  local taken = {}  -- (a name already in the list gets a number: "My theme (2)")
  for _, c in ipairs(choices()) do taken[c.title] = true end
  local base_title, k = title, 2
  while taken[title] do title = base_title .. " (" .. k .. ")"; k = k + 1 end
  r.custom[name] = { title = title, base = t.base, colors = colors }
  return name
end

function M.save_as(player, title)
  title = (title or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local th = M.resolve(player.index)
  local r = root()
  local n = 1
  while r.custom["custom_" .. n] do n = n + 1 end
  local name = "custom_" .. n
  if title == "" then  -- (no name given: "Custom (Vanilla)")
    r.custom[name] = { base = th.carrier, n = next_n(th.carrier), colors = th.edits }
  else
    r.custom[name] = { title = title:sub(1, 40), base = th.carrier, colors = th.edits }
  end
  M.set_theme(player, name)
end

--- every window's size for a player (percent: one of themes.SCALE_CHOICES): the setting fstd-window-scale, and every
--- mod's windows told at once (fstd-scale-changed: a setting set by a script may not raise its event)
function M.set_window_scale(player, pct)
  local ok = false
  for _, c in ipairs(themes.SCALE_CHOICES) do if c == pct then ok = true end end
  if not ok then return false end
  player.mod_settings["fstd-window-scale"] = { value = pct }
  script.raise_event("fstd-scale-changed", { player_index = player.index })
  return true
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
      refresh(player)
    elseif what == "pick" then
      M.set_theme(player, el.tags.theme)
    elseif what == "export" then
      local text = M.export(player)
      shared[player.index] = text
      local copied = input.clipboard_set(text)
      local w = parts(player)
      if w and w.share then
        w.share.fstd_ed_share_text.text = text
        local fold = w.pane.fstd_ed_share  -- (the text shows: its fold opens)
        fold.fstd_fold_body.visible = true
        fold.children[1].children[1].caption = "-"
      end
      theme.toast(player, copied and { "fstd.copied" } or { "fstd.copy-by-hand" }, { window = NAME })
    elseif what == "import" then
      local name, err = M.import(player, el.parent.fstd_ed_share_text.text)
      if name then
        shared[player.index] = nil
        M.set_theme(player, name)
      else
        theme.toast(player, err, { window = NAME })
      end
    elseif what == "reset" then
      local th = M.resolve(player.index)
      if next(pstate(player.index).edits[th.name] or {}) == nil then
        M.reset(player)  -- (no colour edits of the player's to lose)
      else
        theme.confirm(player, { name = "fstd_reset", title = { "fstd.reset" }, text = { "fstd.reset-confirm" },
          yes = { "fstd.reset-yes" }, no = { "fstd.keep" }, danger = true })
      end
    elseif what == "save" then
      M.save_as(player, el.parent.fstd_ed_save_name.text)
    end
  end,
  [defines.events.on_gui_selection_state_changed] = function(e)
    local el = e.element
    if el and el.valid and el.tags.fstd_ed == "scale" then
      local c = themes.SCALE_CHOICES[el.selected_index]
      if c then M.set_window_scale(game.get_player(e.player_index), c) end
      return
    end
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
    el.parent.fstd_ed_value.caption = tostring(math.floor(el.slider_value + 0.5))
    local row = el.parent.parent.fstd_ed_row  -- (the swatch and the #rrggbb field over the sliders)
    recolor(row.children[1].fstd_ed_swatch, c)
    row.fstd_ed_hex.text = hex(c)
    M.set_color(player, token, c, false)
    local w = parts(player)  -- (its swatch in the colours' list)
    local sw = w and w.tokens["f_" .. token]
    if sw then recolor(sw.children[1], c) end
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
  [defines.events.on_runtime_mod_setting_changed] = function(e)
    if e.setting ~= "fstd-default-theme" then return end
    for _, player in pairs(game.players) do
      local p = root().players[player.index]
      if not (p and p.theme) then
        probe(player)
        script.raise_event("fstd-theme-changed", { player_index = player.index })
        live(player)
        if editor(player) then refresh(player) end
      end
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
  local name = name_of(p, r.custom)
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

-- "Reset to default colours" asks first when the player's colour edits would go
theme.on_confirm(function(player, name, yes)
  if name == "fstd_reset" and yes then M.reset(player) end
end)

function M.init()
  local r = root()
  if not r.default_migrated then  -- (saves from before the server default stored "vanilla" for everyone)
    r.default_migrated = true
    for _, p in pairs(r.players) do
      if p.theme == "vanilla" then p.theme = nil end
    end
  end
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
  -- the server's default theme (the map setting), for scenarios and server scripts
  -- every window's size for a player (percent: 75 90 100 110 125 150 175 200), as the theme window's Window size
  set_window_scale = function(index, pct) return M.set_window_scale(game.get_player(index), pct) end,
  set_default_theme = function(name)
    if themes.by_name[name] then settings.global["fstd-default-theme"] = { value = name } end
  end,
  export_theme = function(index) return M.export(game.get_player(index)) end,
  import_theme = function(index, text) return M.import(game.get_player(index), text) end,
  -- drawing over the GUI (theme.graph, theme.glow): needs the fse loader's draw plugin
  draw_available = function() return overlay.available() end,
  overlay_add = function(el, kind, data) return overlay.add(el, kind, data) end,
  overlay_set = function(id, data) overlay.set(id, data) end,
  overlay_remove = function(id) overlay.remove(id) end,
})

commands.add_command("fse-theme", { "fstd.command-help" },
  function(c)
    local player = c.player_index and game.get_player(c.player_index)
    if player then M.open(player) end
  end)

return M
