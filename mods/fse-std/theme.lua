-- Themed components for mod GUIs. Each player picks a theme (and edits its colours) in fse-std's theme window
-- (/fse-theme); every mod's themed elements follow at once.
--
--   local theme = require("__fse-std__/theme")
--   events.register({ theme.handlers, window.handlers, ... })  -- restyles, folds, toasts, dialogs, search boxes
--   local frame, content = window.create(player, { name = "my_window", title = "My window", themed = true })
--   local sec = theme.section(content, "Recipe")             -- a panel with a heading
--   theme.add(sec, { type = "button", caption = "Plan" }, "ok")
--   theme.add(sec, { type = "textfield", text = "120" }, "field", { width = 60 })
--
-- Roles (themes.lua): panels window section inset deep stat toast badge; buttons button tab rtab ok ok_small (ok in a
-- plain button's size) pulse bad (red: delete, remove) tool tool_on slot;
-- inputs field check radio slider dropdown scroll list tabbed ntab progress; lines drag line bar bar2; text title
-- caption text dim big badge_text. `tweak` is style values of your own (width, stretchable, ...): they are kept
-- when the element is restyled for another theme (a new style name resets an element's style).
--
-- Components (each returns what you add to or update):
--   section(parent, title)          tabs(parent, names, i, tag)       tabbed(parent, names) -> pane, {contents}
--   field(parent, caption)          fold(parent, title, open) -> body  separator(parent)
--   progress(parent, value, {caption, text, auto, color, width}) -> bar;  set_progress(bar, value, text)
--   badge(parent, text)             stat(parent, value, caption)       chart(parent, values, {height, role})
--   search(parent, name, hint)      list(parent, items, selected)      toast(player, text, {seconds, window})
--   confirm(player, {name, title, text, yes, no, danger, data})  (yes / no: the buttons' captions, say verbs;
--   danger = true: yes is a red button, for something that destroys or removes)
-- Layouts (parts that stick out of a themed window, following it when it moves or is resized):
--   attach(frame, side, {size, along, overlap, role, direction}) -> a frame on that edge ("left" "right" "top"
--   "bottom"); tab_rail(frame, names, i, tag) / folder_tabs(frame, names, i, tag) -> tabs out of the left / top
--   edge, the open one in the accent; dock(frame, {size}) -> a toolbar hanging below;
--   over(frame, el, {size, corner}) -> a frame kept over an element (with the fse loader, single player; else nil);
--   menu(frame, {size}) -> a window's settings, under its title bar's right end (window.create{settings = true}).
-- Answers: on_confirm(fn(player, name, yes, data)), on_search(fn(player, name, text)).
-- pulse: an ok button that breathes (with the fse loader; without it, a plain ok button).

local themes = require("__fse-std__/themes")

local M = {}
M.themes = themes

local DEFAULT = { name = "vanilla", carrier = "vanilla", edits = {} }
local FADE = { button = true, tab = true, rtab = true, ok = true, ok_small = true, bad = true, tool = true, slot = true,
  ntab = true }
for name, r in pairs(themes.ROLES) do  -- (adopt()'s variants fade as their roles)
  if r.base and FADE[r.base] then FADE[name] = true end
end
M.FADE = FADE
local confirmers, searchers = {}, {}

--- a player's theme: {name, carrier (the shipped theme whose styles are used), edits = {token = colour}}
--- (fse-std keeps the choice, so every mod shows the same one)
function M.of(player)
  local i = remote.interfaces["fse-std"]
  if i and i.theme then
    local t = remote.call("fse-std", "theme", player.index)
    if t and themes.by_name[t.carrier] then return t end
  end
  return DEFAULT
end

function M.style_name(carrier, role) return "fstd_" .. carrier .. "_" .. role end

local function color_of(th, token)
  return th.edits and th.edits[token] or themes.by_name[th.carrier].tokens[token]
end

local function font(el, role, th)
  local r = themes.ROLES[role]
  local e = th.edits
  if not (r.ink and e) then return end
  local ink, sel = e[r.ink], r.sel_ink and e[r.sel_ink]
  if not (ink or sel) then return end
  local s = el.style
  local function put(k, v) pcall(function() s[k] = v end) end  -- (a sprite button has no text colours)
  if r.type == "button" then
    if ink then
      put("default_font_color", ink); put("hovered_font_color", ink); put("clicked_font_color", ink)
      put("disabled_font_color", themes.faded(ink, 0.5))
    end
    if sel then
      put("selected_font_color", sel); put("selected_hovered_font_color", sel); put("selected_clicked_font_color", sel)
    end
  elseif r.type == "label" or r.type == "textbox" or r.type == "checkbox" or r.type == "radiobutton" then
    if ink then put("font_color", ink) end
  end
end

local fab  -- (adopt()'s title bar buttons, below)

local function tweak(el, t)
  if not t then return end
  local s = el.style
  for k, v in pairs(t) do pcall(function() s[k] = v end) end  -- (a value its type lacks: skipped, not an error)
end

--- gives an element a role's style for theme `th` (default: its player's) and remembers role and tweak
function M.apply(el, role, t, th)
  th = th or M.of(game.get_player(el.player_index))
  local tags = el.tags
  if tags.fstd_role ~= role or t then
    tags.fstd_role = role
    tags.fstd_tweak = t or tags.fstd_tweak
    el.tags = tags
  end
  el.style = M.style_name(th.carrier, role)
  if FADE[role] then el.raise_hover_events = true end  -- (fse-std fades its hover colour in, with the fse loader)
  if ((themes.ROLES[role] or {}).base or role) == "progress" then
    el.style.color = tags.fstd_auto and M.ramp(el.value) or color_of(th, "btn_on")
  end
  font(el, role, th)
  tweak(el, t or tags.fstd_tweak)  -- (after the theme's text colour: a font colour of the caller's wins)
  return el
end

--- parent.add(spec), themed
function M.add(parent, spec, role, t)
  return M.apply(parent.add(spec), role, t)
end

local function th_of(el) return M.of(game.get_player(el.player_index)) end

--- a panel with a heading; returns the panel (add to it)
function M.section(parent, title, tooltip, name)
  local th = th_of(parent)
  local f = M.apply(parent.add({ type = "frame", direction = "vertical", name = name }), "section", nil, th)
  if title then M.apply(f.add({ type = "label", caption = title, tooltip = tooltip }), "caption", nil, th) end
  return f
end

--- a caption over a control: returns the flow to add the control to
function M.field(parent, caption, tooltip)
  local f = parent.add({ type = "flow", direction = "vertical" })
  f.style.vertical_spacing = 2
  M.add(f, { type = "label", caption = caption, tooltip = tooltip }, "dim")
  return f
end

--- a row of toggle buttons; tags = { [tag] = i } on each, the selected one toggled
function M.tabs(parent, names, selected, tag)
  local th = th_of(parent)
  local f = parent.add({ type = "flow", direction = "horizontal" })
  f.style.horizontal_spacing = 2
  for i, n in ipairs(names) do
    M.apply(f.add({ type = "button", caption = n, toggled = i == selected, tags = { [tag] = i } }), "tab", nil, th)
  end
  return f
end

--- toggles the tab with index i in a tabs() row
function M.select_tab(row, i)
  for k, b in ipairs(row.children) do b.toggled = k == i end
end

--- the game's own tabbed pane, themed: returns the pane and each tab's content flow
function M.tabbed(parent, names, selected)
  local th = th_of(parent)
  local pane = M.apply(parent.add({ type = "tabbed-pane" }), "tabbed", nil, th)
  local contents = {}
  for i, n in ipairs(names) do
    local tab = M.apply(pane.add({ type = "tab", caption = n }), "ntab", nil, th)
    local c = pane.add({ type = "flow", direction = "vertical" })
    pane.add_tab(tab, c)
    contents[i] = c
  end
  pane.selected_tab_index = selected or 1
  return pane, contents
end

--- a section whose heading folds it: returns the body to add to
function M.fold(parent, title, open, name)
  local th = th_of(parent)
  open = open ~= false
  local f = M.apply(parent.add({ type = "frame", direction = "vertical", name = name }), "section", nil, th)
  local head = f.add({ type = "flow", direction = "horizontal" })
  head.style.vertical_align = "center"
  M.apply(head.add({ type = "button", caption = open and "-" or "+", tags = { fstd_fold = true },
    tooltip = { "fstd.fold" } }), "tool", { size = 20, font = "default-bold" }, th)
  M.apply(head.add({ type = "label", caption = title }), "caption", nil, th)
  local body = f.add({ type = "flow", direction = "vertical", name = "fstd_fold_body", visible = open })
  return body
end

--- a thin line across
function M.separator(parent)
  return M.add(parent, { type = "empty-widget" }, "line", { horizontally_stretchable = true })
end

--- red at 0, yellow at 0.5, green at 1
function M.ramp(v)
  v = math.max(0, math.min(1, v))
  if v < 0.5 then return { r = 0.9, g = 0.25 + 1.2 * v, b = 0.2, a = 1 } end
  return { r = 0.9 - 1.4 * (v - 0.5), g = 0.85, b = 0.25, a = 1 }
end

--- a progress bar (opts: caption over it, text right of the caption, auto = coloured by its value, color, width)
function M.progress(parent, value, opts)
  opts = opts or {}
  local holder = parent
  local text
  if opts.caption or opts.text then
    holder = parent.add({ type = "flow", direction = "vertical" })
    holder.style.vertical_spacing = 2
    local row = holder.add({ type = "flow", direction = "horizontal" })
    M.add(row, { type = "label", caption = opts.caption or "" }, "dim")
    local push = row.add({ type = "empty-widget" })
    push.style.horizontally_stretchable = true
    text = M.add(row, { type = "label", caption = opts.text or "", name = "fstd_progress_text" }, "text")
  end
  local bar = holder.add({ type = "progressbar", value = value or 0,
    tags = { fstd_auto = opts.auto or nil } })
  M.apply(bar, "progress", { width = opts.width or nil, horizontally_stretchable = not opts.width or nil,
    color = (not opts.auto and opts.color) or nil })
  return bar
end

--- updates a progress bar (and its text, when it has one)
function M.set_progress(bar, value, text)
  bar.value = value
  if bar.tags.fstd_auto then bar.style.color = M.ramp(value) end
  local row = text and bar.parent.children[1]
  if row and row.fstd_progress_text then row.fstd_progress_text.caption = text end
end

--- a small pill with a word or a count
function M.badge(parent, text, tooltip)
  local f = M.add(parent, { type = "frame", direction = "horizontal", tooltip = tooltip }, "badge")
  M.add(f, { type = "label", caption = text }, "badge_text")
  return f
end

--- a big number over a caption
function M.stat(parent, value, caption)
  local f = M.add(parent, { type = "frame", direction = "vertical" }, "stat")
  M.add(f, { type = "label", caption = value, name = "fstd_stat_value" }, "big")
  M.add(f, { type = "label", caption = caption }, "dim")
  return f
end

--- a column chart: one bar per value, scaled to the largest (opts: height, role "bar"/"bar2", max)
function M.chart(parent, values, opts)
  opts = opts or {}
  local h = opts.height or 60
  local max = opts.max or 0
  if not opts.max then for _, v in ipairs(values) do max = math.max(max, v) end end
  local f = M.add(parent, { type = "frame", direction = "horizontal",
    tags = { fstd_chart = { height = h, max = opts.max, role = opts.role } } }, "deep", { height = h + 8, padding = 4 })
  local row = f.add({ type = "flow", direction = "horizontal" })
  row.style.vertical_align = "bottom"
  row.style.horizontal_spacing = 2
  row.style.height = h
  for _, v in ipairs(values) do
    M.add(row, { type = "empty-widget", tooltip = tostring(v) }, opts.role or "bar",
      { height = math.max(1, math.floor(h * (max > 0 and v / max or 0))) })
  end
  return f
end

local function draw_available()
  local i = remote.interfaces["fse-std"]
  return i and i.draw_available and remote.call("fse-std", "draw_available") or false
end

--- a line chart (with the fse loader's draw plugin: drawn over the panel; without: a column chart).
--- opts: width, height (GUI units), token (the colour: "btn_on"), max
function M.graph(parent, values, opts)
  opts = opts or {}
  if not draw_available() then return M.chart(parent, values, { height = opts.height, max = opts.max }) end
  local f = M.add(parent, { type = "frame" }, "deep", { width = opts.width or 300, height = opts.height or 80 })
  local id = remote.call("fse-std", "overlay_add", f, "graph", { values = values, token = opts.token, max = opts.max })
  local tags = f.tags
  tags.fstd_overlay = id
  tags.fstd_graph = { token = opts.token, max = opts.max }
  f.tags = tags
  return f
end

--- new values for a graph() (a column chart without the draw plugin: its bars made again)
function M.set_graph(f, values)
  local id = f.tags.fstd_overlay
  if id then
    local g = f.tags.fstd_graph or {}
    remote.call("fse-std", "overlay_set", id, { values = values, token = g.token, max = g.max })
    return
  end
  local c = f.tags.fstd_chart or {}
  local row = f.children[1]
  local h = c.height or 60
  row.clear()
  local max = c.max or 0
  if not c.max then for _, v in ipairs(values) do max = math.max(max, v) end end
  for _, v in ipairs(values) do
    M.add(row, { type = "empty-widget", tooltip = tostring(v) }, c.role or "bar",
      { height = math.max(1, math.floor(h * (max > 0 and v / max or 0))) })
  end
end

--- a glow around an element (a window): an accent outline across its edge (with the draw plugin; else nothing)
function M.glow(el, token)
  if not draw_available() then return nil end
  return remote.call("fse-std", "overlay_add", el, "glow", { token = token })
end

--- a search box with a clear button; on_search(fn) hears what is typed
function M.search(parent, name, hint)
  local f = parent.add({ type = "flow", direction = "horizontal" })
  f.style.horizontal_spacing = 2
  M.add(f, { type = "textfield", tags = { fstd_search = name }, tooltip = hint or { "fstd.search" } }, "field",
    { horizontally_stretchable = true, minimal_width = 100 })
  M.add(f, { type = "button", caption = "x", tags = { fstd_search_clear = name }, tooltip = { "fstd.clear" } }, "tool")
  return f
end

--- the game's list box, themed
function M.list(parent, items, selected)
  return M.add(parent, { type = "list-box", items = items, selected_index = selected or 0 }, "list")
end

-- toasts: where a box of them goes. Next to the mod's window (below it, past a dock; else above it, past folder tabs;
-- else right or left of it), never over any shown window (any mod's); else at the top of the screen. Each mod's box
-- keeps clear of the others' (their rectangles are in their tags: every mod sees the screen's children).
local TOAST_W, TOAST_GAP = 320, 4

-- (a toast's height in GUI units, guessed: Lua can't read sizes, nor translate. A line holds about 46 characters; a
-- localised text counts its parameters plus 70 for each key's own words, on the safe side: a box guessed too tall only
-- leaves a gap, one guessed too short lets the next mod's box cover it)
local function text_length(text, depth)
  if type(text) == "string" or type(text) == "number" then return #tostring(text) end
  if type(text) ~= "table" or depth > 8 then return 0 end
  local n = (type(text[1]) == "string" and text[1] ~= "") and 70 or 0
  for i = 2, #text do n = n + text_length(text[i], depth + 1) end
  return n
end
local function toast_height(text)
  local lines = math.max(1, math.ceil(text_length(text, 0) / 46))
  return 18 + 20 * lines + TOAST_GAP
end

-- the mod's window a toast belongs to: the one given, the player's opened one, or the first shown
local function toast_owner(player, given)
  local screen = player.gui.screen
  if type(given) == "string" then given = screen[given] end
  if given and given.valid then return given end
  local function fits(c)
    local t = c.tags
    return c.valid and c.visible and t.fstd_window and not t.fstd_confirm_window and c.get_mod() == script.mod_name
      and c.location
  end
  local o = player.opened_gui_type == defines.gui_type.custom and player.opened
  if o and fits(o) then return o end
  for _, c in pairs(screen.children) do
    if fits(c) then return c end
  end
end

-- what sticks out of a window on a side (theme.attach: a dock, folder tabs, rails), in GUI units past its edge
local function sticking_out(player, frame, side)
  local most = 0
  for _, c in pairs(player.gui.screen.children) do
    local a = c.tags.fstd_attach
    if a and a.owner == frame.name and a.side == side and c.visible and c.get_mod() == frame.get_mod() then
      local size = (side == "left" or side == "right") and a.w or a.h
      most = math.max(most, size - (a.overlap or 8))
    end
  end
  return most
end

local function overlaps(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local screen_rect, can_place  -- (below: an element's rectangle from the engine)

-- a shown window's rectangle on the screen in pixels (any mod's): from the engine (the fse loader, single player),
-- else the size window.create / attach / adopt kept in its tags, else a size set on its style; nil when unknown
local function window_rect(player, c)
  if not (c.valid and c.visible and c.location) then return nil end
  local r = can_place() and screen_rect(c)
  if r then return r end
  local sc = player.display_scale
  local t, a = c.tags.fstd_tweak, c.tags.fstd_attach
  local w, h = (a and a.w) or (type(t) == "table" and t.width), (a and a.h) or (type(t) == "table" and t.height)
  if not (w and h) then
    local ok, st = pcall(function() return c.style end)
    local function fixed(lo, hi)
      local o1, a1 = pcall(function() return st[lo] end)
      local o2, b1 = pcall(function() return st[hi] end)
      if not (o1 and o2) then return nil end
      return a1 and a1 > 0 and a1 == b1 and a1 or nil
    end
    w = w or (ok and fixed("minimal_width", "maximal_width"))
    h = h or (ok and fixed("minimal_height", "maximal_height"))
  end
  if not (w and h) then return nil end
  return { x = c.location.x, y = c.location.y, w = w * sc, h = h * sc }
end

-- puts a box of toasts (h: its height in pixels) next to its window, clear of every shown window on the screen
-- (any mod's, with what sticks out of them) and of other mods' boxes of toasts; else at the top of the screen
local function place_toasts(player, box, h, owner)
  local sc = player.display_scale
  local res = player.display_resolution
  local w, gap, edge = math.floor(TOAST_W * sc), math.floor(6 * sc), 8 * sc
  local screen = player.gui.screen
  local windows, others = {}, {}
  for _, c in pairs(screen.children) do
    if c ~= box and c.valid and c.name ~= box.name then
      local r = c.tags.fstd_toast_rect
      if r then others[#others + 1] = r
      elseif c.type == "frame" then
        local wr = window_rect(player, c)
        if wr then windows[#windows + 1] = wr end
      end
    end
  end
  local spots = {}
  if owner then
    local o = window_rect(player, owner)
    if not o then
      local tw = owner.tags.fstd_tweak or {}
      o = { x = owner.location.x, y = owner.location.y, w = (tw.width or 400) * sc, h = (tw.height or 300) * sc }
    end
    local cx = math.floor(o.x + (o.w - w) / 2)
    spots[#spots + 1] = { cx, o.y + o.h + sticking_out(player, owner, "bottom") * sc + gap }
    spots[#spots + 1] = { cx, o.y - sticking_out(player, owner, "top") * sc - gap - h }
    spots[#spots + 1] = { o.x + o.w + sticking_out(player, owner, "right") * sc + gap, o.y }
    spots[#spots + 1] = { o.x - sticking_out(player, owner, "left") * sc - gap - w, o.y }
  end
  local top = { math.floor(res.width / 2 - w / 2), math.floor(70 * sc) }
  spots[#spots + 1] = top
  -- (a spot moved down past each other mod's box it would cover)
  local function settle(x, y)
    local me = { x = math.max(0, math.min(x, res.width - w)), y = y, w = w, h = h }
    for _ = 1, #others + 1 do
      local hit
      for _, r in ipairs(others) do
        if overlaps(me, r) then hit = r break end
      end
      if not hit then break end
      me.y = hit.y + hit.h + math.floor(TOAST_GAP * sc)
    end
    return me
  end
  local function clear(me)
    if me.y < edge or me.y + me.h > res.height - edge or me.x < 0 or me.x + me.w > res.width then return false end
    for _, r in ipairs(windows) do if overlaps(me, r) then return false end end
    return true
  end
  local pick
  for _, sp in ipairs(spots) do
    local me = settle(sp[1], sp[2])
    if clear(me) then pick = me break end
  end
  if not pick then
    -- (no room by its window: the free spot nearest to it (else to the top's middle), along the windows' edges)
    local xs, ys = { top[1] }, { top[2] }
    for _, r in ipairs(windows) do
      xs[#xs + 1] = r.x + r.w + gap; xs[#xs + 1] = r.x - gap - w; xs[#xs + 1] = r.x
      ys[#ys + 1] = r.y + r.h + gap; ys[#ys + 1] = r.y - gap - h; ys[#ys + 1] = r.y
    end
    local ax, ay = spots[1][1], spots[1][2]
    local best
    for _, x in ipairs(xs) do
      for _, y in ipairs(ys) do
        local me = { x = x, y = y, w = w, h = h }
        if clear(me) then
          local d = (x - ax) ^ 2 + (y - ay) ^ 2
          if not best or d < best.d then best = { d = d, me = me } end
        end
      end
    end
    pick = best and settle(best.me.x, best.me.y)
    if pick and not clear(pick) then pick = nil end
  end
  pick = pick or settle(top[1], top[2])
  box.location = { math.floor(pick.x), math.floor(pick.y) }
  local tags = box.tags
  tags.fstd_toast_rect = pick
  box.tags = tags
end

--- a message that goes away by itself, next to the mod's window (opts.window: which one, a frame or its name;
--- else the player's opened one or the first shown), never over it; seconds (4)
function M.toast(player, text, opts)
  opts = opts or {}
  local name = "fstd_toasts_" .. script.mod_name
  local screen = player.gui.screen
  local box = screen[name]
  if not box then
    box = screen.add({ type = "flow", name = name, direction = "vertical", ignored_by_interaction = true })
    box.style.vertical_spacing = TOAST_GAP
  end
  local h = toast_height(text)
  local t = M.add(box, { type = "frame", direction = "horizontal",
    tags = { fstd_until = game.tick + math.floor((opts.seconds or 4) * 60), fstd_h = h } }, "toast", { width = TOAST_W })
  M.add(t, { type = "label", caption = text }, "text", { single_line = false, maximal_width = TOAST_W - 30 })
  local total = 0
  for _, c in pairs(box.children) do total = total + (c.tags.fstd_h or 40) end
  place_toasts(player, box, math.floor(total * player.display_scale), toast_owner(player, opts.window))
  box.bring_to_front()
  return t
end

--- a yes / no question in a window of its own; on_confirm(fn) hears the answer (Esc and close count as no).
--- opts: name, title, text, yes / no (captions: default Yes / No), danger (yes in red), width, data
function M.confirm(player, opts)
  local window = assert(M.window, "theme.confirm: require __fse-std__/window too")
  local name = "fstd_confirm_" .. opts.name
  -- (as tall as its text: a long question wraps, the buttons stay in; a long one gets a wider box)
  local long = type(opts.text) == "string" and #opts.text > 140
  local w = opts.width or (long and 440 or 360)
  local size = { width = w, minimal_height = 120, maximal_height = 900 }
  local frame, content = window.create(player, { name = name, title = opts.title or { "fstd.confirm-title" },
    width = w, height = 160, themed = true, resizable = false, remember = false, close = false, esc = false })
  frame.tags = { fstd_window = name, fstd_role = "window", fstd_tweak = size, fstd_confirm_window = opts.name,
    data = opts.data }
  M.apply(frame, "window", size)
  content.style.vertically_stretchable = false
  M.add(content, { type = "label", caption = opts.text or "" }, "text", { single_line = false, maximal_width = w - 40 })
  local row = content.add({ type = "flow", direction = "horizontal" })
  row.style.top_margin = 12
  local gap = row.add({ type = "empty-widget" })
  gap.style.horizontally_stretchable = true
  M.add(row, { type = "button", caption = opts.no or { "fstd.no" }, tags = { fstd_confirm = opts.name, yes = false } }, "button")
  M.add(row, { type = "button", caption = opts.yes or { "fstd.yes" }, tags = { fstd_confirm = opts.name, yes = true } },
    opts.danger and "bad" or "ok")
  window.open_child(player, frame)  -- (Esc is no; a window of this mod that had Esc gets it back after)
  return frame
end

-- a window's size in GUI units: what window.create set (Lua can't read a size back)
local function win_size(frame)
  local t = frame.tags.fstd_tweak
  return t and t.width or 400, t and t.height or 300
end

--- puts a window's attached frames where they belong (window.lua calls it when the window moves or resizes)
function M.follow(frame)
  if not (frame and frame.valid and frame.location) then return end
  local player = game.get_player(frame.player_index)
  local sc = player.display_scale
  local loc = frame.location
  local W, H = win_size(frame)
  for _, c in pairs(player.gui.screen.children) do
    local a = c.tags.fstd_attach
    if a and a.owner == frame.name and c.get_mod() == frame.get_mod() and a.side == "over" then
      M.place_over(c, frame)
    elseif a and a.owner == frame.name and c.get_mod() == frame.get_mod() then
      local w, h, along, o = a.w, a.h, a.along or 0, a.overlap or 8
      if along < 0 then along = ((a.side == "left" or a.side == "right") and H or W) + along - ((a.side == "left" or a.side == "right") and h or w) end
      local x, y
      if a.side == "left" then x, y = loc.x - (w - o) * sc, loc.y + along * sc
      elseif a.side == "right" then x, y = loc.x + (W - o) * sc, loc.y + along * sc
      elseif a.side == "top" then x, y = loc.x + along * sc, loc.y - (h - o) * sc
      else
        if a.along == nil then along = (W - w) / 2 end  -- (a dock: centred under the window)
        x, y = loc.x + along * sc, loc.y + (H - o) * sc
      end
      c.location = { math.floor(x), math.floor(y) }
      c.bring_to_front()
    end
  end
end

-- over(): an element's rectangle in pixels of the game window, read from the engine (the fse loader), or nil
screen_rect = function(el)
  local ok, r = pcall(function()
    local function ptr(v) if type(v) == "table" and v.ptr and v.ptr ~= 0 then return v end end
    local w = ptr(native.read(el, "guiElement.target.widget"))
    if not w then return nil end
    local width, height = tonumber(native.read(w, "size.width")), tonumber(native.read(w, "size.height"))
    if not (width and height) or width <= 0 or height <= 0 then return nil end
    local x, y, depth = 0, 0, 0
    local cw, ch, px, py  -- (the widget we came from: its size and location)
    while w and depth < 40 do
      local lx, ly = tonumber(native.read(w, "location.x")) or 0, tonumber(native.read(w, "location.y")) or 0
      local sw, sh = tonumber(native.read(w, "size.width")) or 0, tonumber(native.read(w, "size.height")) or 0
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
  end)
  return ok and r or nil
end

local function shown(el)
  while el do
    if not el.visible then return false end
    el = el.parent
  end
  return true
end

local function named(el, name)
  if el.name == name then return el end
  for _, c in pairs(el.children) do
    local f = named(c, name)
    if f then return f end
  end
end

-- (only where the engine can be read and the mouse is this peer's own: the frame's place comes from this peer)
can_place = function()
  return type(native) == "table" and type(native.read) == "function" and not game.is_multiplayer()
end

-- puts an over() frame on its element's corner (hidden while the element isn't shown or can't be read)
local function place_over(c, owner)
  local a = c.tags.fstd_attach
  local target = owner and owner.valid and named(owner, a.target)
  local r = target and shown(target) and can_place() and screen_rect(target)
  if not r then
    if c.visible then c.visible = false end
    return
  end
  local sc = game.get_player(c.player_index).display_scale
  local w, h, inset = a.w * sc, a.h * sc, (a.inset or 8) * sc
  local corner = a.corner or "top-left"
  local x = corner:find("right") and r.x + r.w - w - inset or r.x + inset
  local y = corner:find("bottom") and r.y + r.h - h - inset or r.y + inset
  local loc = c.location
  x, y = math.floor(x), math.floor(y)
  if not c.visible or not loc or loc.x ~= x or loc.y ~= y then
    c.location = { x, y }
    c.visible = true
    c.bring_to_front()
  end
end

M.place_over = place_over

--- a frame kept over an element of a window (a toolbar on a camera, say): a frame of its own on the screen, put on
--- the element's corner from where the engine draws it, and kept there as the window moves or its layout changes.
--- The element needs a name (unique in the window). Only with the fse loader in single player: elsewhere it returns
--- nil, and the controls belong in the window. opts: size = {w, h} (GUI units: Lua can't read sizes), corner
--- ("top-left" "top-right" "bottom-left" "bottom-right"), inset (8, from the element's edges), role ("toast"),
--- direction, padding, name
function M.over(frame, el, opts)
  if not can_place() then return nil end
  opts = opts or {}
  assert(el.name ~= "", "theme.over: the element needs a name")
  local player = game.get_player(frame.player_index)
  local corner = opts.corner or "top-left"
  local name = opts.name or (frame.name .. "__over_" .. el.name .. "_" .. corner)
  if player.gui.screen[name] then player.gui.screen[name].destroy() end
  local w, h = opts.size[1], opts.size[2]
  local c = player.gui.screen.add({ type = "frame", name = name, direction = opts.direction or "horizontal", visible = false,
    tags = { fstd_attach = { owner = frame.name, side = "over", target = el.name, corner = corner, w = w, h = h,
      inset = opts.inset } } })
  M.apply(c, opts.role or "toast", { width = w, height = h, padding = opts.padding or 4 })
  return c
end

--- a frame stuck to a themed window's edge, crossing its border by `overlap` (GUI units). opts: size = {w, h}
--- (needed: Lua can't read sizes), along = offset along the edge (negative: from the far end; a bottom dock
--- without one is centred), overlap (8), role ("toast"), direction, name
function M.attach(frame, side, opts)
  opts = opts or {}
  local player = game.get_player(frame.player_index)
  local name = opts.name or (frame.name .. "__" .. side)
  if player.gui.screen[name] then player.gui.screen[name].destroy() end
  local w, h = opts.size[1], opts.size[2]
  local c = player.gui.screen.add({ type = "frame", name = name, direction = opts.direction or "horizontal",
    tags = { fstd_attach = { owner = frame.name, side = side, w = w, h = h, along = opts.along,
      overlap = opts.overlap } } })
  M.apply(c, opts.role or "toast", { width = w, height = h, padding = opts.padding or 4 })
  M.follow(frame)
  return c
end

local function tab_frame(frame, side, names, selected, tag, opts)
  local vertical = side == "left" or side == "right"
  local tw, th = opts.tab_width or 96, opts.tab_height or 30
  local n = #names
  local size = vertical and { tw + 8, n * (th + 4) + 4 } or { n * (tw + 4) + 8, th + 8 }
  local c = M.attach(frame, side, { size = size, along = opts.along or (vertical and 48 or 16), overlap = 6,
    role = "inset", direction = vertical and "vertical" or "horizontal", padding = 4 })
  for i, n2 in ipairs(names) do
    M.add(c, { type = "button", caption = n2, toggled = i == selected, tags = { [tag] = i } }, "rtab",
      { width = tw, height = th })
  end
  return c
end

--- tabs sticking out of a window's left edge; the open one in the accent (tags = { [tag] = i })
function M.tab_rail(frame, names, selected, tag, opts)
  return tab_frame(frame, "left", names, selected, tag, opts or {})
end

--- folder tabs on top of a window (opts.along: from its left edge; negative: from its right)
function M.folder_tabs(frame, names, selected, tag, opts)
  return tab_frame(frame, "top", names, selected, tag, opts or {})
end

--- a toolbar hanging below a window, across its border (opts.size = {w, h}); add buttons to it
function M.dock(frame, opts)
  opts = opts or {}
  return M.attach(frame, "bottom", { size = opts.size or { 300, 44 }, along = opts.along, overlap = 14,
    role = "toast", padding = 6 })
end

function M.on_confirm(fn) confirmers[#confirmers + 1] = fn end
function M.on_search(fn) searchers[#searchers + 1] = fn end

-- adopt(): the game's styles a GUI was built with (themes.ADOPT), each themed as the game's style with its role's
-- colours (a variant: themes.variant). What its mod set on an element itself (sizes, stretch, a dim text colour, ...:
-- what differs from a fresh element of its style) is kept as its tweak.
local OWN = { "minimal_width", "maximal_width", "minimal_height", "maximal_height", "natural_width",
  "natural_height", "horizontally_stretchable", "vertically_stretchable", "horizontally_squashable",
  "vertically_squashable", "horizontal_align", "vertical_align", "top_margin", "right_margin", "bottom_margin",
  "left_margin", "top_padding", "right_padding", "bottom_padding", "left_padding", "single_line", "font",
  "font_color" }

local function read(st, k)
  local ok, v = pcall(function() return st[k] end)
  if ok then return v end
end
local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
end

-- (what a style alone gives an element of that type: a fresh one, read and thrown away; false if it can't be made)
local function fresh(holder, el, style, cache)
  local key = el.type .. " " .. style
  if cache[key] == nil then
    local spec = { type = el.type, style = style }
    if el.type == "choose-elem-button" then spec.elem_type = el.elem_type end
    if el.type == "table" then spec.column_count = el.column_count end
    local ok, f = pcall(holder().add, spec)
    local v = false
    if ok and f then
      v = {}
      for _, k in ipairs(OWN) do v[k] = read(f.style, k) end
      f.destroy()
    end
    cache[key] = v
  end
  return cache[key]
end

-- (an element themed before variants: its role and the tweak it was given then, all its sizes, read back. Its game
-- style is guessed from the role; a false stretch is dropped: read back, the game's "auto" is a plain false)
local function legacy(el)
  local tags = el.tags
  local role, t = tags.fstd_role, tags.fstd_tweak
  if type(role) ~= "string" or role:find("__", 1, true) or type(t) ~= "table" then return nil end
  -- (adopt() then copied every margin; a caller's own tweak hardly gives all four)
  if t.top_margin == nil or t.right_margin == nil or t.bottom_margin == nil or t.left_margin == nil then return nil end
  local r = themes.ROLES[role]
  local base = r and r.vanilla
  if role == "section" then base = (t.minimal_height == 36 and t.maximal_height == 36) and "subheader_frame" or "frame" end
  local v = base and themes.variant(role, base)
  if not (v and themes.ROLES[v]) then return nil end
  local out = {}
  for k, x in pairs(t) do if x ~= false or not k:find("ably$") then out[k] = x end end
  return v, out
end

-- a title bar's icons for a light button (a light theme's window, a light accent): the game's and flib's white ones
-- that have a dark one (data.lua makes the missing ones)
local DARK_ICON = { ["utility/close"] = "utility/close_black", ["utility/reset_white"] = "utility/reset",
  ["utility/trash_white"] = "utility/trash", ["utility/search"] = "fstd-black-search",
  ["flib_pin_white"] = "flib_pin_black", ["flib_settings_white"] = "flib_settings_black",
  ["flib_nav_backward_white"] = "flib_nav_backward_black", ["flib_nav_forward_white"] = "flib_nav_forward_black",
  ["fstd-settings"] = "fstd-settings-black" }
local LIGHT_ICON = {}
for w, b in pairs(DARK_ICON) do LIGHT_ICON[b] = w end
M.DARK_ICON = DARK_ICON

-- a title bar's button adopt() themed: its icon dark on a light button. A light icon of a mod's own with no dark one
-- keeps the game's dark button (the button's game style: tags.fstd_fab), so it stays readable; themed again on a
-- dark theme
fab = function(el, th)
  local f = el.tags.fstd_fab
  local token = ((themes.ROLES[el.tags.fstd_role] or {}).base == "close_on") and "btn_on" or "win"
  local light = themes.is_light(color_of(th, token))
  local want = (not light and f.icon) or DARK_ICON[f.icon]
  if not want then
    -- (the game's dark button; with flat game windows that one is light too: the accent's own, when that is dark)
    local md = prototypes.mod_data["fstd-game-styles"]
    if md and md.data.flat and not themes.is_light(color_of(th, "btn_on")) then
      el.style = M.style_name(th.carrier, "close_on")
    else
      el.style = f.style
    end
    tweak(el, el.tags.fstd_tweak)
    want = f.icon
  end
  el.sprite = want
  if f.hovered then el.hovered_sprite = want end
  if f.clicked then el.clicked_sprite = want end
end

--- themes a GUI built with the game's styles: every element whose style has a role (themes.ADOPT) gets that role's
--- colours on its own style (its sizes, paddings, flows and fonts stay the game's). A window frame at the root gets
--- the window's. Elements with styles of their own (another mod's) stay as they are. Call it again after adding
--- elements or giving one a game style again: only those are themed (and ones themed by an older fse-std, again).
function M.adopt(root)
  local player = game.get_player(root.player_index)
  local th = M.of(player)
  local box, cache = nil, {}
  local function holder()
    if not (box and box.valid) then box = player.gui.screen.add({ type = "frame", visible = false }) end
    return box
  end
  local function visit(el, top)
    local name = el.style and el.style.name
    if name and name:sub(1, 5) == "fstd_" then
      local v, t = legacy(el)
      if v then M.apply(el, v, t, th) end
    else
      local role = name and themes.ADOPT[name]
      if role == "window" and not top then role = themes.ADOPT_INNER[name] end
      -- (a title bar's buttons: sprite buttons, their icons following the theme)
      if (role == "close" or role == "close_on") and el.type ~= "sprite-button" then role = nil end
      local v = role and themes.variant(role, name)
      if v and themes.ROLES[v] then
        local t, st = {}, el.style
        local was = fresh(holder, el, name, cache)
        if was then
          for _, k in ipairs(OWN) do
            local x = read(st, k)
            if x ~= nil and not same(x, was[k]) then t[k] = x end
          end
        end
        local old = top and el.tags.fstd_tweak
        if type(old) == "table" then  -- (a window's size, which Lua can't read back: attached frames follow it)
          t.width, t.height = t.width or old.width, t.height or old.height
        end
        if top then  -- (a size set with style.width / height reads back as equal minimum and maximum)
          if not t.width and t.minimal_width and t.minimal_width == t.maximal_width then t.width = t.minimal_width end
          if not t.height and t.minimal_height and t.minimal_height == t.maximal_height then t.height = t.minimal_height end
        end
        if role == "close" or role == "close_on" then
          local tags = el.tags
          local icon = LIGHT_ICON[el.sprite] or el.sprite
          tags.fstd_fab = { style = name, icon = icon, hovered = el.hovered_sprite == el.sprite or nil,
            clicked = el.clicked_sprite == el.sprite or nil }
          el.tags = tags
        end
        M.apply(el, v, t, th)
        if role == "close" or role == "close_on" then fab(el, th) end
      end
    end
    for _, c in pairs(el.children) do visit(c, false) end
  end
  visit(root, true)
  if box and box.valid then box.destroy() end
  return root
end

--- the close icon for a theme: black on light themes
function M.close_sprite(th)
  local t = themes.by_name[th.carrier]
  return t and t.light and "utility/close_black" or "utility/close"
end

--- the settings icon (a gear) for a theme: black on light themes
function M.settings_sprite(th)
  local t = themes.by_name[th.carrier]
  return t and t.light and "fstd-settings-black" or "fstd-settings"
end

--- a window's settings: a panel under its title bar's right end (after its settings button: window.create{settings}),
--- following the window. A second call closes it (-> nil), as do Esc, closing or hiding the window. opts: size =
--- {w, h} (GUI units), name, keep_opened (a window that is the player's opened GUI keeps that: Esc then closes the
--- window, the panel with it)
function M.menu(frame, opts)
  opts = opts or {}
  local player = game.get_player(frame.player_index)
  local name = opts.name or (frame.name .. "__menu")
  local open = player.gui.screen[name]
  if open then
    local tags = open.tags
    open.destroy()
    if M.window then M.window.give_back(player, tags) end
    return nil
  end
  local w, h = opts.size[1], opts.size[2]
  local m = M.attach(frame, "top", { size = { w, h }, along = -(opts.right or 8), overlap = h + (opts.below or 38),
    role = "toast", direction = "vertical", padding = 8, name = name })
  local tags = m.tags
  tags.fstd_menu = frame.name
  m.tags = tags
  if not opts.keep_opened then  -- (Esc closes it; a window that had Esc gets it back after)
    if M.window then M.window.open_child(player, m) else player.opened = m end
  end
  return m
end

local function walk(el, th)
  if el.tags.fstd_close then el.sprite = M.close_sprite(th) end
  if el.tags.fstd_settings then el.sprite = M.settings_sprite(th) end
  local role, f = el.tags.fstd_role, el.tags.fstd_fab
  -- (only what still has a theme's style, or an adopted title bar button its game style: a mod may have given an
  -- element a style of its own since)
  if f and role and (el.style.name:sub(1, 5) == "fstd_" or el.style.name == f.style) then
    M.apply(el, role, nil, th)
    fab(el, th)
  elseif role and el.style.name:sub(1, 5) == "fstd_" then
    local v, t = legacy(el)  -- (themed by an older fse-std: as adopt() themes it now)
    if v then M.apply(el, v, t, th) else M.apply(el, role, nil, th) end
  end
  for _, c in pairs(el.children) do walk(c, th) end
end

--- restyles this mod's themed elements of a player (all of its GUI roots)
function M.restyle(player)
  local th = M.of(player)
  local mod = script.mod_name
  for _, root in pairs({ player.gui.screen, player.gui.left, player.gui.top, player.gui.center, player.gui.relative }) do
    for _, el in pairs(root.children) do
      if el.get_mod() == mod then walk(el, th) end
    end
  end
end

local function answer(player, frame, yes)
  local tags = frame.tags
  local name, data = tags.fstd_confirm_window, tags.data
  frame.destroy()
  if M.window then M.window.give_back(player, tags) end
  for _, fn in ipairs(confirmers) do fn(player, name, yes, data) end
end

-- (events reach every mod: each one only answers for its own elements)
local function ours(el) return el and el.valid and el.get_mod() == script.mod_name end

M.handlers = {
  ["fstd-theme-changed"] = function(e)
    local p = game.get_player(e.player_index)
    if p then M.restyle(p) end
  end,
  [defines.events.on_gui_click] = function(e)
    local el = e.element
    if not ours(el) then return end
    local tags = el.tags
    local player = game.get_player(e.player_index)
    if tags.fstd_fold then
      local body = el.parent.parent.fstd_fold_body
      body.visible = not body.visible
      el.caption = body.visible and "-" or "+"
    elseif tags.fstd_confirm then
      local frame = player.gui.screen["fstd_confirm_" .. tags.fstd_confirm]
      if frame then answer(player, frame, tags.yes) end
    elseif tags.fstd_search_clear then
      local field = el.parent.children[1]
      field.text = ""
      for _, fn in ipairs(searchers) do fn(player, tags.fstd_search_clear, "") end
    end
  end,
  [defines.events.on_gui_text_changed] = function(e)
    local el = e.element
    if not (ours(el) and el.tags.fstd_search) then return end
    local player = game.get_player(e.player_index)
    for _, fn in ipairs(searchers) do fn(player, el.tags.fstd_search, el.text) end
  end,
  [defines.events.on_gui_closed] = function(e)
    local el = e.element
    if ours(el) and el.tags.fstd_confirm_window then answer(game.get_player(e.player_index), el, false) end
    if ours(el) and el.tags.fstd_menu then  -- (a window's settings: Esc closes them)
      local tags = el.tags
      el.destroy()
      if M.window then M.window.give_back(game.get_player(e.player_index), tags) end
    end
  end,
  [defines.events.on_gui_location_changed] = function(e)
    local el = e.element
    if ours(el) and el.tags.fstd_window then M.follow(el) end
  end,
  [defines.events.on_tick] = function(e)
    if e.tick % 5 == 0 and can_place() then  -- (over() frames: back on their element if the layout moved it)
      for _, player in pairs(game.connected_players) do
        local screen = player.gui.screen
        for _, c in pairs(screen.children) do
          local a = c.tags.fstd_attach
          if a and a.side == "over" and c.get_mod() == script.mod_name then place_over(c, screen[a.owner]) end
        end
      end
    end
    if e.tick % 10 == 0 then  -- (a window moved or resized without an event, e.g. kept on the screen by the game)
      for _, player in pairs(game.connected_players) do
        for _, c in pairs(player.gui.screen.children) do
          local t = c.tags
          if t.fstd_window and t.fstd_role and c.get_mod() == script.mod_name and c.location then
            local tw = t.fstd_tweak or {}
            local key = string.format("%d,%d,%s,%s", c.location.x, c.location.y, tostring(tw.width), tostring(tw.height))
            if t.fstd_at ~= key then
              t.fstd_at = key
              c.tags = t
              M.follow(c)
            end
          end
        end
      end
    end
    if e.tick % 30 ~= 0 then return end
    -- (frames stuck to a window hide while it's hidden, and go when it's gone)
    for _, player in pairs(game.connected_players) do
      local screen = player.gui.screen
      for _, c in pairs(screen.children) do
        local a = c.tags.fstd_attach
        if a and c.get_mod() == script.mod_name then
          local owner = screen[a.owner]
          if not owner or (c.tags.fstd_menu and not owner.visible) then  -- (a window's settings go with it)
            c.destroy()
          elseif a.side ~= "over" and owner.visible ~= c.visible and (c.visible or c.tags.fstd_hidden_with) then
            local tags = c.tags
            tags.fstd_hidden_with = not owner.visible or nil
            c.tags = tags
            c.visible = owner.visible
          end
        end
      end
    end
    local name = "fstd_toasts_" .. script.mod_name
    for _, player in pairs(game.connected_players) do
      local box = player.gui.screen[name]
      if box then
        local gone = false
        for _, t in pairs(box.children) do
          if t.tags.fstd_until and t.tags.fstd_until <= e.tick then t.destroy(); gone = true end
        end
        if #box.children == 0 then
          box.destroy()
        elseif gone then  -- (its rectangle shrinks with it: other mods' boxes may come closer)
          local tags = box.tags
          local h = 0
          for _, t in pairs(box.children) do h = h + (t.tags.fstd_h or 40) end
          if tags.fstd_toast_rect then tags.fstd_toast_rect.h = math.floor(h * player.display_scale) end
          box.tags = tags
        end
      end
    end
  end,
}

return M
