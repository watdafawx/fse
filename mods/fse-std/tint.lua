-- Live colours, with the fse loader: a player's theme colours written straight into the sprites of the theme's
-- styles (and, when asked, of the game's own styles), so edits show at once, no restart. Only the peer the player
-- plays on writes (the GUI is drawn there): nothing here is game state, every peer's game stays the same.
--
-- The engine draws a style's image set from Sprites whose tint we write (SpriteParameters.tint, read through
-- native.read from a LuaGuiElement: guiElement.target.widget -> style.parent -> <engine path> ->
-- base.<part>.value.sprite). A tint multiplies the texture and can't go over 1: our white tiles take any colour,
-- the game's grey textures only get darker or change hue.

local themes = require("themes")

local M = {}
local PARTS = { "center", "leftTop", "rightTop", "leftBottom", "rightBottom", "top", "right", "bottom", "left" }
local KIND = { frame = "frame", button = "button", textbox = "textfield", empty = "empty-widget",
  checkbox = "checkbox", radiobutton = "radiobutton", slider = "slider", dropdown = "drop-down",
  scroll = "scroll-pane", list = "list-box", tabbed = "tabbed-pane", progress = "progressbar", label = "label" }
-- the game's own dark panels are tinted by how far the theme is from them; its light controls (buttons, fields)
-- only take the theme's hue, so their black text stays readable
local DARK = { win = true, section = true, inset = true, deep = true, drag = true, slot = true }  -- (slots: dark too)

