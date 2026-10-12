-- Drawing over the GUI, with the fse loader's draw plugin: line charts inside a themed panel, glows around a window
-- that cross its edge. Mods register elements through the "fse-std" remote interface (theme.graph, theme.glow);
-- that is game state, the same on every peer. Drawing is this peer's own: each few ticks the element's place on
-- screen is read from the engine (its widget's location, plus every parent's) and the shapes are set as a screen
-- layer of the draw plugin.

local themes = require("themes")

local M = {}
local last = nil  -- (this peer's own: the shapes sent last, to send only changes)

function M.available()
  if type(native) ~= "table" or type(native.plugins) ~= "function" then return false end
  local ok, list = pcall(native.plugins)
  return ok and type(list) == "table" and list.draw ~= nil and type(native.read) == "function"
end

local function root()
  storage.fstd_overlays = storage.fstd_overlays or { next = 1, list = {} }
  return storage.fstd_overlays
end

--- registers an element: kind "graph" (data = {values, token, max}) or "glow" (data = {token, width})
function M.add(el, kind, data)
  local r = root()
  local id = r.next
  r.next = id + 1
  r.list[id] = { el = el, kind = kind, data = data or {} }
  return id
end

function M.set(id, data)
  local o = root().list[id]
  if o then o.data = data or o.data end
end

function M.remove(id) root().list[id] = nil end

local function ptr(v) if type(v) == "table" and v.ptr and v.ptr ~= 0 then return v end end
local function num(v) return tonumber((v)) end

-- an element's rectangle in pixels of the game window, or nil (not drawn)
local function rect(el)
  local w = ptr(native.read(el, "guiElement.target.widget"))
  if not w then return nil end
  local width, height = num(native.read(w, "size.width")), num(native.read(w, "size.height"))
  if not (width and height) or width <= 0 or height <= 0 then return nil end
  local x, y, depth = 0, 0, 0
  local cw, ch, px, py  -- (the widget we came from: its size and location)
  while w and depth < 40 do
    local lx, ly = num(native.read(w, "location.x")) or 0, num(native.read(w, "location.y")) or 0
    local sw, sh = num(native.read(w, "size.width")) or 0, num(native.read(w, "size.height")) or 0
    -- (a frame's content sits inside its padding and border, though it says 0, 0: half the sizes' difference)
    if cw and w.type == "agui::Window" and px == 0 and py == 0 then
      x, y = x + math.max(0, sw - cw) / 2, y + math.max(0, sh - ch) / 2
    end
    x, y = x + lx, y + ly
    px, py, cw, ch = lx, ly, sw, sh
    w = ptr(native.read(w, "parentWidget"))
    depth = depth + 1
  end
  return { x = x, y = y, w = width, h = height }
end

local function shown(el)
  while el do
    if not el.visible then return false end
    el = el.parent
  end
  return true
end

local function rgba(c, a) return { c.r, c.g, c.b, a or c.a or 1 } end

local function shapes_of(o, r, theme, edits)
  local d = o.data
  local col = themes.color(theme, edits, d.token or "btn_on")
  if o.kind == "glow" then
    local g = d.width or 3
    return {
      { rect = { { r.x - g, r.y - g }, { r.x + r.w + g, r.y + r.h + g } }, color = rgba(col, 0.25), width = g * 2 },
      { rect = { { r.x - 1, r.y - 1 }, { r.x + r.w + 1, r.y + r.h + 1 } }, color = rgba(col, 0.9), width = 1.5 },
    }
  end
  local values = d.values or {}
  local n = #values
  if n < 2 then return {} end
  local max = d.max or 0
  if not d.max then for _, v in ipairs(values) do max = math.max(max, v) end end
  if max <= 0 then max = 1 end
  local pad = 6
  local x0, y0, w, h = r.x + pad, r.y + pad, r.w - 2 * pad, r.h - 2 * pad
  local line, area = {}, { { x0, y0 + h } }
  for i, v in ipairs(values) do
    local p = { x0 + w * (i - 1) / (n - 1), y0 + h - h * math.max(0, v) / max }
    line[#line + 1] = p
    area[#area + 1] = p
  end
  area[#area + 1] = { x0 + w, y0 + h }
  return {
    { poly = area, color = rgba(col, 0.22), width = 0 },
    { poly = line, color = rgba(col, 1), width = 2 },
    { circle = line[#line], radius = 3, color = rgba(col, 1), width = 0 },
  }
end

--- drops the overlays of elements that are gone (every peer: game state)
function M.cleanup()
  local r = storage.fstd_overlays
  for id, o in pairs(r and r.list or {}) do
    if not (o.el and o.el.valid) then r.list[id] = nil end
  end
end

--- draws this peer's player's overlays (call every few ticks); state: the player's theme
function M.tick(player, state)
  if not M.available() then return end
  local r = root()
  local theme = themes.by_name[state.carrier]
  local shapes = {}
  for id, o in pairs(r.list) do
    if o.el and o.el.valid and o.el.player_index == player.index and shown(o.el) then
      local rc = rect(o.el)
      if rc then
        for _, s in ipairs(shapes_of(o, rc, theme, state.edits)) do shapes[#shapes + 1] = s end
      end
    end
  end
  local text = helpers.table_to_json({ id = "fse-std:overlay", screen = true, shapes = shapes })
  if text == last then return end
  last = text
  if #shapes == 0 then
    native.call("draw", "clear", '{"id": "fse-std:overlay"}')
  else
    native.call("draw", "set", text)
  end
end

return M
