-- Window scale, data stage (data-final-fixes.lua, last): what the control stage (scale.lua) needs to draw our windows
-- bigger or smaller than the game's GUI scale.
--  * fonts: a copy of every font a GUI style uses (and fse-std's own) at each scale step: "fstd-s150-default-bold"
--  * frame styles: each frame role's style of every theme at each step, its flows' spacing scaled ("<style>_x150"):
--    Lua can set a frame's paddings and sizes, not the spacing of the flow inside it
--  * mod-data "fstd-layout": every GUI style's sizes, paddings, margins, spacing and font, resolved through its
--    parents (Lua can't read a frame's paddings back; the control stage scales from these)

local themes = require("themes")
local styles = data.raw["gui-style"].default
local STEPS = themes.SCALE_STEPS

-- (a style without a parent inherits its type's default style: "button_style" -> "button")
local function parent_of(name)
  local s = styles[name]
  if type(s) ~= "table" then return nil end
  if s.parent then return s.parent end
  local d = type(s.type) == "string" and s.type:gsub("_style$", "")
  if d and d ~= name and type(styles[d]) == "table" then return d end
end

local function chain(name)
  local out, n, depth = {}, name, 0
  while n and depth < 50 and type(styles[n]) == "table" do
    out[#out + 1] = styles[n]
    n, depth = parent_of(n), depth + 1
  end
  return out
end

local function two(v)
  if type(v) == "table" then return v[1] or v.width, v[2] or v.height end
  return v, v
end
local function four(v)
  if type(v) ~= "table" then return v, v, v, v end
  if #v == 2 then return v[1], v[2], v[1], v[2] end
  return v[1], v[2], v[3], v[4]
end
local SIDES = { "top", "right", "bottom", "left" }
local FLOWS = { horizontal_flow_style = true, vertical_flow_style = true, table_style = true, flow_style = true }

-- one style's own layout values over what its parents gave (out)
local function over(s, out)
  if s.size then
    local w, h = two(s.size)
    out.minimal_width, out.maximal_width, out.minimal_height, out.maximal_height = w, w, h, h
  end
  if s.width then out.minimal_width, out.maximal_width = s.width, s.width end
  if s.height then out.minimal_height, out.maximal_height = s.height, s.height end
  if s.natural_size then out.natural_width, out.natural_height = two(s.natural_size) end
  for _, k in ipairs({ "minimal_width", "maximal_width", "minimal_height", "maximal_height", "natural_width",
    "natural_height", "bar_width" }) do
    if s[k] ~= nil then out[k] = s[k] end
  end
  for _, what in ipairs({ "padding", "margin", "cell_padding" }) do
    if s[what] ~= nil then
      local v = { four(s[what]) }
      for i, side in ipairs(SIDES) do out[side .. "_" .. what] = v[i] end
    end
    for _, side in ipairs(SIDES) do
      local k = side .. "_" .. what
      if s[k] ~= nil then out[k] = s[k] end
    end
  end
  if FLOWS[s.type] then
    if s.horizontal_spacing ~= nil then out.horizontal_spacing = s.horizontal_spacing end
    if s.vertical_spacing ~= nil then out.vertical_spacing = s.vertical_spacing end
  end
  if type(s.font) == "string" then out.font = s.font end
end

local function resolve(name)
  local list = chain(name)
  local out = {}
  for i = #list, 1, -1 do over(list[i], out) end
  for k, v in pairs(out) do
    if type(v) ~= "string" and (type(v) ~= "number" or v == 0) then out[k] = nil end
  end
  return next(out) and out or nil
end

-- a frame style's nested flow style as it is drawn (the nearest one through its parents), a copy
local function nested(name, key)
  for _, s in ipairs(chain(name)) do
    if type(s[key]) == "table" then return table.deepcopy(s[key]) end
  end
end
local function flow_spacing(flow, key)
  local v = flow and flow[key]
  local p = flow and flow.parent
  local depth = 0
  while v == nil and p and styles[p] and depth < 20 do
    v = styles[p][key]
    p, depth = parent_of(p), depth + 1
  end
  if v == nil then  -- (the engine's default flow)
    local d = styles[key == "vertical_spacing" and "vertical_flow" or "horizontal_flow"]
    v = d and d[key]
  end
  return v
end

-- the layout table (before the scaled copies are made: they aren't listed, the control stage strips "_x150")
local layout = {}
local names = {}
for name, s in pairs(styles) do
  if type(s) == "table" and type(s.type) == "string" then names[#names + 1] = name end
end
table.sort(names)
for _, name in ipairs(names) do layout[name] = resolve(name) end

-- every theme's frame role styles at each scale step: the flows' spacing scaled
local new = {}
for _, theme in ipairs(themes.list) do
  for role, r in pairs(themes.ROLES) do
    local base = "fstd_" .. theme.name .. "_" .. role
    if r.type == "frame" and styles[base] then
      local vf, hf = nested(base, "vertical_flow_style"), nested(base, "horizontal_flow_style")
      local vs, hs = flow_spacing(vf, "vertical_spacing") or 0, flow_spacing(hf, "horizontal_spacing") or 0
      for _, step in ipairs(STEPS) do
        if step ~= 100 then
          local c = { type = "frame_style", parent = base }
          c.vertical_flow_style = vf and table.deepcopy(vf) or { type = "vertical_flow_style" }
          c.vertical_flow_style.vertical_spacing = math.floor(vs * step / 100 + 0.5)
          c.horizontal_flow_style = hf and table.deepcopy(hf) or { type = "horizontal_flow_style" }
          c.horizontal_flow_style.horizontal_spacing = math.floor(hs * step / 100 + 0.5)
          new[base .. "_x" .. step] = c
        end
      end
    end
  end
end
-- drop-downs: their button's font (and their list's) at each step
local function font_of(t)
  if type(t) ~= "table" then return nil end
  if type(t.font) == "string" then return t.font end
  local p, depth = t.parent, 0
  while p and styles[p] and depth < 20 do
    if type(styles[p].font) == "string" then return styles[p].font end
    p, depth = parent_of(p), depth + 1
  end
end
for _, theme in ipairs(themes.list) do
  for role, r in pairs(themes.ROLES) do
    local base = "fstd_" .. theme.name .. "_" .. role
    if r.type == "dropdown" and styles[base] then
      local bs = nested(base, "button_style") or { type = "button_style", parent = "dropdown_button" }
      local bf = font_of(bs) or font_of(styles.dropdown_button) or "default"
      local ls = nested(base, "list_box_style")
      local item = ls and type(ls.item_style) == "table" and ls.item_style or { type = "button_style",
        parent = "list_box_item" }
      local lf = font_of(item) or font_of(styles.list_box_item) or "default"
      for _, step in ipairs(STEPS) do
        if step ~= 100 then
          local c = { type = "dropdown_style", parent = base }
          c.button_style = table.deepcopy(bs)
          c.button_style.font = "fstd-s" .. step .. "-" .. bf
          c.list_box_style = ls and table.deepcopy(ls) or { type = "list_box_style" }
          c.list_box_style.item_style = table.deepcopy(item)
          c.list_box_style.item_style.font = "fstd-s" .. step .. "-" .. lf
          new[base .. "_x" .. step] = c
        end
      end
    end
  end
end
for name, c in pairs(new) do styles[name] = c end

-- fonts: every font a style names (nested ones too), the game's usual ones and fse-std's, at each step
local used = {}
local function scan(t, depth)
  for k, v in pairs(t) do
    if k == "font" and type(v) == "string" then used[v] = true
    elseif type(v) == "table" and depth < 6 then scan(v, depth + 1) end
  end
end
for _, name in ipairs(names) do scan(styles[name], 0) end
for _, n in ipairs({ "default", "default-semibold", "default-bold", "default-small", "default-small-semibold",
  "default-small-bold", "default-large", "default-large-semibold", "default-large-bold", "default-listbox",
  "default-game", "heading-1", "heading-2", "heading-3", "count-font" }) do used[n] = true end
for name in pairs(data.raw.font) do
  if name:sub(1, 5) == "fstd-" then used[name] = true end
end
local fonts = {}
for name in pairs(used) do
  local f = data.raw.font[name]
  if f and not name:find("^fstd%-s%d+%-") and type(f.size) == "number" then
    for _, step in ipairs(STEPS) do
      if step ~= 100 then
        local c = table.deepcopy(f)
        c.name = "fstd-s" .. step .. "-" .. name
        c.size = math.max(4, math.floor(f.size * step / 100 + 0.5))
        if type(c.spacing) == "number" then c.spacing = c.spacing * step / 100 end
        fonts[#fonts + 1] = c
      end
    end
  end
end
data:extend(fonts)

data:extend({ { type = "mod-data", name = "fstd-layout", data = layout } })