-- (this peer's own: engine addresses, found again after a load)
local cache = {}      -- "<style>/<engine path>" -> { sprite pointers }
local originals = {}  -- sprite address -> its tint before we wrote it (the game's own styles: given back)
local touched = {}    -- player_index -> the game's own styles were tinted

function M.available()
  return type(native) == "table" and type(native.write) == "function" and type(native.read) == "function"
    and type(native.local_player) == "function"
end

local function add(f, role, name, style)
  local r = themes.ROLES[role]
  if r.type == "tab" then  -- (a tab is drawn only inside a tabbed pane)
    local pane = f.add({ type = "tabbed-pane", name = "pane_" .. name })
    local tab = pane.add({ type = "tab", name = name, style = style, caption = "t" })
    pane.add_tab(tab, pane.add({ type = "flow" }))
    return
  end
  local kind = KIND[r.type]
  if not kind then return end
  local spec = { type = kind, name = name, style = style }
  if kind == "checkbox" or kind == "radiobutton" then spec.state = false end
  f.add(spec)
end

--- the probe: a hidden frame of one element per styled role of the player's theme and per game style it stands
--- for (with_game: every game style too), so the engine has those styles' sprites and they can be found. Made the
--- same on every peer.
function M.probe(player, carrier, with_game)
  local screen = player.gui.screen
  if screen.fstd_probe then screen.fstd_probe.destroy() end
  local f = screen.add({ type = "frame", name = "fstd_probe", visible = false, tags = { carrier = carrier } })
  for role, r in pairs(themes.ROLES) do
    add(f, role, "t_" .. role, "fstd_" .. carrier .. "_" .. role)
    if not r.own then add(f, role, "v_" .. role, r.vanilla) end
  end
  if with_game then
    local g = f.add({ type = "flow", name = "game" })
    for i, s in ipairs(themes.game_styles()) do
      if s.type == "tab" then  -- (a tab is drawn only inside a tabbed pane)
        local pane = g.add({ type = "tabbed-pane", name = "pane_g_" .. i })
        pane.add_tab(pane.add({ type = "tab", name = "g_" .. i, style = s.style, caption = "t" }), pane.add({ type = "flow" }))
      else
        local kind = ({ scroll = "scroll-pane", table = "table", tabbed = "tabbed-pane" })[s.type] or KIND[s.type]
        g.add({ type = kind, name = "g_" .. i, style = s.style, column_count = kind == "table" and 1 or nil })
      end
    end
  end
  return f
end

local function find(probe, name)
  return probe[name] or (probe["pane_" .. name] and probe["pane_" .. name][name])
end

local function ptr(v)
  if type(v) == "table" and v.ptr and v.ptr ~= 0 then return v end
end

-- an element's style's sprites of one image set at an engine path (the style's own, or the nearest parent's)
local function sprites(el, epath, style)
  local key = (style or el.style.name) .. "/" .. table.concat(epath, ".")
  if cache[key] then return cache[key] end
  if not (el and el.valid) then return nil end
  local w = ptr(native.read(el, "guiElement.target.widget"))
  if not w then return nil end
  local st = ptr(native.read(w, "style.parent"))
  local depth = 0
  while st and depth < 8 do
    local cur = st
    for _, f in ipairs(epath) do
      cur = ptr(native.read(cur, f))
      if not cur then break end
    end
    if cur then
      local out = {}
      for _, part in ipairs(PARTS) do
        local sp = ptr(native.read(cur, "base." .. part .. ".value.sprite"))
        if sp then out[#out + 1] = sp end
      end
      cache[key] = out
      return out
    end
    st = ptr(native.read(st, "parent"))
    depth = depth + 1
  end
end

-- a style's text colour object (an agui::Color the engine holds by pointer), the style's own or a parent's
local function color_of(el, field, style)
  local key = style .. "/font/" .. field
  if cache[key] then return cache[key] end
  if not (el and el.valid) then return nil end
  local w = ptr(native.read(el, "guiElement.target.widget"))
  local st = w and ptr(native.read(w, "style.parent"))
  local depth = 0
  while st and depth < 8 do
    local c = ptr(native.read(st, field))
    if c then cache[key] = { c }; return cache[key] end
    st = ptr(native.read(st, "parent"))
    depth = depth + 1
  end
end

local function write_color(list, c)
  if native.write_many and pcall(native.write_many, list, { r = c.r, g = c.g, b = c.b, a = c.a }) then return end
  for _, o in ipairs(list) do
    for _, k in ipairs({ "r", "g", "b", "a" }) do native.write(o, k, c[k]) end
  end
end

local function remember_color(list)
  for _, o in ipairs(list) do
    if not originals[o.ptr] then
      local t = native.read(o, "")
      if type(t) == "table" then originals[o.ptr] = { r = t.r, g = t.g, b = t.b, a = t.a, color = true } end
    end
  end
end

local function write(list, c)
  if #list == 0 then return end
  if native.write_many and pcall(native.write_many, list,  -- (one call for all: the offsets found once)
      { ["tint.r"] = c.r, ["tint.g"] = c.g, ["tint.b"] = c.b, ["tint.a"] = c.a }) then
    return
  end
  for _, sp in ipairs(list) do
    native.write(sp, "tint.r", c.r)
    native.write(sp, "tint.g", c.g)
    native.write(sp, "tint.b", c.b)
    native.write(sp, "tint.a", c.a)
  end
end

local function remember(list)
  for _, sp in ipairs(list) do
    if not originals[sp.ptr] then
      local t = native.read(sp, "tint")
      if type(t) == "table" then originals[sp.ptr] = { r = t.r, g = t.g, b = t.b, a = t.a } end
    end
  end
end

local function give_back(list)
  if list[1] and list[1].type == "agui::Color" then  -- (text colours: as they were)
    for _, o in ipairs(list) do
      local c = originals[o.ptr]
      if c then write_color({ o }, c) end
    end
    return
  end
  local groups = {}  -- (the same colour together: one write each)
  for _, sp in ipairs(list) do
    local o = originals[sp.ptr]
    if o then
      local key = o.r .. "," .. o.g .. "," .. o.b .. "," .. o.a
      local g = groups[key] or { c = o, list = {} }
      groups[key] = g
      g.list[#g.list + 1] = sp
    end
  end
  for _, g in pairs(groups) do write(g.list, g.c) end
end

local function own_tint(theme, token, col)
  local t = themes.tint(theme, token, col)
  t.a = t.a * (1 - theme.index * 0.0004)  -- (as data.lua: one theme's sprites never equal another's)
  return t
end

-- the game's styles drawn with our white tiles (startup setting fstd-flat-game): any colour, as our own styles
local function flat_game()
  local md = prototypes.mod_data["fstd-game-styles"]
  return md and md.data.flat
end

local function game_tint(token, base, how)
  if flat_game() then return themes.tint({ shape = "soft" }, token, themes.derive(base, how or "same")) end
  if DARK[token] then
    return themes.tint({ shape = "vanilla" }, token, { r = base.r, g = base.g, b = base.b, a = 1 })
  end
  local m = math.max(base.r, base.g, base.b, 0.001)
  return themes.mix({ r = 1, g = 1, b = 1, a = 1 }, { r = base.r / m, g = base.g / m, b = base.b / m, a = 1 }, 0.45)
end

local function mine(player)
  return M.available() and native.local_player() == player.index
end

local function probe_of(player, state, given)
  local probe = given or player.gui.screen.fstd_probe
  if probe and probe.valid and probe.tags.carrier == state.carrier then return probe end
end

--- writes a player's theme colours (state: {carrier, edits, vanilla_gui}); only = a token: just what it colours.
--- Returns false when it couldn't (no loader, another peer's player, the probe not drawn yet).
function M.apply(player, state, only, given_probe)
  if not mine(player) then return false end
  local probe = probe_of(player, state, given_probe)
  if not probe then return false end
  local theme = themes.by_name[state.carrier]
  local found = false
  for role, r in pairs(themes.ROLES) do
    local own, game_el = find(probe, "t_" .. role), (not r.own) and find(probe, "v_" .. role)
    for _, st in ipairs(themes.sets(role)) do
      local epath, token, how = st[2], st[3], st[4]
      if not only or only == token then
        local list = own and sprites(own, epath)
        if list then
          write(list, own_tint(theme, token, themes.derive(themes.color(theme, state.edits, token), how)))
          found = true
        end
        local glist = game_el and token ~= "white" and sprites(game_el, epath)
        if glist then
          if state.vanilla_gui then
            remember(glist)
            write(glist, game_tint(token, themes.color(theme, state.edits, token), how))
            touched[player.index] = true
          elseif touched[player.index] then
            give_back(glist)
          end
        end
      end
    end
  end
  if not state.vanilla_gui then touched[player.index] = nil end
  return found
end

--- every game style (the map, the quick bar, the shortcut bar, every window: themes.game_styles()) in the theme's
--- colours, or, when the player turned it off, given back. Many styles: called when things settle, not per edit.
function M.apply_game(player, state, given_probe, only)
  if not mine(player) then return false end
  local probe = probe_of(player, state, given_probe)
  local holder = probe and probe.game
  local theme = themes.by_name[state.carrier]
  local found = false
  for i, g in ipairs(themes.game_styles()) do
    local el = holder and (holder["g_" .. i] or (holder["pane_g_" .. i] and holder["pane_g_" .. i]["g_" .. i]))
    for _, f in ipairs(g.fonts or {}) do
      local field, token = f[1], f[2]
      local list = (not f.flat or flat_game()) and (not only or only == token) and color_of(el, field, g.style)
      if list then
        found = true
        if state.vanilla_gui then
          remember_color(list)
          local c = themes.color(theme, state.edits, token)
          write_color(list, { r = c.r, g = c.g, b = c.b, a = 1 })
        else
          give_back(list)
        end
      end
    end
    for _, st in ipairs(g.sets) do
      local token = st[3]
      local list = (not only or only == token) and sprites(el, st[2], g.style)
      if list then
        found = true
        if state.vanilla_gui then
          remember(list)
          write(list, game_tint(token, themes.color(theme, state.edits, token), st[4]))
        else
          give_back(list)
        end
      end
    end
  end
  return found
end

--- the pulse role's glow: its main colour breathing toward a lighter one (call every few ticks)
function M.pulse(player, state, tick)
  if not mine(player) then return end
  local probe = probe_of(player, state)
  local el = probe and find(probe, "t_pulse")
  if not el then return end
  local theme = themes.by_name[state.carrier]
  local base = themes.color(theme, state.edits, "ok")
  local t = (math.sin(tick / 10) + 1) / 2
  for i = 1, 2 do  -- (default and hovered)
    local st = themes.sets("pulse")[i]
    local list = sprites(el, st[2])
    if list then
      write(list, own_tint(theme, "ok", themes.lighter(themes.derive(base, st[4]), 0.35 * t)))
    end
  end
end

-- hover fades: role -> {start tick}; each tick until done the role's hovered colour moves from its normal one to
-- its lit one, so a button lights up instead of jumping (the colour is the style's: only one button is hovered)
local fades = {}
local FADE_TICKS = 8

function M.fade_start(role, tick) fades[role] = { start = tick } end

function M.fade_step(player, state, tick)
  if not next(fades) or not mine(player) then return end
  local probe = probe_of(player, state)
  local theme = themes.by_name[state.carrier]
  for role, f in pairs(fades) do
    local el = probe and find(probe, "t_" .. role)
    local t = math.min(1, (tick - f.start) / FADE_TICKS)
    local sets = themes.sets(role)
    for _, i in ipairs({ 2, 6 }) do  -- (hovered, and hovered while toggled)
      local st = sets[i]
      local list = el and st and sprites(el, st[2])
      if list then
        local base = themes.color(theme, state.edits, st[3])
        local col = themes.mix(base, themes.derive(base, st[4]), t)
        write(list, own_tint(theme, st[3], col))
      end
    end
    if t >= 1 then fades[role] = nil end
  end
end

--- forgets the addresses (the engine may have made its sprites again: a graphics change)
function M.forget()
  cache = {}
end

return M
