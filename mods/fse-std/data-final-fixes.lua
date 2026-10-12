-- every frame, scroll pane, table, tab, button, label and checkbox style of the game and of every mod, for "colour the
-- game's own windows": each image set a style defines itself, with the theme token it follows (and how), and each text
-- colour it defines itself that a theme may change. The control stage reads it from the mod-data (themes.game_styles).
-- Only what a style defines itself is listed: the engine draws a style without a set of its own with its parent's, so
-- a write to the parent's colours it too (a child listed with its own token would write into the parent's sprites).
--
-- With the startup setting fstd-flat-game, the game's plain 9-slice image sets are also drawn with fse-std's white
-- tiles (tinted in the game's own colours to start with), so a theme can make the game's windows any colour, light
-- ones too. Sets made of separate pieces (a frame open on one side, like the map view's) keep their shape. Text
-- colours are listed only where the art under them was flattened (a light theme needs dark text there, not on the
-- game's dark textures), and only the game's plain white / heading / black text: coloured text (a hyperlink, a
-- warning, a clickable label's hover) keeps its meaning.
--
-- Load order: fse-std depends only on base, so a mod loaded after it (one that depends on more, or on fse-std) may
-- still change or add styles in its own data-final-fixes. Such later styles are not listed (the control stage adds the
-- ones it finds in prototypes.style, untinted); a set a later mod replaced is found at run time (its sprite is no
-- longer fse-std's tile, tint.lua) and then left as the game's art, its text unchanged. (A hidden optional dependency
-- on every such mod would move fse-std after them, but it would have to name them all, and a mod that depends on
-- fse-std can never come before it.)

local themes = require("themes")
local styles = data.raw["gui-style"].default

-- adopt()'s variants (theme.lua): each game style it themes, with its role's colours, for every theme. Made here,
-- when flib's and every mod's styles are there, and before the flat tiles below replace the game's own art
require("theme_data").roles(true)
local flat = settings.startup["fstd-flat-game"] and settings.startup["fstd-flat-game"].value or false

-- (anchored to whole words of the name: "red" must not match bordered_frame, hovered, colored, centered)
local SKIP_WORD = { red = true, green = true, blue = true, yellow = true, orange = true, confirm = true, dirt = true,
  flib = true }
local SKIP_START = { "technology", "achievement", "highlight", "transparent", "invisible" }
local function skip(name)
  if name:sub(1, 5) == "fstd_" or name:find("tip_notice", 1, true) then return true end
  for w in name:gmatch("[^_%-]+") do
    if SKIP_WORD[w] then return true end
    for _, p in ipairs(SKIP_START) do if w:sub(1, #p) == p then return true end end
  end
  return false
end

-- (a style without a parent inherits its type's default style)
local DEFAULT = { frame_style = "frame", button_style = "button", label_style = "label", checkbox_style = "checkbox",
  radiobutton_style = "radiobutton", tab_style = "tab", table_style = "table", scroll_pane_style = "scroll_pane",
  tabbed_pane_style = "tabbed_pane", switch_style = "switch" }
local function parent_of(name)
  local s = styles[name]
  if type(s) ~= "table" then return nil end
  if s.parent then return s.parent end
  local d = DEFAULT[s.type]
  if d and d ~= name then return d end
end

-- the style that defines `key` (the style itself or the nearest parent), and the value
local function owner(name, key)
  local depth = 0
  while name and depth < 50 do
    local s = styles[name]
    if type(s) ~= "table" then return nil end
    if s[key] ~= nil then return name, s[key] end
    name, depth = parent_of(name), depth + 1
  end
end

-- what art a style is drawn with: its nearest parent the game draws with a known colour (inside_deep_frame: deep;
-- slot_sized_button, slot, compact_slot: the light grey buttons; slot_button: the dark slot). A style named
-- "..._selected" (GUI Unifyer's) is a selected look: the accent.
local ROOT = {
  frame = "win", inside_deep_frame = "deep", deep_frame_in_shallow_frame = "deep", inside_shallow_frame = "inset",
  subheader_frame = "inset", subfooter_frame = "inset", bordered_frame = "section", scroll_pane = "deep",
  button = "btn", slot = "btn", slot_sized_button = "btn", compact_slot = "btn", slot_button = "slot",
  frame_button = "win", tab = "btn", table = "inset",
}
local FALLBACK = { frame_style = "win", button_style = "btn", scroll_pane_style = "deep", tab_style = "btn",
  table_style = "inset" }
local function token_of(name)
  for w in name:gmatch("[^_%-]+") do if w == "selected" then return "btn_on" end end
  local n, depth = name, 0
  while n and depth < 50 do
    if ROOT[n] then return ROOT[n], n end
    n, depth = parent_of(n), depth + 1
  end
  -- (a root of a mod's own: guessed from its name, as before)
  local s = styles[name]
  if s.type == "frame_style" then
    if name:find("deep") then return "deep" end
    if name:find("shallow") or name:find("subheader") or name:find("inner") then return "inset" end
  end
  return FALLBACK[s.type] or "win"
end

-- data key -> the engine's field (camel case)
local function engine(key)
  return (key:gsub("_(%l)", function(c) return c:upper() end))
end

-- the colours of a style's text as numbers 0..1 ({1, 1, 1} and 0..255 values too), or nil
local function rgba(c)
  if type(c) ~= "table" then return nil end
  local r, g, b, a = c.r or c[1] or 0, c.g or c[2] or 0, c.b or c[3] or 0, c.a or c[4]
  if r > 1 or g > 1 or b > 1 then r, g, b = r / 255, g / 255, b / 255; if a and a > 1 then a = a / 255 end end
  return { r = r, g = g, b = b, a = a or 1 }
end
local function near(c, ref, d)
  return c and math.abs(c.r - ref.r) < d and math.abs(c.g - ref.g) < d and math.abs(c.b - ref.b) < d and c.a > 0.5
end
local WHITE, BLACK, CAPTION = { r = 1, g = 1, b = 1 }, { r = 0, g = 0, b = 0 }, rgba({ 255, 230, 192 })
-- which token a text colour of the game's stands for: plain white text, a heading's, a button's black; else nil
local function ink_of(c)
  c = rgba(c)
  if near(c, WHITE, 0.1) then return "ink" end
  if near(c, CAPTION, 0.06) then return "caption" end
end
local function black(c) return near(rgba(c), BLACK, 0.15) end

-- (the engine shares sprites that are equal: each (token, how) a style's set follows gets a hair of alpha of its own,
-- so two sets drawn the same but coloured apart (odd and even rows, a frame and the slot grid behind it) never share
-- one. Kept clear of the themes' own offsets (multiples of 0.0004: theme_data.lua))
local marks, mark_list = {}, {}
local function mark(token, how)
  local key = token .. "/" .. how
  if not marks[key] then mark_list[#mark_list + 1] = key; marks[key] = true end
  return key
end

-- a plain 9-slice set (a corner size, no separately given edges): what a flat tile can stand in for. Not a hollow
-- one: drawn "outer" without a centre of its own, it is a border around something that shows through (the map
-- view's frame_around_center)
local PIECES = { "top", "bottom", "left", "right", "left_top", "right_top", "left_bottom", "right_bottom" }
local function pieces(base)
  for _, k in ipairs(PIECES) do if base[k] ~= nil then return true end end
  return false
end
local function base_of(set)
  if type(set) ~= "table" or next(set) == nil then return nil end
  local b = set.base or ((set.shadow or set.glow) and nil or set)
  if type(b) ~= "table" or b.type == "none" then return nil end
  -- (art: a place in a file, or pieces. Not a blur alone: blurry_scroll_pane)
  if not (b.position or b.filename or b.x or b.y or b.center or pieces(b)) then return nil end
  return b
end
local function ours(b) return not b.filename or b.filename == "__core__/graphics/gui-new.png" end
local function plain(b)
  if pieces(b) then return false end
  if not (b.corner_size or b.border) then return false end  -- (slots: border = 4)
  if b.draw_type == "outer" and b.center == nil then return false end
  return ours(b)  -- (a mod's own art: kept)
end

local FILE = "__fse-std__/graphics/theme.png"
local SOFT = themes.SHAPES.soft
-- the tile for a set: the game's corner size (in GUI units) kept by the scale, its draw type, opacity, shadow and glow
local function tile(kind, col, set, b)
  local c = b.corner_size or b.border or SOFT.corner
  if type(c) == "table" then c = c[1] or SOFT.corner end
  local base = { filename = FILE, corner_size = SOFT.corner, tint = themes.tint({ shape = "soft" }, "", col),
    position = { themes.KINDS[kind] * themes.STEP, SOFT.row * themes.STEP }, draw_type = b.draw_type,
    scale = c * (b.scale or 1) / SOFT.corner, opacity = b.opacity }
  -- (drawn outside the element: the game's art there is mostly the colour around it, a thin rim shows. A whole tile
  -- out there would cover what is next to it)
  if b.draw_type == "outer" then base.scale = 0.25 end
  return { base = base, shadow = set.base and table.deepcopy(set.shadow) or nil,
    glow = set.base and table.deepcopy(set.glow) or nil }
end

-- a set made of separate pieces (a frame open on one side), or just a centre (statistics_scroll_pane): each piece it
-- has, cut from the tile
local function piece_tile(set, b, kind, col)
  local x0, y0, c = themes.KINDS[kind] * themes.STEP, SOFT.row * themes.STEP, SOFT.corner
  local at = { left_top = { 0, 0, c, c }, top = { c, 0, 1, c }, right_top = { c + 1, 0, c, c },
    left = { 0, c, c, 1 }, center = { c, c, 1, 1 }, right = { c + 1, c, c, 1 },
    left_bottom = { 0, c + 1, c, c }, bottom = { c, c + 1, 1, c }, right_bottom = { c + 1, c + 1, c, c } }
  local new = { tint = themes.tint({ shape = "soft" }, "", col), draw_type = b.draw_type, opacity = b.opacity }
  for k, r in pairs(at) do
    if b[k] ~= nil then new[k] = { filename = FILE, position = { x0 + r[1], y0 + r[2] }, size = { r[3], r[4] } } end
  end
  return { base = new, shadow = set.base and table.deepcopy(set.shadow) or nil,
    glow = set.base and table.deepcopy(set.glow) or nil }
end

-- the flat version of a set (nil: it stays the game's): a tile in the token's colour as the game draws it
local function flattened(set, kind, token, how)
  local b = base_of(set)
  if not b then return nil end
  local col = themes.derive(themes.VANILLA[token], how)
  if ours(b) and not (b.corner_size or b.border) and (b.size == 1 or (type(b.size) == "table" and b.size[1] == 1
      and b.size[2] == 1)) then  -- (one pixel stretched: a table's striped rows)
    local x0, y0 = themes.KINDS[kind] * themes.STEP, SOFT.row * themes.STEP
    return { base = { filename = FILE, position = { x0 + SOFT.corner, y0 + SOFT.corner }, size = 1,
      tint = themes.tint({ shape = "soft" }, "", col), opacity = b.opacity } }
  end
  if pieces(b) or (b.center and not b.corner_size and not b.border) then
    return ours(b) and piece_tile(set, b, kind, col) or nil
  end
  if not plain(b) then return nil end
  if b.overall_tiling_horizontal_size or b.overall_tiling_vertical_size or b.custom_horizontal_tiling_sizes then
    -- (drawn once per cell, slot grids: the tiling kept, the outline tile)
    local new = tile("outline", col, set, b)
    new.base.scale = nil
    for k, v in pairs(b) do
      if k:find("tiling") or k:find("^overall") then new.base[k] = table.deepcopy(v) end
    end
    return new
  end
  return tile(kind, col, set, b)
end

-- what each kind of style lists: { data key, token (nil: the style's own), how, tile kind }
local FRAME = { { "graphical_set", nil, "same", "panel" }, { "background_graphical_set", "slot", "same", "flat" } }
local SCROLL = { { "graphical_set", nil, "same", "inset" }, { "background_graphical_set", "slot", "same", "flat" } }
local TABLE = { { "background_graphical_set", "slot", "same", "flat" }, { "default_row_graphical_set", nil, "same", "flat" },
  { "odd_row_graphical_set", nil, "same", "flat" }, { "even_row_graphical_set", nil, "darker", "flat" },
  { "hovered_graphical_set", nil, "lighter", "flat" }, { "selected_graphical_set", "btn_on", "same", "flat" } }
-- (a selected tab is the content it opens: the tabbed pane's colour)
local TAB = { { "default_graphical_set", nil, "same", "button" }, { "hovered_graphical_set", nil, "lighter", "button" },
  { "clicked_graphical_set", nil, "darker", "button" }, { "disabled_graphical_set", nil, "faded", "button" },
  { "selected_graphical_set", "inset", "same", "button" } }
local BUTTON = { { "default_graphical_set", nil, "same", "button" }, { "hovered_graphical_set", nil, "lighter", "button" },
  { "clicked_graphical_set", nil, "darker", "button" }, { "disabled_graphical_set", nil, "faded", "button" },
  { "selected_graphical_set", "btn_on", "same", "button" }, { "selected_hovered_graphical_set", "btn_on", "lighter", "button" },
  { "selected_clicked_graphical_set", "btn_on", "darker", "button" } }
local KIND = { frame_style = "frame", scroll_pane_style = "scroll", table_style = "table", tabbed_pane_style = "tabbed",
  tab_style = "tab", label_style = "label", button_style = "button", checkbox_style = "check",
  radiobutton_style = "radio", switch_style = "switch" }
local SETS = { frame = FRAME, scroll = SCROLL, table = TABLE, tab = TAB, button = BUTTON }

-- buttons the game draws a white icon on (the shortcut bar, the side menu's research and map buttons, a title bar's):
-- on a light theme's flat tile the icon would vanish, so their tiles go dark there ("icon_<how>": themes.derive).
-- One that is drawn with its parent's art gets its own copy of it, so its parent (slot_sized_button) stays light.
local ICON = { shortcut_bar_button = true, shortcut_bar_button_small = true, shortcut_bar_expand_button = true,
  side_menu_button = true, frame_action_button = true }

local names = {}
for name, s in pairs(styles) do
  if type(s) == "table" and KIND[s.type] and not skip(name) then names[#names + 1] = name end
end
table.sort(names)  -- (the same list, the same order, whatever order pairs() visits them in)

-- pass 1: the plan, read from the styles as the game and the mods made them (nothing changed yet, so no style sees
-- another's flat tile in place of its art)
local plan = {}     -- { style table, key, nested table or nil, new set }
local flat_at = {}  -- "<style>/<key>" -> its set is flattened
local list = {}
for _, name in ipairs(names) do
  local s = styles[name]
  local kind = KIND[s.type]
  local entry = { name = name, kind = kind, sets = {}, fonts = {} }
  local own, root = token_of(name)
  for _, st in ipairs(SETS[kind] or {}) do
    local key, token, how, tk = st[1], st[2] or own, st[3], st[4]
    -- (a title bar's buttons: lit in the accent, where the game inverts their icon)
    if root == "frame_button" and (key == "hovered_graphical_set" or key == "clicked_graphical_set") then
      token, how = "btn_on", key == "clicked_graphical_set" and "darker" or "same"
    end
    if kind == "frame" and key == "graphical_set" and token ~= "win" then tk = "inset" end
    local set = s[key]
    local icon = flat and ICON[name] and token ~= "btn_on"
    if set == nil and icon then local _; _, set = owner(name, key) end  -- (the parent's art, as its own)
    if icon then how = "icon_" .. how end
    if base_of(set) and (s[key] ~= nil or flattened(set, tk, token, how)) then
      local new = flat and flattened(set, tk, token, how)
      if new then
        plan[#plan + 1] = { s, key, nil, new }
        flat_at[name .. "/" .. key] = true
      end
      entry.sets[#entry.sets + 1] = { path = { engine(key) }, token = token, how = how, flat = new and true or nil,
        mark = mark(token, how) }
    end
  end
  if kind == "tabbed" and type(s.tab_content_frame) == "table" then  -- (its content frame: a sub-style of its own)
    local tf = s.tab_content_frame
    local set = tf.graphical_set
    if set == nil and tf.parent then local _; _, set = owner(tf.parent, "graphical_set") end
    if base_of(set) then
      local new = flat and flattened(set, "inset", "inset", "same")
      if new then plan[#plan + 1] = { s, "graphical_set", tf, new } end
      if tf.graphical_set ~= nil or new then
        entry.sets[#entry.sets + 1] = { path = { "contentFrame", "graphicalSet" }, token = "inset", how = "same",
          flat = new and true or nil, mark = mark("inset", "same") }
      end
    end
  end
  list[#list + 1] = entry
end

-- is the art a style is drawn with (its own set at `key`, or the parent's it inherits) a flat tile?
local function art_flat(name, key)
  local o = owner(name, key)
  return o and flat_at[o .. "/" .. key] or false
end

-- the text colours: only on flattened art (a light theme makes it light), and only the game's plain colours
for _, entry in ipairs(list) do
  local name, s, kind = entry.name, styles[entry.name], entry.kind
  local function font(dkey, token, art)
    if s[dkey] ~= nil then entry.fonts[#entry.fonts + 1] = { path = { engine(dkey) }, token = token, art = art } end
  end
  if flat and (kind == "button" or kind == "tab") then
    local art = art_flat(name, "default_graphical_set") and owner(name, "default_graphical_set")
    if art then
      local _, c = owner(name, "default_font_color")
      if black(c) then  -- (black text on the game's light buttons; white or no text: a meaning of its own)
        font("default_font_color", "btn_ink", art)
        if kind == "button" then
          for _, k in ipairs({ "hovered_font_color", "clicked_font_color" }) do
            if black(s[k]) then font(k, "btn_ink", art) end
          end
        end
      end
      if kind == "tab" and ink_of(s.selected_font_color) then font("selected_font_color", "caption", art) end
      if kind == "button" and black(s.selected_font_color) then font("selected_font_color", "btn_on_ink", art) end
    end
  elseif flat and (kind == "label" or kind == "check" or kind == "radio") and art_flat("frame", "graphical_set") then
    -- (on the window: flat when the game's window is. White or heading text only; hovered only when it is the same)
    local token = ink_of(s.font_color)
    if token then
      font("font_color", token, "frame")
      local _, c = owner(name, "font_color")
      if kind == "label" and s.hovered_font_color and near(rgba(s.hovered_font_color), rgba(c), 0.01) then
        font("hovered_font_color", token, "frame")
      end
    end
  elseif flat and kind == "switch" and art_flat("frame", "graphical_set") then
    local il = type(s.inactive_label) == "table" and s.inactive_label
    if il and ink_of(il.font_color) == "ink" then
      entry.fonts[#entry.fonts + 1] = { path = { "inactiveLabelStyle", "fontColor" }, token = "ink", art = "frame" }
    end
  end
  if entry.sets[1] == nil then entry.sets = nil end
  if entry.fonts[1] == nil then entry.fonts = nil end
end

-- pass 2: the flat tiles put in (owner sets only: a child without a set of its own is drawn with its parent's), and
-- every listed set's own hair of alpha
table.sort(mark_list)
local alpha = {}
local n = 0
for _, key in ipairs(mark_list) do
  n = n + 1
  if n % 8 == 0 then n = n + 1 end  -- (never a multiple of 0.0004)
  alpha[key] = 1 - n * 0.00005
end
local function marked(set, a)
  local b = base_of(set)
  if not b then return end
  local t = b.tint and rgba(b.tint) or { r = 1, g = 1, b = 1, a = 1 }
  b.tint = { r = t.r * a, g = t.g * a, b = t.b * a, a = t.a * a }
end
for _, p in ipairs(plan) do
  local holder = p[3] or p[1]
  holder[p[2]] = p[4]
end
local DATA_KEY = {}
for _, st in ipairs(BUTTON) do DATA_KEY[engine(st[1])] = st[1] end
for _, st in ipairs(TABLE) do DATA_KEY[engine(st[1])] = st[1] end
for _, st in ipairs(FRAME) do DATA_KEY[engine(st[1])] = st[1] end
local out = {}
for _, entry in ipairs(list) do
  local s = styles[entry.name]
  for _, st in ipairs(entry.sets or {}) do
    local a = alpha[st.mark]
    if st.path[1] == "contentFrame" then
      if type(s.tab_content_frame) == "table" and s.tab_content_frame.graphical_set then
        marked(s.tab_content_frame.graphical_set, a)
      end
    else
      marked(s[DATA_KEY[st.path[1]]], a)
    end
    st.mark = nil
  end
  if entry.sets or entry.fonts then
    out[#out + 1] = { name = entry.name, kind = entry.kind, sets = entry.sets, fonts = entry.fonts }
  end
end

data:extend({ { type = "mod-data", name = "fstd-game-styles", data = { styles = out, flat = flat,
  tileset = styles.default_tileset } } })
