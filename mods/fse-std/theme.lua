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
-- Roles (themes.lua): panels window section inset deep stat toast badge; buttons button tab ok pulse tool slot;
-- inputs field check radio slider dropdown scroll list tabbed ntab progress; lines drag line bar bar2; text title
-- caption text dim big badge_text. `tweak` is style values of your own (width, stretchable, ...): they are kept
-- when the element is restyled for another theme (a new style name resets an element's style).
--
-- Components (each returns what you add to or update):
--   section(parent, title)          tabs(parent, names, i, tag)       tabbed(parent, names) -> pane, {contents}
--   field(parent, caption)          fold(parent, title, open) -> body  separator(parent)
--   progress(parent, value, {caption, text, auto, color, width}) -> bar;  set_progress(bar, value, text)
--   badge(parent, text)             stat(parent, value, caption)       chart(parent, values, {height, role})
--   search(parent, name, hint)      list(parent, items, selected)      toast(player, text, {seconds})
--   confirm(player, {name, title, text, yes, no, data})
-- Layouts (parts that stick out of a themed window, following it when it moves or is resized):
--   attach(frame, side, {size, along, overlap, role, direction}) -> a frame on that edge ("left" "right" "top"
--   "bottom"); tab_rail(frame, names, i, tag) / folder_tabs(frame, names, i, tag) -> tabs out of the left / top
--   edge, the open one merging into the window; dock(frame, {size}) -> a toolbar hanging below.
-- Answers: on_confirm(fn(player, name, yes, data)), on_search(fn(player, name, text)).
-- pulse: an ok button that breathes (with the fse loader; without it, a plain ok button).

local themes = require("__fse-std__/themes")

local M = {}
M.themes = themes

local DEFAULT = { name = "vanilla", carrier = "vanilla", edits = {} }
local FADE = { button = true, tab = true, rtab = true, ok = true, tool = true, slot = true, ntab = true }
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
  if r.type == "button" then
    if ink then
      s.default_font_color = ink; s.hovered_font_color = ink; s.clicked_font_color = ink
      s.disabled_font_color = themes.faded(ink, 0.5)
    end
    if sel then
      s.selected_font_color = sel; s.selected_hovered_font_color = sel; s.selected_clicked_font_color = sel
    end
  elseif r.type == "label" or r.type == "textbox" or r.type == "checkbox" or r.type == "radiobutton" then
    if ink then s.font_color = ink end
  end
end

local function tweak(el, t)
  if not t then return end
  local s = el.style
  for k, v in pairs(t) do s[k] = v end
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
  if role == "progress" then el.style.color = tags.fstd_auto and M.ramp(el.value) or color_of(th, "btn_on") end
  tweak(el, t or tags.fstd_tweak)
  font(el, role, th)
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
    tooltip = "Fold / unfold" }), "tool", { size = 20, font = "default-bold" }, th)
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
  M.add(f, { type = "textfield", tags = { fstd_search = name }, tooltip = hint or "Search" }, "field",
    { horizontally_stretchable = true, minimal_width = 100 })
  M.add(f, { type = "button", caption = "x", tags = { fstd_search_clear = name }, tooltip = "Clear" }, "tool")
  return f
end

--- the game's list box, themed
function M.list(parent, items, selected)
  return M.add(parent, { type = "list-box", items = items, selected_index = selected or 0 }, "list")
end

--- a message at the top of the screen that goes away by itself
function M.toast(player, text, opts)
  opts = opts or {}
  local name = "fstd_toasts_" .. script.mod_name
  local screen = player.gui.screen
  local box = screen[name]
  if not box then
    box = screen.add({ type = "flow", name = name, direction = "vertical", ignored_by_interaction = true })
    box.style.vertical_spacing = 4
  end
  local scale = player.display_scale
  box.location = { math.floor(player.display_resolution.width / 2 - 160 * scale), math.floor(70 * scale) }
  local t = M.add(box, { type = "frame", direction = "horizontal",
    tags = { fstd_until = game.tick + math.floor((opts.seconds or 4) * 60) } }, "toast", { width = 320 })
  M.add(t, { type = "label", caption = text }, "text", { single_line = false, maximal_width = 290 })
  return t
end

--- a yes / no question in a window of its own; on_confirm(fn) hears the answer (Esc and close count as no)
function M.confirm(player, opts)
  local window = assert(M.window, "theme.confirm: require __fse-std__/window too")
  local name = "fstd_confirm_" .. opts.name
  local frame, content = window.create(player, { name = name, title = opts.title or "Are you sure?", width = 360,
    height = 160, themed = true, resizable = false, remember = false, close = false })
  frame.tags = { fstd_window = name, fstd_role = "window", fstd_tweak = { width = 360, height = 160 },
    fstd_confirm_window = opts.name, data = opts.data }
  M.add(content, { type = "label", caption = opts.text or "" }, "text", { single_line = false })
  local push = content.add({ type = "empty-widget" })
  push.style.vertically_stretchable = true
  local row = content.add({ type = "flow", direction = "horizontal" })
  local gap = row.add({ type = "empty-widget" })
  gap.style.horizontally_stretchable = true
  M.add(row, { type = "button", caption = opts.no or "Cancel", tags = { fstd_confirm = opts.name, yes = false } }, "button")
  M.add(row, { type = "button", caption = opts.yes or "Yes", tags = { fstd_confirm = opts.name, yes = true } }, "ok")
  player.opened = frame
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
    if a and a.owner == frame.name and c.get_mod() == frame.get_mod() then
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

