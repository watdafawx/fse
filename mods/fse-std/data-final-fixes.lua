-- every frame and button style of the game and of every mod (made last, so all of them are there), for "colour the
-- game's own windows": each with the theme token it follows. The control stage reads it from the mod-data.
-- Each named style keeps its own copy of its sprites, so all of them are listed, not just the base ones.
--
-- With the startup setting fstd-flat-game, those styles are also drawn with fse-std's white tiles (tinted in the
-- game's own colours to start with), so a theme can make the game's windows any colour, light ones too.

local themes = require("themes")
local styles = data.raw["gui-style"].default
local flat = settings.startup["fstd-flat-game"] and settings.startup["fstd-flat-game"].value

local SKIP = { "^fstd_", "red", "green", "blue", "yellow", "orange", "confirm", "technology", "tip_notice",
  "achievement", "_dirt", "invisible", "transparent", "empty", "highlight", "flib" }

local function skip(name)
  for _, p in ipairs(SKIP) do if name:find(p) then return true end end
  return false
end

-- a style's own set or its nearest parent's: does it draw anything?
local function has_set(s, key)
  while s do
    local v = s[key]
    if v ~= nil then return type(v) == "table" and next(v) ~= nil end
    s = s.parent and styles[s.parent]
  end
  return false
end

local FILE = "__fse-std__/graphics/theme.png"
local function tile(kind, col, shadow)
  local shape = themes.SHAPES.soft
  local t = themes.tint({ shape = "soft" }, "", col)
  return { base = { filename = FILE, corner_size = shape.corner, tint = t,
    position = { themes.KINDS[kind] * themes.STEP, shape.row * themes.STEP } }, shadow = shadow }
end

local BUTTON_SETS = { { "default_graphical_set", "same" }, { "hovered_graphical_set", "lighter" },
  { "clicked_graphical_set", "darker" }, { "disabled_graphical_set", "faded" } }

local list = {}
for name, s in pairs(styles) do
  if type(s) == "table" and not skip(name) then
    if s.type == "frame_style" then
      local token = "win"
      if name:find("deep") or name:find("slot") then token = "deep"
      elseif name:find("shallow") or name:find("subheader") or name:find("inner") then token = "inset" end
      list[#list + 1] = { name, "frame", token }
      if flat and has_set(s, "graphical_set") then
        local shadow = type(s.graphical_set) == "table" and s.graphical_set.shadow or nil
        s.graphical_set = tile(token == "win" and "panel" or "inset", themes.VANILLA[token], shadow)
      end
    elseif s.type == "label_style" then  -- (their text colour: a light theme needs dark text)
      local heading = name:find("title") or name:find("caption") or name:find("heading")
      list[#list + 1] = { name, "label", heading and "caption" or "ink" }
    elseif s.type == "button_style" then
      local token = name:find("slot") and "slot" or "btn"
      list[#list + 1] = { name, "button", token }
      if flat and has_set(s, "default_graphical_set") then
        local kind = token == "slot" and "outline" or "button"
        for _, st in ipairs(BUTTON_SETS) do
          s[st[1]] = tile(kind, themes.derive(themes.VANILLA[token], st[2]))
        end
      end
    end
  end
end
table.sort(list, function(a, b) return a[1] < b[1] end)

data:extend({ { type = "mod-data", name = "fstd-game-styles", data = { styles = list, flat = flat and true or false } } })
