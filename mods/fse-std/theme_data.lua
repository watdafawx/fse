-- every theme's styles: fstd_<theme>_<role> (themes.lua has the themes and the roles). A theme is switched by
-- giving elements another theme's style names, so all of them are made here; edited colours are written into
-- these styles' sprites while the game runs (control stage, with the fse loader).

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
  local path, token, how = st[1], st[3], st[4]
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

-- the monospace fonts (Cascadia Mono, fonts/OFL.txt) mono themes use
data:extend({
  { type = "font", name = "fstd-mono", from = "fstd-mono", size = 14 },
  { type = "font", name = "fstd-mono-small", from = "fstd-mono", size = 12 },
  { type = "font", name = "fstd-mono-title", from = "fstd-mono", size = 17 },
  { type = "font", name = "fstd-mono-large", from = "fstd-mono", size = 20 },
})
local MONO = { title = "fstd-mono-title", caption = "fstd-mono-title", big = "fstd-mono-large",
  badge_text = "fstd-mono-small", tab = "fstd-mono-small", rtab = "fstd-mono-small" }  -- (tabs: names in fixed-width buttons)

for _, theme in ipairs(themes.list) do
  local tk = theme.tokens
  for role, r in pairs(themes.ROLES) do
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
    if r.type == "frame" then
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
      if role == "tab" or role == "rtab" then s.minimal_width = 0; s.left_padding = 10; s.right_padding = 10 end
      if role == "tool" then s.size = 28; s.padding = 0 end
      if role == "slot" then s.size = 40 end
    elseif r.type == "textbox" or r.type == "label" or r.type == "checkbox" or r.type == "radiobutton" then
      s.font_color = ink
      if r.font then s.font = r.font end
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
    elseif r.type == "list" then
      fonts(s.item_style, ink, sel)
    elseif r.type == "tab" then
      s.default_font_color = ink; s.selected_font_color = sel; s.disabled_font_color = themes.faded(ink, 0.5)
    elseif r.type == "progress" then
      s.color = tk.btn_on
      s.bar_width = 10
    end
    for _, st in ipairs(themes.sets(role)) do
      local g = set(theme, r, st)
      if g then put(s, st[1], g) end
    end
    if role == "row" then  -- (unselected rows show the list through: only hovered and selected ones are drawn)
      s.default_graphical_set = { base = { type = "none" } }
    end
    if (role == "window" or role == "toast") and s.graphical_set then
      s.graphical_set.shadow = shadow
      if theme.glass then
        s.graphical_set.base.background_blur = true
        s.graphical_set.base.background_blur_sigma = 6
      end
    end
    if theme.mono then
      local f = MONO[role] or "fstd-mono"
      if r.type == "label" or r.type == "button" or r.type == "textbox" or r.type == "checkbox"
        or r.type == "radiobutton" or r.type == "tab" then
        s.font = f
      elseif r.type == "dropdown" then
        s.button_style.font = f
      elseif r.type == "list" then
        s.item_style.font = f
      end
    end
    styles["fstd_" .. theme.name .. "_" .. role] = s
  end
end