--- tabs sticking out of a window's left edge; the open one takes the window's colour (tags = { [tag] = i })
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

-- adopt(): the game's styles a GUI was built with, and the role that stands for each
local ADOPT = {
  frame = "window", inside_shallow_frame = "inset", inside_shallow_frame_with_padding = "inset",
  inside_deep_frame = "deep", bordered_frame = "section", subheader_frame = "section",
  button = "button", confirm_button = "ok", tool_button = "tool", slot_button = "slot",
  frame_title = "title", caption_label = "caption", label = "text", bold_label = "text",
  textbox = "field", checkbox = "check", radiobutton = "radio", slider = "slider", dropdown = "dropdown",
  scroll_pane = "scroll", list_box = "list", tabbed_pane = "tabbed", tab = "ntab", progressbar = "progress",
  draggable_space_header = "drag", draggable_space = "drag",
  -- (common ones mods build with, flib's included)
  subheader_caption_label = "caption", list_box_scroll_pane = "scroll", list_box_item = "button",
  flib_titlebar_drag_handle = "drag", inside_deep_frame_for_tabs = "deep",
  heading_1_label = "caption", heading_2_label = "caption", heading_3_label = "caption",
}
-- (headings keep their own, bigger font)
local KEEP_FONT = { heading_1_label = true, heading_2_label = true, heading_3_label = true }
-- what an element keeps through its new style: its size, stretch, alignment and margins (readable LuaStyle values)
local KEEP = { "minimal_width", "maximal_width", "minimal_height", "maximal_height", "natural_width",
  "natural_height", "horizontally_stretchable", "vertically_stretchable", "horizontally_squashable",
  "vertically_squashable", "horizontal_align", "vertical_align", "top_margin", "right_margin", "bottom_margin",
  "left_margin", "single_line" }

--- themes a GUI built with the game's styles: every element whose style has a role (ADOPT) gets that role, keeping
--- its size, stretch, alignment and margins (they become its tweak). A window frame at the root becomes "window".
--- Elements with styles of their own (another mod's) stay as they are. Call it again after adding elements: only
--- the new ones are themed.
function M.adopt(root)
  local th = M.of(game.get_player(root.player_index))
  local function visit(el, top)
    local name = el.style and el.style.name
    -- (already themed: left alone; a mod that put a game style back on it gets that style's role again)
    local role = name and name:sub(1, 5) ~= "fstd_" and ADOPT[name]
    if role == "window" and not top then role = "section" end  -- (a frame inside a window: a panel)
    if role then
      local t = el.tags.fstd_tweak
      if not t then
        t = {}
        local st = el.style
        for _, k in ipairs(KEEP) do
          local ok, v = pcall(function() return st[k] end)
          if ok and v ~= nil then t[k] = v end
        end
        if KEEP_FONT[name] then
          local ok, f = pcall(function() return st.font end)
          if ok and f then t.font = type(f) == "string" and f or f.name end
        end
      end
      M.apply(el, role, t, th)
    end
    for _, c in pairs(el.children) do visit(c, false) end
  end
  visit(root, true)
  return root
end

--- the close icon for a theme: black on light themes
function M.close_sprite(th)
  local t = themes.by_name[th.carrier]
  return t and t.light and "utility/close_black" or "utility/close"
end

local function walk(el, th)
  if el.tags.fstd_close then el.sprite = M.close_sprite(th) end
  local role = el.tags.fstd_role
  -- (only what still has a theme's style: a mod may have given an element a style of its own since)
  if role and el.style.name:sub(1, 5) == "fstd_" then M.apply(el, role, nil, th) end
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
  local name, data = frame.tags.fstd_confirm_window, frame.tags.data
  frame.destroy()
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
  end,
  [defines.events.on_gui_location_changed] = function(e)
    local el = e.element
    if ours(el) and el.tags.fstd_window then M.follow(el) end
  end,
  [defines.events.on_tick] = function(e)
    if e.tick % 30 ~= 0 then return end
    local name = "fstd_toasts_" .. script.mod_name
    for _, player in pairs(game.connected_players) do
      local box = player.gui.screen[name]
      if box then
        for _, t in pairs(box.children) do
          if t.tags.fstd_until and t.tags.fstd_until <= e.tick then t.destroy() end
        end
        if #box.children == 0 then box.destroy() end
      end
    end
  end,
}

return M
