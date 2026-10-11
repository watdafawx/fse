-- every frame, scroll pane, tab, button and label style of the game and of every mod (made last, so all of them are
-- there), for "colour the game's own windows": each with the theme token it follows. The control stage reads it
-- from the mod-data. Each named style keeps its own copy of its sprites, so all of them are listed, not just the
-- base ones.
--
-- With the startup setting fstd-flat-game, their plain 9-slice image sets are also drawn with fse-std's white tiles
-- (tinted in the game's own colours to start with), so a theme can make the game's windows any colour, light ones
-- too. Sets made of separate pieces (a frame open on one side, like the map view's) keep the game's art.

local themes = require("themes")
local styles = data.raw["gui-style"].default
local flat = settings.startup["fstd-flat-game"] and settings.startup["fstd-flat-game"].value

local SKIP = { "^fstd_", "red", "green", "blue", "yellow", "orange", "confirm", "technology", "tip_notice",
  "achievement", "_dirt", "invisible", "transparent", "highlight", "flib" }

local function skip(name)
  for _, p in ipairs(SKIP) do if name:find(p) then return true end end
  return false
end

-- a style's set at `key`, its own or its nearest parent's
local function set_of(s, key)
  while s do
    local v = s[key]
    if v ~= nil then return v end
    s = s.parent and styles[s.parent]
  end
end

-- a plain 9-slice set (a corner size, no separately given edges): what a flat tile can stand in for. Not a hollow
-- one: drawn "outer" without a centre of its own, it is a border around something that shows through (the map
-- view's frame_around_center)
local PIECES = { "top", "bottom", "left", "right", "left_top", "right_top", "left_bottom", "right_bottom" }
local function pieces(base)
  for _, k in ipairs(PIECES) do if base[k] ~= nil then return true end end
  return false
end
local function plain(set)
  if type(set) ~= "table" or next(set) == nil then return false end
  local base = set.base or set
  if type(base) ~= "table" then return false end
  if pieces(base) then return false end
  if not (base.corner_size or base.border) then return false end  -- (slots: border = 4)
  if base.draw_type == "outer" and base.center == nil then return false end
  if base.filename and base.filename ~= "__core__/graphics/gui-new.png" then return false end  -- (a mod's own art)
  return true
end

local FILE = "__fse-std__/graphics/theme.png"
local function tile(kind, col, shadow)
  local shape = themes.SHAPES.soft
  local t = themes.tint({ shape = "soft" }, "", col)
  return { base = { filename = FILE, corner_size = shape.corner, tint = t,
    position = { themes.KINDS[kind] * themes.STEP, shape.row * themes.STEP } }, shadow = shadow }
end

-- replaces a style's set with a tile when it is a plain one (its own or inherited: the copy is the style's own). A
-- set drawn once per cell (slot grids: overall_tiling_*) keeps its tiling and gets the outline tile in the slot colour.
-- a set made of separate pieces (a frame open on one side): each piece it has, cut from the tile
local function piece_tile(set, kind, col)
  local base = set.base or set
  local shape = themes.SHAPES.soft
  local x0, y0, c = themes.KINDS[kind] * themes.STEP, shape.row * themes.STEP, shape.corner
  local at = { left_top = { 0, 0, c, c }, top = { c, 0, 1, c }, right_top = { c + 1, 0, c, c },
    left = { 0, c, c, 1 }, center = { c, c, 1, 1 }, right = { c + 1, c, c, 1 },
    left_bottom = { 0, c + 1, c, c }, bottom = { c, c + 1, 1, c }, right_bottom = { c + 1, c + 1, c, c } }
  local new = { tint = themes.tint({ shape = "soft" }, "", col), draw_type = base.draw_type }
  for k, r in pairs(at) do
    if base[k] ~= nil then
      new[k] = { filename = FILE, position = { x0 + r[1], y0 + r[2] }, size = { r[3], r[4] } }
    end
  end
  return { base = new, shadow = set.base and set.shadow or nil }
end

local function flatten(s, key, kind, col)
  local set = set_of(s, key)
  local b0 = type(set) == "table" and next(set) ~= nil and (set.base or set)
  -- (pieces given one by one, or just a centre: statistics_scroll_pane)
  if type(b0) == "table" and (pieces(b0) or (b0.center and not b0.corner_size and not b0.border)) then
    local base = set.base or set
    if not base.filename or base.filename == "__core__/graphics/gui-new.png" then
      s[key] = piece_tile(set, kind, col)
    end
    return
  end
  if not plain(set) then return end
  local base = set.base or set
  local new = tile(kind, col, set.base and set.shadow or nil)
  if base.overall_tiling_horizontal_size or base.overall_tiling_vertical_size or base.custom_horizontal_tiling_sizes then
    new = tile("outline", themes.VANILLA.slot, set.base and set.shadow or nil)
    for k, v in pairs(base) do
      if k:find("tiling") or k:find("^overall") then new.base[k] = table.deepcopy(v) end
    end
  end
  s[key] = new
end

local CLICK = { { "default_graphical_set", "same" }, { "hovered_graphical_set", "lighter" },
  { "clicked_graphical_set", "darker" }, { "disabled_graphical_set", "faded" } }
local TAB = { { "default_graphical_set", "same" }, { "hovered_graphical_set", "lighter" },
  { "clicked_graphical_set", "darker" }, { "disabled_graphical_set", "faded" }, { "selected_graphical_set", "lighter" } }

local list = {}
for name, s in pairs(styles) do
  if type(s) == "table" and not skip(name) then
    local V = themes.VANILLA
    if s.type == "frame_style" then
      local token = "win"
      if name:find("deep") or name:find("slot") then token = "deep"
      elseif name:find("shallow") or name:find("subheader") or name:find("inner") then token = "inset" end
      list[#list + 1] = { name, "frame", token }
      if flat then
        flatten(s, "graphical_set", token == "win" and "panel" or "inset", V[token])
        flatten(s, "background_graphical_set", "flat", V[token])
      end
    elseif s.type == "scroll_pane_style" then
      list[#list + 1] = { name, "scroll", "deep" }
      if flat then
        flatten(s, "graphical_set", "inset", V.deep)
        flatten(s, "background_graphical_set", "flat", V.deep)
      end
    elseif s.type == "table_style" then  -- (rows, striped rows, slot grids behind a table)
      list[#list + 1] = { name, "table", "inset" }
      if flat then
        flatten(s, "background_graphical_set", "flat", V.slot)
        for _, k in ipairs({ "default_row_graphical_set", "odd_row_graphical_set", "even_row_graphical_set" }) do
          flatten(s, k, "flat", V.inset)
        end
        flatten(s, "hovered_graphical_set", "flat", themes.lighter(V.inset, 0.12))
        flatten(s, "selected_graphical_set", "flat", V.btn_on)
      end
    elseif s.type == "tabbed_pane_style" then  -- (its content frame is a sub-style of its own)
      list[#list + 1] = { name, "tabbed", "inset" }
      if flat and type(s.tab_content_frame) == "table" then
        flatten(s.tab_content_frame, "graphical_set", "inset", V.inset)
      end
    elseif s.type == "tab_style" then
      list[#list + 1] = { name, "tab", "btn" }
      if flat then
        for _, st in ipairs(TAB) do flatten(s, st[1], "button", themes.derive(V.btn, st[2])) end
      end
    elseif s.type == "label_style" then  -- (their text colour: in flat game windows, a light theme needs dark text)
      local heading = name:find("title") or name:find("caption") or name:find("heading")
      list[#list + 1] = { name, "label", heading and "caption" or "ink" }
    elseif s.type == "button_style" then
      local token = name:find("slot") and "slot" or "btn"
      list[#list + 1] = { name, "button", token }
      if flat then
        for _, st in ipairs(CLICK) do
          flatten(s, st[1], token == "slot" and "outline" or "button", themes.derive(V[token], st[2]))
        end
      end
    end
  end
end
table.sort(list, function(a, b) return a[1] < b[1] end)

data:extend({ { type = "mod-data", name = "fstd-game-styles", data = { styles = list, flat = flat and true or false } } })
