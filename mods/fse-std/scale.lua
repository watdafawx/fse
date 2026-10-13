-- Window scale, control stage: an element's sizes, paddings, margins, spacing and font at a scale of its window's
-- (on top of the game's display_scale). theme.lua decides each window's scale; this file writes it into elements.
--
-- Every element keeps its design values (GUI units at 100 %): what its style gives (fstd-layout, data stage), what a
-- tweak or its mod set. Scaled elements carry a mark in their tags, fstd_sc = { f = scale, s = style name, b =
-- design values }, so scaling again (another scale, or the same after a mod changed something) starts from the
-- design values, never from scaled ones. A value that no longer reads as the mark's scaled one was set by its mod
-- since (in design units): it becomes the design value. At 100 % an element without a mark is never touched.

local themes = require("__fse-std__/themes")

local S = {}

-- the keys scaled, by element type (Lua reads these back, except a frame's paddings: those come from fstd-layout)
local SIZE = { "minimal_width", "maximal_width", "minimal_height", "maximal_height", "natural_width", "natural_height",
  "top_padding", "right_padding", "bottom_padding", "left_padding", "top_margin", "right_margin", "bottom_margin",
  "left_margin" }
local SPACING = { "horizontal_spacing", "vertical_spacing" }
local CELL = { "top_cell_padding", "right_cell_padding", "bottom_cell_padding", "left_cell_padding" }
local FONTED = { label = true, button = true, textfield = true, ["text-box"] = true, checkbox = true,
  radiobutton = true, tab = true }
S.FONTED = FONTED

local by_type = {}
local function keys_of(t)
  local k = by_type[t]
  if k then return k end
  k = { table.unpack(SIZE) }
  if t == "flow" or t == "table" then for _, x in ipairs(SPACING) do k[#k + 1] = x end end
  if t == "table" then for _, x in ipairs(CELL) do k[#k + 1] = x end end
  if t == "progressbar" then k[#k + 1] = "bar_width" end
  by_type[t] = k
  return k
end
S.keys_of = keys_of

-- every key a design table (a tweak, theme.style) may give that is a size
local SCALES = {}
for _, k in ipairs(SIZE) do SCALES[k] = true end
for _, k in ipairs(SPACING) do SCALES[k] = true end
for _, k in ipairs(CELL) do SCALES[k] = true end
for _, k in ipairs({ "width", "height", "size", "padding", "margin", "cell_padding", "natural_size", "bar_width" }) do
  SCALES[k] = true
end
S.SCALES = SCALES

local function index(t, k) return t[k] end
local function assign(t, k, v) t[k] = v end
S.index, S.assign = index, assign

--- n GUI units at scale f (rounded; negative margins too)
function S.px(n, f)
  if type(n) == "table" then
    local out = {}
    for i, v in pairs(n) do out[i] = S.px(v, f) end
    return out
  end
  if type(n) ~= "number" then return n end
  if n >= 0 then return math.floor(n * f + 0.5) end
  return -math.floor(-n * f + 0.5)
end
local px = S.px

function S.pct(f) return math.floor(f * 100 + 0.5) end

--- the largest step at or under f (the smallest step at least)
function S.snap(f)
  local steps = themes.SCALE_STEPS
  local best = steps[1]
  for _, s in ipairs(steps) do
    if s <= f * 100 + 0.001 then best = s end
  end
  return best / 100
end

-- a style's design layout (data stage: resolved through its parents); a scaled frame copy has its base's
local layout_md, layout = nil, {}
function S.layout(name)
  local l = layout[name]
  if l ~= nil then return l end
  if layout_md == nil then layout_md = prototypes.mod_data["fstd-layout"] or false end
  local base = name:gsub("_x%d+$", "")
  local ok, v = false, nil
  if layout_md then ok, v = pcall(layout_md.get, base) end
  l = ok and type(v) == "table" and v or false
  layout[name] = l
  return l
end

-- fonts: the copy of a font at a step (data stage), or the font itself
local fonts = {}
function S.font(base, f)
  local p = S.pct(f)
  if p == 100 or type(base) ~= "string" then return base end
  local n = "fstd-s" .. p .. "-" .. base
  local ok = fonts[n]
  if ok == nil then
    local o, v = pcall(function() return prototypes.font[n] end)
    ok = o and v ~= nil
    fonts[n] = ok
  end
  return ok and n or base
end
function S.unfont(n)
  return type(n) == "string" and (n:match("^fstd%-s%d+%-(.+)$") or n) or n
end

-- a tweak / design table as the keys above (width -> minimal and maximal width, padding -> its four sides, ...)
local SIDES = { "top", "right", "bottom", "left" }
local function two(v)
  if type(v) == "table" then return v[1], v[2] end
  return v, v
end
local function four(v)
  if type(v) ~= "table" then return v, v, v, v end
  if #v == 2 then return v[1], v[2], v[1], v[2] end
  return v[1], v[2], v[3], v[4]
end
function S.norm(t)
  if type(t) ~= "table" then return nil end
  local o = {}
  if t.size ~= nil then
    local w, h = two(t.size)
    o.minimal_width, o.maximal_width, o.minimal_height, o.maximal_height = w, w, h, h
  end
  if t.width ~= nil then o.minimal_width, o.maximal_width = t.width, t.width end
  if t.height ~= nil then o.minimal_height, o.maximal_height = t.height, t.height end
  if t.natural_size ~= nil then o.natural_width, o.natural_height = two(t.natural_size) end
  for _, what in ipairs({ "padding", "margin", "cell_padding" }) do
    if t[what] ~= nil then
      local v = { four(t[what]) }
      for i, side in ipairs(SIDES) do o[side .. "_" .. what] = v[i] end
    end
  end
  for _, list in ipairs({ SIZE, SPACING, CELL, { "bar_width" } }) do
    for _, k in ipairs(list) do
      if type(t[k]) == "number" then o[k] = t[k] end
    end
  end
  if t.font ~= nil then o.font = t.font end
  return o
end

local function sane(v) return type(v) == "number" and v > -20000 and v < 20000 end

--- scales one element to f. restyle(el, f, force) -> true: called for a themed element first, to give it the style
--- of its role at that scale (a frame's flows; force: again, a scaled element back at 100 %); it returns true when it
--- set the style (the values went back to the style's). Writes only what differs; the mark goes at 100 %.
function S.scale_el(el, f, restyle)
  local tags = el.tags
  local mk = tags.fstd_sc
  if f == 1 and not mk then return false end
  local st = el.style
  local sname = st.name
  local same = mk and mk.s == sname
  local mb = same and mk.b or {}
  local themed = tags.fstd_role and sname:sub(1, 5) == "fstd_"
  local tw = themed and S.norm(tags.fstd_tweak) or nil
  local L = S.layout(sname) or {}
  local keys = keys_of(el.type)
  -- (LuaStyle reads back only what Lua set: a value from the style itself reads nil, and comes from fstd-layout.
  -- Those are marked "from the style" (ml): back at 100 % a themed element just gets its style again)
  local ml = same and mk.l or {}
  local base, cur, from_style = {}, {}, {}
  for _, k in ipairs(keys) do
    local ok, v = pcall(index, st, k)
    if not ok then v = nil end
    if v ~= nil and not sane(v) then v = false end  -- (an unset maximum reading as a huge number: left alone)
    cur[k] = v
    local b, fs
    if v == false then b = nil
    elseif v == nil then  -- (the style's, or written by us and not read back: a frame's paddings)
      if same and mb[k] ~= nil then b, fs = mb[k], ml[k]
      elseif tw and tw[k] ~= nil then b = tw[k]
      else b, fs = L[k], true end
    elseif same and mb[k] ~= nil and v == px(mb[k], mk.f) then b, fs = mb[k], ml[k]
    elseif same and mb[k] == nil and v == 0 then b = nil
    else b = v end  -- (set by Lua: its mod's or a tweak, in design units)
    if b == 0 then b = nil end
    base[k], from_style[k] = b, b and fs or nil
  end
  if FONTED[el.type] then
    local ok, v = pcall(index, st, "font")
    if not ok then v = nil end
    cur.font = v
    if type(v) == "string" then
      if same and mb.font and v == S.font(mb.font, mk.f) then base.font, from_style.font = mb.font, ml.font
      else base.font = S.unfont(v) end
    elseif tw and tw.font then base.font = tw.font
    else base.font, from_style.font = L.font, L.font and true or nil end
  end
  -- (a themed element: its role's style for this scale; back at 100 % its style again, as it was built)
  local swapped = themed and restyle and restyle(el, f, f == 1 and mk ~= nil) or false
  if swapped then st = el.style end
  local wrote = false
  for _, k in ipairs(keys) do
    local b = base[k]
    if b and not (swapped and f == 1 and from_style[k]) then
      local w = px(b, f)
      if swapped or cur[k] ~= w then pcall(assign, st, k, w); wrote = true end
    end
  end
  if base.font and not (swapped and f == 1 and from_style.font) then
    local w = S.font(base.font, f)
    if swapped or cur.font ~= w then pcall(assign, st, "font", w); wrote = true end
  end
  -- the mark (none at 100 %)
  if f == 1 then
    if mk then tags.fstd_sc = nil; el.tags = tags end
  else
    local changed = wrote or not same or mk.f ~= f
    if not changed then
      for k, v in pairs(base) do if mb[k] ~= v or ml[k] ~= from_style[k] then changed = true break end end
      for k in pairs(mb) do if base[k] == nil then changed = true break end end
    end
    if changed then
      tags.fstd_sc = { f = f, s = el.style.name, b = base, l = next(from_style) and from_style or nil }
      el.tags = tags
    end
  end
  return wrote
end

--- sets design values (GUI units at 100 %) on an element at scale f: written scaled, kept in its mark. t as a tweak
--- (width, size, padding, ...). Values that aren't sizes go as they are.
function S.set(el, t, f, restyle)
  local tags = el.tags
  local mk = tags.fstd_sc
  local st = el.style
  if f == 1 and not mk then
    for k, v in pairs(t) do pcall(assign, st, k, v) end
    return
  end
  if not mk then  -- (a fresh element: written as given, then all of it scaled)
    for k, v in pairs(t) do pcall(assign, st, k, v) end
    S.scale_el(el, f, restyle)
    return
  end
  local n = S.norm(t)
  for k, v in pairs(n) do
    if k == "font" then mk.b.font = S.unfont(v) elseif v ~= 0 then mk.b[k] = v else mk.b[k] = nil end
    if mk.l then mk.l[k] = nil end  -- (set by Lua now, not the style's)
  end
  mk.s = st.name
  tags.fstd_sc = mk
  el.tags = tags
  for k, v in pairs(t) do
    if k == "font" then pcall(assign, st, k, S.font(S.unfont(v), f))
    elseif SCALES[k] then pcall(assign, st, k, px(v, f))
    else pcall(assign, st, k, v) end
  end
end

return S
