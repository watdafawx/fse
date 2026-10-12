-- every theme's styles: fstd_<theme>_<role> (themes.lua has the themes and the roles). A theme is switched by
-- giving elements another theme's style names, so all of them are made here; edited colours are written into
-- these styles' sprites while the game runs (control stage, with the fse loader).
--   data.lua: M.fonts(), M.roles(false); data-final-fixes.lua: M.roles(true) (the game styles adopt() themes, each
--   with a role's colours: made last, when flib's and every mod's styles are there)

local themes = require("themes")
local styles = data.raw["gui-style"].default
local FILE = "__fse-std__/graphics/theme.png"
local shadow = rawget(_G, "default_shadow")
local dirt = rawget(_G, "default_dirt")

local STYLE_TYPE = {
  frame = "frame_style", button = "button_style", textbox = "textbox_style", empty = "empty_widget_style",
  label = "label_style", checkbox = "checkbox_style", radiobutton = "radiobutton_style", slider = "slider_style",
  dropdown = "dropdown_style", scroll = "scroll_pane_style", list = "list_box_style", tabbed = "tabbed_pane_style",
  tab = "tab_style", progress = "progressbar_style",
}

-- a vanilla style's value at a path of keys, through each table's parents
local function field(t, key)
  while t do
    if t[key] ~= nil then return t[key] end
    t = t.parent and styles[t.parent]
  end
end
local function vanilla(name, path)
  local t = styles[name]
  for _, key in ipairs(path) do
    if type(t) ~= "table" then return nil end
    t = field(t, key)
  end
  return t
end

-- (the engine shares sprites that are equal: every theme's tints are set apart by a hair of alpha, so writing one
-- theme's colours never reaches another theme or the game's own styles)
local function tint(theme, token, col)
  local t = themes.tint(theme, token, col)
  return { r = t.r, g = t.g, b = t.b, a = t.a * (1 - theme.index * 0.0004) }
end

-- one image set: on vanilla, a copy of the game's own with a tint; on our tiles, a tinted tile
local function set(theme, r, st)
  local path, token, how = st[1], st[3], (theme.shape == "vanilla" and st.vanilla_how) or st[4]
  local col = tint(theme, token, themes.derive(themes.color(theme, nil, token), how))
  if theme.shape == "vanilla" then
    local src = vanilla(r.vanilla, path)
    if type(src) ~= "table" or next(src) == nil then return nil end  -- (bordered_frame: a border, no image set)
    local out = table.deepcopy(src)
    if not (out.base or out.shadow or out.glow) then out = { base = out } end  -- (a set given as just its base)
    if out.base then out.base.tint = col end
    return out
  end
  local shape = themes.SHAPES[st.small and "small" or theme.shape]
  local out = { base = { filename = FILE, corner_size = shape.corner, tint = col,
    position = { themes.KINDS[st.kind or "panel"] * themes.STEP, shape.row * themes.STEP } } }
  if r.type == "button" then out.shadow = dirt end
  return out
end

-- sets the value at a path of keys, the tables on the way made by `nest`
local function put(s, path, value)
  local t = s
  for i = 1, #path - 1 do t = t[path[i]] end
  t[path[#path]] = value
end

local function fonts(t, ink, sel)
  t.default_font_color = ink; t.hovered_font_color = ink; t.clicked_font_color = ink
  t.disabled_font_color = themes.faded(ink, 0.5)
  if sel then t.selected_font_color = sel; t.selected_hovered_font_color = sel; t.selected_clicked_font_color = sel end
end

local M = {}

-- the monospace fonts (Cascadia Mono, fonts/OFL.txt) mono themes use
function M.fonts()
data:extend({
  { type = "font", name = "fstd-mono", from = "fstd-mono", size = 14 },
  { type = "font", name = "fstd-mono-small", from = "fstd-mono", size = 12 },
  { type = "font", name = "fstd-mono-title", from = "fstd-mono", size = 17 },
  { type = "font", name = "fstd-mono-large", from = "fstd-mono", size = 20 },
})
end
local MONO = { title = "fstd-mono-title", caption = "fstd-mono-title", big = "fstd-mono-large",
  badge_text = "fstd-mono-small", tab = "fstd-mono-small", rtab = "fstd-mono-small" }  -- (tabs: names in fixed-width buttons)

-- a font without the black border the game gives some (count-font, default-game): "fstd-plain-<font>", made once
-- (nil: the font has none)
function M.borderless(name)
  local f = data.raw.font[name]
  if not (f and f.border) then return nil end
  local plain = "fstd-plain-" .. name
  if not data.raw.font[plain] then
    local copy = table.deepcopy(f)
    copy.name, copy.border, copy.border_color = plain, false, nil
    data:extend({ copy })
  end
  return plain
end

-- a checkbox's tick on our tiles: white, tinted (the game's is dark: lost on a dark box)
local function tick(col)
  return { filename = "__fse-std__/graphics/check.png", size = 28, tint = col }
end

-- the outline round a checkbox's or a radio button's box (its shadow layer, drawn just outside it): an unticked box
-- shows on a dark panel too
local function ring(theme, how)
  local sm = themes.SHAPES.small
  return { filename = FILE, corner_size = sm.corner, draw_type = "outer",
    position = { themes.KINDS.ring * themes.STEP, sm.row * themes.STEP },
    tint = tint(theme, "ink_dim", themes.derive(theme.tokens.ink_dim, how)) }
end

-- a 1 px outline over an element's own edge (its glow layer, drawn inside it: an outer one is cut off by a tight
-- parent): an empty slot or text field shows on a dark panel
local function edge(theme, how)
  local sm = themes.SHAPES.small
  return { filename = FILE, corner_size = sm.corner, draw_type = "inner",
    position = { themes.KINDS.edge * themes.STEP, sm.row * themes.STEP },
    tint = tint(theme, "ink_dim", themes.derive(theme.tokens.ink_dim, how)) }
end

-- a monospace font about as big as a game font
local function mono_like(font)
  local f = data.raw.font[font]
  local size = f and f.size or 14
  if size <= 12 then return "fstd-mono-small" end
  if size <= 15 then return "fstd-mono" end
  if size <= 18 then return "fstd-mono-title" end
  return "fstd-mono-large"
end

-- one theme's style for a role. A variant (r.exact: adopt()'s) is the game's style with the role's colours only:
-- none of the role's sizes, paddings and flows
local function make(theme, role, r)
  local tk = theme.tokens
  local base, lay = r.base or role, not r.exact
  local s = { type = STYLE_TYPE[r.type], parent = r.vanilla }
  -- nested sub-styles, outer ones first
  local nests = {}
  for key, n in pairs(r.nest or {}) do nests[#nests + 1] = { key = key, n = n } end
  table.sort(nests, function(a, b) return #a.key < #b.key end)
  for _, n in ipairs(nests) do
    local path = {}
    for k in n.key:gmatch("[^.]+") do path[#path + 1] = k end
    put(s, path, { type = n.n.type, parent = n.n.parent })
  end
  local ink, sel = r.ink and tk[r.ink], r.sel_ink and tk[r.sel_ink]
  if r.type == "frame" and lay then
    s.padding = (role == "deep") and 0 or theme.pad
    s.vertical_flow_style = { type = "vertical_flow_style", vertical_spacing = theme.gap }
    s.horizontal_flow_style = { type = "horizontal_flow_style", horizontal_spacing = theme.gap }
    if role == "window" then s.top_padding = math.max(2, theme.pad - 4) end
    if role == "badge" then
      s.padding = 0; s.left_padding = 6; s.right_padding = 6
      s.horizontal_flow_style.vertical_align = "center"
    end
  elseif r.type == "button" then
    fonts(s, ink, sel)
    if lay and (role == "tab" or role == "rtab") then s.minimal_width = 0; s.left_padding = 10; s.right_padding = 10 end
    if lay and role == "tool" then s.size = 28; s.padding = 0 end
    if lay and role == "slot" then s.size = 40 end
  elseif r.type == "textbox" or r.type == "label" or r.type == "checkbox" or r.type == "radiobutton" then
    s.font_color = ink
    if r.font then s.font = r.font end
    if r.type == "checkbox" and theme.shape ~= "vanilla" then
      s.checkmark = tick(tint(theme, "field_ink", tk.field_ink))
      s.disabled_checkmark = tick(tint(theme, "field_ink", themes.faded(tk.field_ink, 0.5)))
    end
  elseif r.type == "empty" and not lay then  -- (the game's sizes)
  elseif r.type == "empty" then
    if role == "drag" then s.height = 24; s.horizontally_stretchable = "on" end
    if role == "line" then s.height = 2; s.horizontally_stretchable = "on"; s.top_margin = 2; s.bottom_margin = 2 end
    if role == "bar" or role == "bar2" then s.width = 10 end
  elseif r.type == "scroll" then  -- (the bars and thumbs keep the game's sizes)
    local v, h = s.vertical_scrollbar_style, s.horizontal_scrollbar_style
    v.width = 12; v.thumb_button_style.width = 10; v.thumb_button_style.minimal_height = 16
    h.height = 12; h.thumb_button_style.height = 10; h.thumb_button_style.minimal_width = 16
  elseif r.type == "dropdown" then
    fonts(s.button_style, tk.btn_ink, tk.btn_on_ink)
    -- (the game's arrow is black: on a dark theme's buttons it is drawn inverted, light)
    local icon = vanilla("dropdown", { "icon" })
    if type(icon) == "table" and not themes.is_light(tk.btn) then
      s.icon = table.deepcopy(icon)
      s.icon.invert_colors = true
    end
  elseif r.type == "list" then
    fonts(s.item_style, ink, sel)
  elseif r.type == "tab" then
    s.default_font_color = ink; s.selected_font_color = sel; s.disabled_font_color = themes.faded(ink, 0.5)
  elseif r.type == "progress" then
    s.color = tk.btn_on
    if lay then s.bar_width = 10 end
  end
  for i, st in ipairs(themes.sets(role)) do
    local g = set(theme, r, st)
    if g and (r.type == "checkbox" or r.type == "radiobutton") and theme.shape ~= "vanilla" then
      g.shadow = ring(theme, i == 4 and "faded" or "same")  -- (as themes.lua's extra: the 4th is disabled)
    elseif g and ((base == "slot" or base == "field") and not theme.light or theme.edged and themes.EDGED[base])
      and theme.shape ~= "vanilla" then
      -- (an empty one shows on a dark panel. A text box draws no glow, and its shadow under its base: there its
      -- colour is the shadow, drawn inside it, the outline its base; themes.lua's dark_layer)
      local e = edge(theme, st[4] == "faded" and "faded" or "same")
      if r.type == "textbox" then
        g.base.draw_type = "inner"
        g.shadow, g.base = g.base, e
      else
        g.glow = e
      end
    end
    if g then put(s, st[1], g) end
  end
  if (base == "close" or base == "close_on") and theme.shape ~= "vanilla" then
    -- (the game inverts a title bar button's icon when hovered, for its light hover: ours is the accent, so only
    -- when the icon would vanish on it. The icon is dark on a light theme's window: theme.lua's icons)
    s.invert_colors_of_picture_when_hovered_or_toggled = base == "close"
      and (not theme.light) == themes.is_light(tk.btn_on)
  end
  if base == "row" then  -- (unselected rows show the list through: only hovered and selected ones are drawn)
    s.default_graphical_set = { base = { type = "none" } }
  elseif base == "list" then
    s.item_style.default_graphical_set = { base = { type = "none" } }
  end
  if (base == "list" or base == "scroll") and theme.shape ~= "vanilla" then
    -- (the game's list box draws dark row stripes behind its rows: bars on our tiles, black ones on a light theme)
    local sp = base == "list" and s.scroll_pane_style or s
    if base == "list" or vanilla(r.vanilla, { "background_graphical_set" }) then
      sp.background_graphical_set = { base = { type = "none" } }
    end
  end
  if r.type == "frame" and not lay then
    -- (the game's frame draws its caption and the bar beside it itself: in the theme's colours too)
    local ts = vanilla(r.vanilla, { "title_style" })
    if type(ts) == "table" then
      s.title_style = table.deepcopy(ts)
      s.title_style.font_color = tk[base == "window" and "title" or "caption"]  -- (its font the game's)
    end
    local hf = vanilla(r.vanilla, { "use_header_filler" }) and vanilla(r.vanilla, { "header_filler_style" })
    if type(hf) == "table" then
      s.header_filler_style = table.deepcopy(hf)
      s.header_filler_style.graphical_set = set(theme, themes.ROLES.drag, themes.ROLES.drag.sets[1])
    end
  end
  if (base == "window" or base == "toast") and s.graphical_set then
    s.graphical_set.shadow = shadow
    if theme.glass then
      s.graphical_set.base.background_blur = true
      s.graphical_set.base.background_blur_sigma = 6
    end
  end
  local f
  if theme.mono then
    f = MONO[base] or "fstd-mono"
    if not lay then  -- (a game style: headings keep the game's font, the rest a monospace one of its size)
      local vf = vanilla(r.vanilla, (r.type == "dropdown" and { "button_style", "font" })
        or (r.type == "list" and { "item_style", "font" }) or { "font" })
      if base == "title" or base == "caption" or base == "big" then f = nil
      elseif type(vf) == "string" and (vf:find("bold") or vf:find("heading") or vf:find("title") or vf:find("count")) then
        f = nil  -- (a weight or a look of its own: a monospace font would lose it)
      elseif type(vf) == "string" then f = mono_like(vf) end
    end
  end
  if theme.light and not (theme.mono and f) then
    -- (a font the game draws with a black border, count-font: a blot round dark text on a light theme)
    local vf = vanilla(r.vanilla, (r.type == "dropdown" and { "button_style", "font" })
      or (r.type == "list" and { "item_style", "font" }) or { "font" })
    if type(vf) == "string" and (r.type == "label" or r.type == "button") then
      local plain = M.borderless(vf)
      if plain then s.font = plain end
    end
  end
  if theme.mono and f then
    if r.type == "label" or r.type == "button" or r.type == "textbox" or r.type == "checkbox"
      or r.type == "radiobutton" or r.type == "tab" then
      s.font = f
    elseif r.type == "dropdown" then
      s.button_style.font = f
    elseif r.type == "list" then
      s.item_style.font = f
    end
  end
  return s
end

--- every theme's styles of the roles (exact: adopt()'s variants, put into the roles first, else the others)
function M.roles(exact)
  if exact then themes.add_variants(function(name) return styles[name] ~= nil end) end
  for _, theme in ipairs(themes.list) do
    for role, r in pairs(themes.ROLES) do
      if (r.exact or false) == exact then styles["fstd_" .. theme.name .. "_" .. role] = make(theme, role, r) end
    end
  end
end

return M
