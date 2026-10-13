-- fse-std themes in a real client: a bpgen-like panel made with the theme library, shot in every theme; a live
-- colour edit read back from the engine; the game's own windows coloured. Writes theme-result.json and
-- theme-*.png to script-output, then theme-done.txt.

local events = require("__fse-std__/events")
local theme = require("__fse-std__/theme")
local themes = require("__fse-std__/themes")
local window = require("__fse-std__/window")

local THEMES = { "vanilla", "compact", "flat", "blueprint", "platform", "vulcanus", "gleba", "fulgora", "aquilo",
  "crt", "glass", "glassdark" }
local result = { shots = {}, checks = {} }

local function check(name, ok, detail)
  result.checks[#result.checks + 1] = { name = name, ok = ok and true or false, detail = detail }
end

local function shot(name)
  local p = game.get_player(1)
  game.take_screenshot({ player = 1, path = "theme-" .. name .. ".png", show_gui = true,
    resolution = { p.display_resolution.width, p.display_resolution.height }, zoom = 1, daytime = 0 })
  result.shots[#result.shots + 1] = name
end

-- the bpgen window's Line tab, made of themed components
local function panel(player)
  local _, content = window.create(player, { name = "theme_test_panel", title = "bpgen", width = 640, height = 470,
    themed = true, close = true })
  local top = content.add({ type = "flow", direction = "horizontal" })
  theme.tabs(top, { "Line", "Mall", "Base", "Extend", "Bus" }, 1, "tt_tab")
  local push = top.add({ type = "empty-widget" })
  push.style.horizontally_stretchable = true
  theme.add(top, { type = "checkbox", caption = "Only unlocked", state = true }, "check")
  local body = content.add({ type = "flow", direction = "horizontal" })
  local left = body.add({ type = "flow", direction = "vertical" })
  local sec = theme.section(left, "Recipe")
  local row = sec.add({ type = "flow", direction = "horizontal" })
  theme.add(theme.field(row, "Recipe"), { type = "choose-elem-button", elem_type = "recipe", recipe = "iron-gear-wheel" }, "slot")
  theme.add(theme.field(row, "Machine"), { type = "choose-elem-button", elem_type = "entity", entity = "assembling-machine-2" }, "slot")
  theme.add(theme.field(row, "Per minute"), { type = "textfield", text = "120" }, "field", { width = 70 })
  theme.add(theme.field(row, "Belt"), { type = "choose-elem-button", elem_type = "entity", entity = "transport-belt" }, "slot")
  local mods = theme.section(left, "Modules & beacons")
  local mrow = mods.add({ type = "flow", direction = "horizontal" })
  theme.add(theme.field(mrow, "Machine modules"), { type = "choose-elem-button", elem_type = "item", item = "speed-module" }, "slot")
  theme.add(theme.field(mrow, "Beacon"), { type = "choose-elem-button", elem_type = "entity" }, "slot")
  local go = left.add({ type = "flow", direction = "horizontal" })
  theme.add(go, { type = "button", caption = "Plan" }, "ok")
  theme.add(go, { type = "button", caption = "What's short?" }, "button")
  theme.add(go, { type = "button", caption = "Check my bus" }, "button")
  theme.add(left, { type = "label", caption = "Planned: 6 assemblers, 2 belts in, 1 out." }, "dim")
  local right = theme.add(body, { type = "frame", direction = "vertical" }, "deep", { width = 220, vertically_stretchable = true })
  theme.add(right, { type = "label", caption = "(the blueprint preview)" }, "dim")
  local tools = right.add({ type = "flow", direction = "horizontal" })
  theme.add(tools, { type = "button", caption = "-" }, "tool")
  theme.add(tools, { type = "button", caption = "+" }, "tool")
  theme.add(tools, { type = "button", caption = "Fit" }, "button", { minimal_width = 0 })
  theme.add(right, { type = "button", caption = "Blueprint to cursor" }, "ok")
end

-- every other component, in a second window
local function parts(player)
  local _, content = window.create(player, { name = "theme_test_parts", title = "Components", width = 560,
    height = 640, themed = true })
  local top = content.add({ type = "flow", direction = "horizontal" })
  theme.stat(top, "128/min", "Gears")
  theme.stat(top, "93%", "Uptime")
  local chips = top.add({ type = "flow", direction = "vertical" })
  theme.badge(chips, "3 short")
  theme.badge(chips, "unlocked")
  theme.add(top, { type = "button", caption = "Build it" }, "pulse")
  theme.progress(content, 0.3, { caption = "Research", text = "30%", auto = true })
  theme.progress(content, 0.85, { caption = "Belts", text = "85%" })
  theme.chart(content, { 3, 5, 8, 6, 9, 12, 10, 7, 11, 14, 13, 9, 6, 8, 12 }, { height = 50 })
  storage.graph = theme.graph(content, { 4, 6, 5, 9, 7, 11, 10, 14, 12, 15 }, { width = 480, height = 60 })
  theme.separator(content)
  theme.search(content, "test", "Search recipes")
  local row = content.add({ type = "flow", direction = "horizontal" })
  theme.list(row, { "Iron gear", "Copper cable", "Circuit", "Pipe" }, 2).style.height = 100
  local inputs = row.add({ type = "flow", direction = "vertical" })
  theme.add(inputs, { type = "checkbox", caption = "Use modules", state = true }, "check")
  theme.add(inputs, { type = "radiobutton", caption = "Belts", state = true }, "radio")
  theme.add(inputs, { type = "radiobutton", caption = "Bots", state = false }, "radio")
  theme.add(inputs, { type = "slider", minimum_value = 0, maximum_value = 10, value = 6 }, "slider")
  theme.add(inputs, { type = "drop-down", items = { "Yellow belt", "Red belt" }, selected_index = 1 }, "dropdown")
  local body = theme.fold(content, "Fine-tune", true)
  local sc = theme.add(body, { type = "scroll-pane" }, "scroll", { height = 60, horizontally_stretchable = true })
  for i = 1, 8 do theme.add(sc, { type = "label", caption = "Row " .. i }, "text") end
  local _, tabs = theme.tabbed(content, { "Input", "Output" })
  theme.add(tabs[1], { type = "label", caption = "Tab content" }, "text")
end

-- does fse-std's probe give every role's image sets (the engine paths live colours write through)?
local function role_paths(player)
  local probe = player.gui.screen.fstd_probe
  local bad = {}
  for role in pairs(themes.ROLES) do
    local el = probe["t_" .. role] or (probe["pane_t_" .. role] and probe["pane_t_" .. role]["t_" .. role])
    if el then
      for _, st in ipairs(themes.sets(role)) do
        if st.none then goto continue end
        local w = native.read(el, "guiElement.target.widget")
        local cur = type(w) == "table" and native.read(w, "style.parent")
        for _, f in ipairs(st[2]) do
          cur = type(cur) == "table" and cur.ptr and native.read(cur, f) or nil
        end
        local sp = type(cur) == "table" and cur.ptr and native.read(cur, "base.center.value.sprite")
        if not (type(sp) == "table" and sp.ptr) then
          sp = type(cur) == "table" and cur.ptr and native.read(cur, "base.top.value.sprite")  -- (no centre: a frame of edges)
        end
        if not (type(sp) == "table" and sp.ptr) then bad[#bad + 1] = role .. ":" .. table.concat(st[2], ".") end
        ::continue::
      end
    end
  end
  return bad
end

-- a frame in the game's own styles (what "colour the game's own windows" reaches)
local function vanilla_frame(player)
  local f = player.gui.screen.add({ type = "frame", name = "theme_test_vanilla", caption = "A game window", direction = "vertical" })
  local inner = f.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  inner.add({ type = "label", caption = "inside_shallow_frame" })
  inner.add({ type = "button", caption = "A game button" })
  inner.add({ type = "checkbox", caption = "A game checkbox", state = false })
  inner.add({ type = "label", caption = "clickable_label", style = "clickable_label" })
  local deep = inner.add({ type = "frame", style = "inside_deep_frame", direction = "vertical" })
  deep.style.padding = 6
  deep.add({ type = "label", caption = "inside_deep_frame" })
  local pane = f.add({ type = "tabbed-pane" })
  for i, n in ipairs({ "First", "Second" }) do
    local tab = pane.add({ type = "tab", caption = n })
    local c = pane.add({ type = "flow", direction = "vertical" })
    c.add({ type = "label", caption = n .. " tab" })
    pane.add_tab(tab, c)
  end
  pane.selected_tab_index = 1
end

-- a window built with the game's styles, then adopted: a title bar with its buttons, a heading, a count
local function adopt_window(player)
  local af = player.gui.screen.add({ type = "frame", name = "theme_test_adopt", direction = "vertical" })
  local bar = af.add({ type = "flow", direction = "horizontal" })
  bar.add({ type = "label", caption = "Adopted", style = "frame_title" })
  local drag = bar.add({ type = "empty-widget", style = "draggable_space_header" })
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  bar.add({ type = "sprite-button", name = "tt_search", style = "frame_action_button", sprite = "utility/search",
    hovered_sprite = "utility/search", clicked_sprite = "utility/search" })
  bar.add({ type = "sprite-button", name = "tt_expand", style = "frame_action_button", sprite = "utility/expand" })
  bar.add({ type = "sprite-button", name = "tt_close", style = "frame_action_button", sprite = "utility/close" })
  local ain = af.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  ain.add({ type = "label", name = "tt_heading", caption = "A heading", style = "caption_label" })
  ain.add({ type = "label", caption = "A plain label" })
  ain.add({ type = "label", name = "tt_count", caption = "42", style = "count_label" })
  ain.add({ type = "checkbox", caption = "Unticked", state = false })
  ain.add({ type = "checkbox", caption = "Ticked", state = true })
  return af, ain
end

-- engine reads (native): an element's named style, and an image set's sprites at an engine path
local function P(v) if type(v) == "table" and v.ptr and v.ptr ~= 0 then return v end end
local function style_obj(el)
  local w = el and P(native.read(el, "guiElement.target.widget"))
  return w and P(native.read(w, "style.parent"))
end
local function at(st, epath)
  local cur = st
  for _, f in ipairs(epath) do cur = cur and P(native.read(cur, f)) end
  return cur
end
local function set_sprites(st, epath, layer)
  local cur = at(st, epath)
  if not cur then return nil end
  local out = {}
  for _, part in ipairs({ "center", "leftTop", "top", "left", "right", "bottom" }) do
    local sp = P(native.read(cur, (layer or "base") .. "." .. part .. ".value.sprite"))
    if sp then out[#out + 1] = sp end
  end
  return out
end

-- two writers (a game style's own token and how, and the roles' pass over the game's styles) must never share a
-- sprite: it would take whichever colour came last
local function conflicts(p)
  local probe = p.gui.screen.fstd_probe
  local holder = probe and probe.game
  if not holder then return { "no game probe" }, 0 end
  local owner, bad, n = {}, {}, 0
  local function take(sp, k, who)
    n = n + 1
    local o = owner[sp.ptr]
    if o and o.k ~= k and #bad < 12 then bad[#bad + 1] = who .. " " .. k .. " vs " .. o.who .. " " .. o.k end
    owner[sp.ptr] = o or { k = k, who = who }
  end
  for i, g in ipairs(themes.game_styles()) do
    local el = holder["g_" .. i] or (holder["pane_g_" .. i] and holder["pane_g_" .. i]["g_" .. i])
    local st = style_obj(el)
    for _, s in ipairs(g.sets) do
      for _, sp in ipairs(st and set_sprites(st, s[1]) or {}) do take(sp, s[2] .. "/" .. s[3], g.style) end
    end
  end
  local game = themes.game_names()
  for role, r in pairs(themes.ROLES) do
    if not r.own and not game[r.vanilla] then
      local el = probe["v_" .. role] or (probe["pane_v_" .. role] and probe["pane_v_" .. role]["v_" .. role])
      local st = style_obj(el)
      for _, s in ipairs(themes.sets(role)) do
        local nest = r.nest and r.nest[s[1][1]]
        if s[3] ~= "white" and not (nest and nest.parent and game[nest.parent]) then
          for _, sp in ipairs(st and set_sprites(st, s[2]) or {}) do take(sp, s[3] .. "/" .. s[4], "v_" .. role) end
        end
      end
    end
  end
  return bad, n
end

local function entry(name)
  for _, g in ipairs(themes.game_styles()) do if g.style == name then return g end end
end
local function set_token(name, epath)
  local g = entry(name)
  for _, s in ipairs(g and g.sets or {}) do
    if table.concat(s[1], ".") == epath then return s[2] .. "/" .. s[3] .. (s.flat and "/flat" or "") end
  end
end
local function font_token(name, epath)
  local g = entry(name)
  for _, f in ipairs(g and g.fonts or {}) do
    if table.concat(f[1], ".") == epath then return f[2] end
  end
end

-- what data-final-fixes.lua listed: tokens from the art a style inherits, anchored skips, fonts only on flat art
local function listing_checks()
  local flat = settings.startup["fstd-flat-game"].value
  check("listing: tokens follow the inherited art", set_token("inside_deep_frame", "graphicalSet"):find("^deep/")
    and set_token("slot_sized_button", "defaultGraphicalSet"):find("^btn/")
    and set_token("slot", "defaultGraphicalSet"):find("^btn/")
    and set_token("slot_button", "defaultGraphicalSet"):find("^slot/"),
    serpent.line({ set_token("inside_deep_frame", "graphicalSet"), set_token("slot_sized_button", "defaultGraphicalSet"),
      set_token("slot", "defaultGraphicalSet"), set_token("slot_button", "defaultGraphicalSet") }))
  check("listing: a selected tab is the content's colour, not a hovered one",
    set_token("tab", "selectedGraphicalSet") and set_token("tab", "selectedGraphicalSet"):find("^inset/")
    and set_token("tab", "hoveredGraphicalSet"):find("^btn/lighter"),
    serpent.line({ set_token("tab", "selectedGraphicalSet"), set_token("tab", "hoveredGraphicalSet") }))
  check("listing: red buttons left alone", entry("red_button") == nil and entry("tool_button_red") == nil)
  if flat then  -- (the game's white icons: their buttons' tiles go dark on light themes)
    check("flat: icon buttons have tiles of their own, dark on light themes",
      set_token("shortcut_bar_button", "defaultGraphicalSet") == "btn/icon_same/flat"
      and (set_token("side_menu_button", "defaultGraphicalSet") or ""):find("/icon_same/flat$")
      and (set_token("frame_action_button", "defaultGraphicalSet") or ""):find("/icon_same/flat$")
      and set_token("slot_sized_button", "defaultGraphicalSet") == "btn/same/flat",
      serpent.line({ set_token("shortcut_bar_button", "defaultGraphicalSet"),
        set_token("side_menu_button", "defaultGraphicalSet"), set_token("frame_action_button", "defaultGraphicalSet"),
        set_token("slot_sized_button", "defaultGraphicalSet") }))
    local light = themes.derive(themes.by_name.aquilo.tokens.btn, "icon_same")
    check("an icon button's tile is dark on a light theme", not themes.is_light(light), serpent.line(light))
  end
  check("listing: buttons' selected sets in the accent", (set_token("button", "selectedGraphicalSet") or "btn_on"):find("^btn_on")
    and set_token("slot_button", "selectedGraphicalSet"):find("^btn_on"), set_token("slot_button", "selectedGraphicalSet"))
  local labels = font_token("label", "fontColor")
  if flat then
    check("flat: frames keep drawing outside (draw_type outer)", set_token("inside_deep_frame", "graphicalSet"):find("/flat$"),
      set_token("inside_deep_frame", "graphicalSet"))
    check("flat: text colours where the art is flat (labels, checkboxes, buttons, tabs)", labels == "ink"
      and font_token("checkbox", "fontColor") == "ink" and font_token("radiobutton", "fontColor") == "ink"
      and font_token("button", "defaultFontColor") == "btn_ink" and font_token("tab", "selectedFontColor") == "caption"
      and font_token("tab", "defaultFontColor") == "btn_ink",
      serpent.line({ labels, font_token("checkbox", "fontColor"), font_token("button", "defaultFontColor"),
        font_token("tab", "selectedFontColor"), font_token("tab", "defaultFontColor") }))
    check("flat: coloured text keeps its colour (clickable hover, hyperlinks)",
      font_token("clickable_label", "hoveredFontColor") == nil and font_token("hyperlink_label", "fontColor") == nil
      and font_token("label", "hoveredFontColor") == nil)
  else
    check("not flat: no text colours listed", labels == nil, tostring(labels))
  end
end

-- the engine draws a style without a set of its own with its parent's: only own sets are written
local function own_set_check(p)
  local f = p.gui.screen.theme_test_vanilla
  local inner = f and f.children[1]
  local st = style_obj(inner)
  local own = st and at(st, { "graphicalSet" })
  local parent = st and P(native.read(st, "parent"))
  local pset = parent and at(parent, { "graphicalSet" })
  check("engine: a child style without a set of its own has none (its parent's is drawn)", st ~= nil and own == nil
    and pset ~= nil, serpent.line({ style = inner and inner.style.name, own = own, parent = pset }))
end

-- the engine's tint of a themed style's window sprite (through the probe fse-std keeps)
local function window_tint(player)
  local probe = player.gui.screen.fstd_probe
  if not probe then return nil, "no probe" end
  local w = native.read(probe.t_window, "guiElement.target.widget")
  if type(w) ~= "table" or not w.ptr then return nil, "no widget (hidden probe?)" end
  local gs = native.read(w, "style.parent.graphicalSet")
  if type(gs) ~= "table" or not gs.ptr then return nil, "no image set" end
  return native.read(gs, "base.center.value.sprite.tint")
end




-- ---------------------------------------------------------------------------------------------------------------
-- window scale (fse-std 0.8): a window built at 100 %, drawn at 150 % in place (the setting), at its own Size, back;
-- sizes read through LuaStyle, paddings measured from the engine's widgets, fonts swapped, attached frames re-placed
-- and the window kept on the screen after a (simulated) display change, capped to fit, adopt at 150 %

-- a style value as drawn: what Lua set (LuaStyle reads back only that), else the style's own (fse-std's fstd-layout)
local function sread(el, k)
  local ok, v = pcall(function() return el.style[k] end)
  if ok and v ~= nil then return v end
  local l = theme.scale.layout(el.style.name)
  return l and l[k] or nil
end

-- an element's drawn size in pixels (the engine's widget, a tick after a change)
local function widget_size(el)
  local w = el and el.valid and P(native.read(el, "guiElement.target.widget"))
  if not w then return nil end
  return { w = tonumber(native.read(w, "size.width")), h = tonumber(native.read(w, "size.height")) }
end

local function scale_window(p, name)
  local frame, content = window.create(p, { name = name, title = "Scale", width = 360, height = 300, themed = true,
    settings = true, esc = false })
  local sec = theme.section(content, "Section", nil, "sw_sec")
  local row = sec.add({ type = "flow", name = "sw_row", direction = "horizontal" })
  theme.add(row, { type = "sprite-button", name = "sw_slot", sprite = "item/iron-plate" }, "slot")
  theme.add(row, { type = "textfield", name = "sw_field", text = "120" }, "field", { width = 70 })
  theme.add(row, { type = "label", name = "sw_label", caption = "A label" }, "text")
  theme.add(sec, { type = "drop-down", name = "sw_drop", items = { "Yellow belt", "Red belt" }, selected_index = 1 },
    "dropdown")
  local plain = content.add({ type = "flow", name = "sw_plain", direction = "horizontal" })
  plain.style.horizontal_spacing = 5
  plain.add({ type = "sprite-button", name = "sw_pslot", style = "slot_button", sprite = "item/copper-plate" })
  local fixed = plain.add({ type = "label", name = "sw_fixed", caption = "fixed 80" })
  fixed.style.width = 80
  local hold = content.add({ type = "flow", name = "sw_hold", direction = "horizontal" })
  local box = theme.add(hold, { type = "frame", name = "sw_box", direction = "vertical" }, "inset")
  box.add({ type = "empty-widget", name = "sw_block" }).style.size = { 100, 40 }
  theme.scale_tree(frame)
  theme.tab_rail(frame, { "A", "B" }, 1, "sw_rail")
  return frame
end

local function parts_of(frame)
  local content = frame.children[2]
  local row = content.sw_sec.sw_row
  return { frame = frame, slot = row.sw_slot, field = row.sw_field, label = row.sw_label, plain = content.sw_plain,
    pslot = content.sw_plain.sw_pslot, fixed = content.sw_plain.sw_fixed, box = content.sw_hold.sw_box,
    block = content.sw_hold.sw_box.sw_block }
end

local function reads(frame)
  local q = parts_of(frame)
  return { frame = sread(q.frame, "minimal_width"), frame_h = sread(q.frame, "minimal_height"),
    style = q.frame.style.name, slot = sread(q.slot, "minimal_width"), field = sread(q.field, "minimal_width"),
    font = sread(q.label, "font"), pslot = sread(q.pslot, "minimal_width"),
    spacing = sread(q.plain, "horizontal_spacing"), fixed = sread(q.fixed, "minimal_width") }
end

-- a window built with the game's styles, adopted
local function adopt_win(p, name)
  local af = p.gui.screen.add({ type = "frame", name = name, direction = "vertical" })
  af.style.width = 300
  af.style.height = 200
  local bar = af.add({ type = "flow", direction = "horizontal" })
  bar.add({ type = "label", caption = "Adopted", style = "frame_title" })
  bar.add({ type = "sprite-button", name = "aw_close", style = "frame_action_button", sprite = "utility/close" })
  local ain = af.add({ type = "frame", name = "aw_in", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  ain.add({ type = "button", name = "aw_button", caption = "A game button" })
  ain.add({ type = "sprite-button", name = "aw_slot", style = "slot_button", sprite = "item/iron-gear-wheel" })
  ain.add({ type = "label", name = "aw_label", caption = "A label" })
  theme.adopt(af)
  return af
end
local function adopt_reads(af)
  local ain = af.aw_in
  return { button = sread(ain.aw_button, "minimal_width"), button_h = sread(ain.aw_button, "minimal_height"),
    slot = sread(ain.aw_slot, "minimal_width"), font = sread(ain.aw_label, "font"),
    close = sread(af.children[1].aw_close, "minimal_width"), frame = sread(af, "minimal_width") }
end

local scaled_heard = {}
window.on_scale(function(_, name, f, info)
  scaled_heard[#scaled_heard + 1] = name .. ":" .. f .. (info.capped and ":capped" or "")
end)

local sc_state = {}
local function near(a, b, d) return a and b and math.abs(a - b) <= (d or 0) end

local function scale_step(p, u, e)
  local st = sc_state
  local ds = p.display_scale
  if u == 0 then
    remote.call("fse-std", "set_vanilla_gui", 1, false)
    remote.call("fse-std", "set_theme", 1, "flat")
    local frame = scale_window(p, "scale_win")
    frame.location = { math.floor(140 * ds), math.floor(60 * ds) }
    theme.follow(frame)
    st.r100 = reads(frame)
    local af = adopt_win(p, "adopt100")
    st.a100 = adopt_reads(af)
    af.destroy()
    check("scale 100 %: nothing scaled, no marks", frame.tags.fstd_scale == 1 and frame.tags.fstd_sc == nil
      and parts_of(frame).slot.tags.fstd_sc == nil and st.r100.style == "fstd_flat_window", serpent.line(st.r100))
  elseif u == 4 then
    st.box100 = widget_size(parts_of(p.gui.screen.scale_win).box)
    st.block100 = widget_size(parts_of(p.gui.screen.scale_win).block)
    st.rail100 = p.gui.screen.scale_win__left.location
    remote.call("fse-std", "set_window_scale", 1, 150)
  elseif u == 8 then
    local frame = p.gui.screen.scale_win
    local r, a = reads(frame), st.r100
    local function x(v) return math.floor(v * 1.5 + 0.5) end
    check("scale 150 %: the setting rescales a window in place (sizes x1.5 read through LuaStyle)",
      r.frame == x(a.frame) and r.frame_h == x(a.frame_h) and r.slot == x(a.slot) and r.field == x(a.field)
      and r.pslot == x(a.pslot) and r.spacing == x(a.spacing) and r.fixed == x(a.fixed), serpent.line({ r, a }))
    check("scale 150 %: the window's frame style is the step's copy (its flows' spacing)",
      r.style == "fstd_flat_window_x150", r.style)
    check("scale 150 %: fonts swapped for their 150 % copies (a drop-down: its step's style)",
      r.font == "fstd-s150-" .. tostring(a.font) and parts_of(frame).frame.children[2].sw_sec.sw_drop.style.name
      == "fstd_flat_dropdown_x150", tostring(r.font))
    local f, want, capped = window.scale(p, "scale_win")
    check("window.scale says 150 %", f == 1.5 and want == 1.5 and not capped, serpent.line({ f, want, capped }))
    check("on_scale heard it", scaled_heard[#scaled_heard] == "scale_win:1.5", serpent.line(scaled_heard))
    local rail = p.gui.screen.scale_win__left
    local loc = frame.location
    local o = rail.tags.fstd_attach
    check("an attached rail is scaled and re-placed", sread(rail, "minimal_width") == x(o.w)
      and near(rail.location.x, math.floor(loc.x - (o.w - 6) * ds * 1.5), 1),
      serpent.line({ rail = rail.location, w = sread(rail, "minimal_width"), win = loc }))
    theme.toast(p, "Scaled", { window = frame, seconds = 3 })
    local box = p.gui.screen["fstd_toasts_theme-test"]
    local t = box and box.children[#box.children]
    check("a toast of a 150 % window is 150 %", t and sread(t, "minimal_width") == 480, t and sread(t, "minimal_width"))
  elseif u == 12 then
    local q = parts_of(p.gui.screen.scale_win)
    local b, k = widget_size(q.box), widget_size(q.block)
    -- (the inset round a 100 x 40 block: the block 1.5 times as big, the inset's padding (the theme's, 10) too; the
    -- frame's border, drawn by the engine, stays)
    local pad = themes.by_name.flat.pad * ds
    local grow = b and k and st.box100 and st.block100
      and { w = (b.w - k.w) - (st.box100.w - st.block100.w), h = (b.h - k.h) - (st.box100.h - st.block100.h) }
    check("paddings scale (an inset measured in the engine)", grow and near(k.w, 150 * ds, 1)
      and near(k.h, 60 * ds, 1) and near(grow.h, pad, 2),
      serpent.line({ box100 = st.box100, block100 = st.block100, box = b, block = k, grow = grow, want = pad }))
    -- (live colours: a scaled frame style draws the same sprites as its base style, which the probe's writes reach)
    local probe = p.gui.screen.fstd_probe
    local pw = P(native.read(probe.t_window, "guiElement.target.widget"))
    local fw = P(native.read(q.frame, "guiElement.target.widget"))
    local a = pw and P(native.read(pw, "style.parent.graphicalSet"))
    -- (the step's copy has no set of its own: the engine draws its parent's, the base style's)
    local c = fw and (P(native.read(fw, "style.parent.graphicalSet")) or P(native.read(fw, "style.parent.parent.graphicalSet")))
    local sa = a and P(native.read(a, "base.center.value.sprite"))
    local sb = c and P(native.read(c, "base.center.value.sprite"))
    st.shared = sa and sb and sa.ptr == sb.ptr
    check("a scaled frame style shares its base's sprites (live colours reach it)", st.shared,
      serpent.line({ a = sa and sa.ptr, b = sb and sb.ptr }))
    shot("scale-150")
  elseif u == 40 then
    local frame = p.gui.screen.scale_win
    local q = parts_of(frame)
    q.fixed.style.width = 50  -- (a mod's own write, in GUI units at 100 %)
    theme.scale_tree(frame)
    theme.style(q.pslot, { size = 32 })
    check("a mod's own size set after scaling is scaled by scale_tree; theme.style sets design values",
      sread(q.fixed, "minimal_width") == 75 and sread(q.pslot, "minimal_width") == 48,
      serpent.line({ sread(q.fixed, "minimal_width"), sread(q.pslot, "minimal_width") }))
    theme.style(q.pslot, { size = 40 })
    q.fixed.style.width = 80
    theme.scale_tree(frame)
    remote.call("fse-std", "set_theme", 1, "aquilo")
  elseif u == 44 then
    local r, a = reads(p.gui.screen.scale_win), st.r100
    check("a theme change keeps the scale", r.style == "fstd_aquilo_window_x150" and r.slot == 60
      and r.field == math.floor(a.field * 1.5 + 0.5) and r.fixed == 120, serpent.line(r))
    window.set_scale(p, "scale_win", 1.25)
  elseif u == 48 then
    local r, a = reads(p.gui.screen.scale_win), st.r100
    local f, want = window.scale(p, "scale_win")
    check("a window's own Size wins over the setting", r.frame == math.floor(a.frame * 1.25 + 0.5)
      and r.style == "fstd_aquilo_window_x125" and f == 1.25 and want == 1.25
      and scaled_heard[#scaled_heard] == "scale_win:1.25", serpent.line({ r, f, want, scaled_heard[#scaled_heard] }))
    local m = theme.menu(p.gui.screen.scale_win, { size = { 220, 100 } })
    local dd = window.size_setting(m, "scale_win")
    check("Size drop-down: 'Default', then the sizes; 125 % picked", dd.selected_index == 1 + 5 and #dd.items == 9,
      serpent.line({ dd.selected_index, #dd.items }))
    dd.selected_index = 1
    window.handlers[defines.events.on_gui_selection_state_changed]({ element = dd, player_index = 1, tick = e.tick })
  elseif u == 52 then
    local frame = p.gui.screen.scale_win
    local r = reads(frame)
    check("Size 'Default' follows the setting again", r.frame == math.floor(st.r100.frame * 1.5 + 0.5)
      and r.style == "fstd_aquilo_window_x150", serpent.line(r))
    local m = p.gui.screen.scale_win__menu
    if m then theme.menu(frame, { size = { 220, 100 } }) end  -- (closed)
    -- the screen changed (simulated: the event's handler): a window half off the screen comes back with its rail
    local res = p.display_resolution
    frame.location = { res.width - 100, res.height - 80 }
    theme.handlers[defines.events.on_player_display_resolution_changed]({ player_index = 1, tick = e.tick })
    local loc, rail = frame.location, p.gui.screen.scale_win__left
    local sc = ds * 1.5
    check("display change: the window is kept on the screen", loc.x + 360 * sc <= res.width + 1
      and loc.y + 300 * sc <= res.height + 1, serpent.line({ loc = loc, res = res }))
    frame.location = { 0, math.floor(100 * ds) }
    theme.handlers[defines.events.on_player_display_scale_changed]({ player_index = 1, tick = e.tick })
    loc = frame.location
    check("display change: what sticks out stays on the screen, and follows", rail.location.x >= 0
      and near(rail.location.x, math.floor(loc.x - (rail.tags.fstd_attach.w - 6) * sc), 1),
      serpent.line({ rail = rail.location, win = loc }))
    -- capped: a window too big for the screen at 150 %
    local w = math.floor(res.width / ds * 0.8)
    local big = window.create(p, { name = "scale_big", title = "Big", width = w, height = 300, themed = true, esc = false })
    local f, want, capped = window.scale(p, "scale_big")
    check("a window too big at 150 % is capped to fit (window.scale says so)", f < 1.5 and want == 1.5 and capped
      and w * f * ds <= res.width and sread(big, "minimal_width") == math.floor(w * f + 0.5),
      serpent.line({ f, want, capped, w, sread(big, "minimal_width") }))
    big.destroy()
    local af = adopt_win(p, "adopt150")
    local ar, a1 = adopt_reads(af), st.a100
    local function x(v) return v and math.floor(v * 1.5 + 0.5) end
    check("adopt at 150 %: the game's styles scaled (button, slot, title bar button, the window's size), fonts too",
      ar.button == x(a1.button) and ar.button_h == x(a1.button_h) and ar.slot == x(a1.slot)
      and ar.close == x(a1.close) and ar.frame == x(a1.frame) and ar.font == "fstd-s150-" .. tostring(a1.font),
      serpent.line({ ar, a1 }))
    af.location = { math.floor(560 * ds * 1.5), math.floor(60 * ds) }
    st.adopted = af
  elseif u == 56 then
    shot("scale-150-aquilo")
  elseif u == 80 then
    if st.adopted and st.adopted.valid then st.adopted.destroy() end
    remote.call("fse-std", "set_window_scale", 1, 100)
  elseif u == 84 then
    local frame = p.gui.screen.scale_win
    local r, a = reads(frame), st.r100
    local q = parts_of(frame)
    check("back at 100 %: every size as built, marks gone (a themed element its style again)", r.frame == a.frame
      and r.slot == a.slot and q.slot.style.minimal_width == nil and sread(q.label, "font") == a.font
      and pcall(function() return q.label.style.font end)
      and r.field == a.field and r.pslot == a.pslot and r.spacing == a.spacing and r.fixed == a.fixed
      and r.font == a.font and r.style == "fstd_aquilo_window" and q.slot.tags.fstd_sc == nil
      and q.pslot.tags.fstd_sc == nil and frame.tags.fstd_scale == 1, serpent.line({ r, a }))
    local rail = p.gui.screen.scale_win__left
    local ft = p.gui.screen.theme_test_parts__top
    check("back at 100 %: attached frames too (a rail, another window's folder tabs)", rail
      and sread(rail, "minimal_width") == rail.tags.fstd_attach.w and rail.tags.fstd_sc == nil
      and (not ft or sread(ft, "minimal_width") == ft.tags.fstd_attach.w),
      serpent.line({ rail and sread(rail, "minimal_width"), ft and sread(ft, "minimal_width") }))
  elseif u == 88 then
    local b = widget_size(parts_of(p.gui.screen.scale_win).box)
    check("back at 100 %: the inset measures as before", b and st.box100 and b.w == st.box100.w and b.h == st.box100.h,
      serpent.line({ st.box100, b }))
    shot("scale-100-back")
  elseif u == 110 then
    p.gui.screen.scale_win.destroy()
    for _, n in ipairs({ "scale_win__left", "scale_win__menu" }) do
      if p.gui.screen[n] then p.gui.screen[n].destroy() end
    end
    -- (as before this phase: the save the second run loads has the game's windows coloured)
    remote.call("fse-std", "set_theme", 1, settings.startup["fstd-flat-game"].value and "aquilo" or "fulgora")
    remote.call("fse-std", "set_vanilla_gui", 1, true)
  end
end

local T0 = 60
local STEP = 6
local SCALE0 = #THEMES * STEP + 262  -- (the window scale phase, ~110 ticks)
local END = SCALE0 + 200

local handlers = {
  [defines.events.on_tick] = function(e)
    local p = game.get_player(1)
    if not p then return end
    local t = e.tick - T0
    if t > 0 then  -- (each tick's time: which ones are slow)
      local st = native.tick_stats()
      result.slow = result.slow or {}
      if st.last_ms > 20 then result.slow[#result.slow + 1] = { t = t - 1, ms = st.last_ms } end
    end
    if t == 0 then
      panel(p)
      parts(p)
      vanilla_frame(p)
      listing_checks()
      -- a window built with the game's styles, then adopted
      local af, ain = adopt_window(p)
      local ab = ain.add({ type = "button", caption = "Wide button" })
      ab.style.width = 150
      ain.add({ type = "button", caption = "Confirm", style = "confirm_button" })
      theme.adopt(af)
      -- (each game style as itself with its role's colours; the width its mod gave the button kept)
      check("adopt themes a game-styled window", af.style.name:find("^fstd_")
        and ain.style.name:find("_inset__inside_shallow_frame_with_padding$")
        and ab.style.name:find("_button__button$") and ab.style.minimal_width == 150,
        serpent.line({ af.style.name, ain.style.name, ab.style.name, ab.style.minimal_width }))
      -- (a subheader themed by fse-std before 0.7: themed again as the game's subheader)
      local old = ain.add({ type = "frame", style = "fstd_vanilla_section", tags = { fstd_role = "section", fstd_tweak = {
        top_margin = 0, right_margin = 0, bottom_margin = 0, left_margin = 0, minimal_height = 36, maximal_height = 36,
        vertically_stretchable = false } } })
      theme.adopt(af)
      check("adopt themes an older themed subheader again", old.style.name:find("_section__subheader_frame$")
        and old.style.minimal_height == 36, serpent.line({ old.style.name, old.style.minimal_height }))
      old.destroy()
      local bar = af.children[1]
      check("adopt themes the title bar's buttons and a count label", bar.tt_search.style.name:find("_close__frame_action_button$")
        and bar.tt_expand.style.name:find("_close__frame_action_button$") and ain.tt_count.style.name:find("_text__count_label$"),
        serpent.line({ bar.tt_search.style.name, bar.tt_expand.style.name, ain.tt_count.style.name }))
      local wf = window.create(p, { name = "adopt_sized", title = "Sized", width = 333, height = 222, esc = false })
      theme.adopt(wf)
      local tw = wf.tags.fstd_tweak or {}
      check("adopt keeps a window's size (what sticks to it follows it)", tw.width == 333 and tw.height == 222,
        serpent.line(tw))
      wf.destroy()
      check("a window takes Esc (it is the opened GUI)", p.opened and p.opened.name == "theme_test_panel",
        p.opened and p.opened.name)
      remote.call("fse-std", "open_theme", 1)
      local ed = p.gui.screen.fstd_theme_editor
      check("editor opens", ed ~= nil)
      check("probe made", p.gui.screen.fstd_probe ~= nil)
      -- the server's default theme: a player who never picked one follows it (99: no such player, no pick)
      local before = remote.call("fse-std", "theme", 99).name
      remote.call("fse-std", "set_default_theme", "gleba")
      local after = remote.call("fse-std", "theme", 99).name
      remote.call("fse-std", "set_default_theme", "vanilla")
      check("players without a pick follow the server's default", before == "vanilla" and after == "gleba",
        before .. " -> " .. after)
    elseif t == 1 then  -- (a tick after: window.create centres them first)
      local sc = p.display_scale
      p.gui.screen.theme_test_panel.location = { math.floor(20 * sc), math.floor(20 * sc) }
      p.gui.screen.theme_test_vanilla.location = { math.floor(20 * sc), math.floor(540 * sc) }
      p.gui.screen.theme_test_adopt.location = { math.floor(240 * sc), math.floor(540 * sc) }
      p.gui.screen.theme_test_parts.location = { math.floor(680 * sc), math.floor(20 * sc) }
      p.gui.screen.fstd_theme_editor.location = { math.floor(1260 * sc), math.floor(20 * sc) }
      result.scale = sc
      local pf = p.gui.screen.theme_test_panel
      theme.tab_rail(pf, { "Line", "Mall", "Base" }, 1, "tt_rail")
      theme.folder_tabs(p.gui.screen.theme_test_parts, { "Parts", "More" }, 1, "tt_folder", { along = -16 })
      local dock = theme.dock(pf, { size = { 260, 44 } })
      theme.add(dock, { type = "button", caption = "Blueprint" }, "ok", { minimal_width = 100 })
      theme.add(dock, { type = "button", caption = "Copy" }, "button", { minimal_width = 60 })
      theme.add(dock, { type = "button", caption = "Undo" }, "button", { minimal_width = 60 })
      theme.glow(pf)
      local rail = p.gui.screen.theme_test_panel__left
      check("tab rail sits left of the window", rail and rail.location.x < pf.location.x,
        serpent.line({ rail = rail and rail.location, win = pf.location }))
      pf.location = { pf.location.x + 30, pf.location.y + 10 }
      theme.follow(pf)
      check("attached frames follow the window", rail and rail.location.x < pf.location.x
        and p.gui.screen.theme_test_panel__bottom.location.y > pf.location.y,
        serpent.line({ rail = rail and rail.location, win = pf.location }))
      check("shortcut shows the theme window open", p.is_shortcut_toggled("fstd-theme"))
      -- a toast: next to its window (the opened one), never over it; clear of another mod's box of toasts
      theme.toast(p, "Blueprint copied", { seconds = 1 })
      local box = p.gui.screen["fstd_toasts_theme-test"]
      check("toast shows", box ~= nil)
      local r = box and box.tags.fstd_toast_rect
      local win = { x = pf.location.x, y = pf.location.y, w = 640 * sc, h = 470 * sc }
      local function over(a, b) return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h end
      check("toast next to its window, not over it", r and not over(r, win), serpent.line({ toast = r, window = win }))
      -- (nor over any other shown window: the adopted one under the dock, the theme window, ...)
      local hit
      for _, c in pairs(p.gui.screen.children) do
        if c.type == "frame" and c.visible and c.name ~= "fstd_probe" and c.location then
          local wr = c.name == "theme_test_adopt" and { x = c.location.x, y = c.location.y, w = 180 * sc, h = 200 * sc }
          if wr and r and over(r, wr) then hit = c.name end
        end
      end
      check("toast clear of the other windows", r and not hit, serpent.line({ toast = r, over = hit }))
      local fake = p.gui.screen.add({ type = "flow", name = "fstd_toasts_fake", tags = { fstd_toast_rect = r } })
      box.destroy()
      theme.toast(p, "Blueprint copied", { seconds = 1 })
      local r2 = p.gui.screen["fstd_toasts_theme-test"].tags.fstd_toast_rect
      check("toasts keep clear of another mod's", r and r2 and not over(r2, r) and not over(r2, win),
        serpent.line({ other = r, mine = r2 }))
      fake.destroy()
      local text = remote.call("fse-std", "export_theme", 1)
      local name = remote.call("fse-std", "import_theme", 1, text)
      check("a theme's text adds it back", type(name) == "string" and name:find("^custom_") ~= nil,
        tostring(text):sub(1, 40))
      local title
      for _, c in pairs(remote.call("fse-std", "themes")) do if c.name == name then title = c.title end end
      check("a shipped theme's copy is called Custom (Vanilla)", title == "Custom (Vanilla)", tostring(title))
    elseif t > 0 and t <= #THEMES * STEP and t % STEP == 0 then
      local i = t / STEP
      local function pane()
        local ed = p.gui.screen.fstd_theme_editor
        return ed and ed.children[2].fstd_ed_pane
      end
      local before = pane() and pane().index
      remote.call("fse-std", "set_theme", 1, THEMES[i])
      if i == 3 then  -- (after i == 1: the list changed by the import, made again once)
        check("theme window updates in place (its view stays)", before and pane() and pane().index == before,
          serpent.line({ before, pane() and pane().index }))
        local cells = pane() and pane().fstd_ed_gallery.fstd_ed_cells
        local on
        for _, c in pairs(cells and cells.children or {}) do if c.children[1].toggled then on = c.tags.theme end end
        check("theme window shows the picked theme", on == THEMES[i], tostring(on))
      end
      local style = p.gui.screen.theme_test_panel.style.name
      check("panel restyled: " .. THEMES[i], style == "fstd_" .. THEMES[i] .. "_window", style)
      local af = p.gui.screen.theme_test_adopt
      local bar, ain = af.children[1], af.children[2]
      if THEMES[i] == "aquilo" then  -- (a light theme: dark icons; one without a dark icon keeps the game's button)
        check("light theme: title bar icons dark", bar.tt_search.sprite == "fstd-black-search"
          and bar.tt_search.hovered_sprite == "fstd-black-search" and bar.tt_close.sprite == "utility/close_black"
          and bar.tt_expand.style.name == (settings.startup["fstd-flat-game"].value and "fstd_aquilo_close_on"
            or "frame_action_button") and bar.tt_expand.sprite == "utility/expand",
          serpent.line({ bar.tt_search.sprite, bar.tt_close.sprite, bar.tt_expand.style.name, bar.tt_expand.sprite }))
      elseif THEMES[i] == "crt" then  -- (after aquilo: the game's button themed again; a heading keeps its font)
        check("dark theme: title bar icons light, themed again", bar.tt_search.sprite == "utility/search"
          and bar.tt_expand.style.name == "fstd_crt_close__frame_action_button",
          serpent.line({ bar.tt_search.sprite, bar.tt_expand.style.name }))
      end
    elseif t > STEP and t <= #THEMES * STEP + 2 and t % STEP == 2 then
      shot(THEMES[(t - 2) / STEP])
    elseif t == #THEMES * STEP + 10 then
      remote.call("fse-std", "set_theme", 1, "vulcanus")
    elseif t == #THEMES * STEP + 14 then
      local before = window_tint(p)
      remote.call("fse-std", "set_color", 1, "win", { r = 0.1, g = 0.3, b = 0.6, a = 1 })
      local after, err = window_tint(p)
      check("live tint written", type(after) == "table" and math.abs(after.b - 0.6) < 0.01,
        serpent.line({ before = before, after = after, err = err }))
      remote.call("fse-std", "set_color", 1, "caption", { r = 1, g = 1, b = 0.2, a = 1 })
      -- (a checkbox's tick and an adopted window's caption follow an edit too)
      remote.call("fse-std", "set_color", 1, "field_ink", { r = 0.9, g = 0.1, b = 0.1, a = 1 })
      remote.call("fse-std", "set_color", 1, "title", { r = 0.2, g = 0.9, b = 0.3, a = 1 })
      local probe = p.gui.screen.fstd_probe
      local ck = at(style_obj(probe.t_check), { "checkmark", "sprite" })
      local tint = ck and native.read(ck, "tint")
      local tc = at(style_obj(probe.t_window__frame), { "titleStyle", "fontColor" })
      local col = tc and native.read(tc, "")
      check("live edits reach a checkbox's tick and a frame's caption", type(tint) == "table" and tint.r > 0.8 and tint.g < 0.2
        and type(col) == "table" and col.g > 0.8 and col.r < 0.3, serpent.line({ tick = tint, title = col }))
    elseif t == #THEMES * STEP + 16 then
      shot("vulcanus-edited")
    elseif t == #THEMES * STEP + 20 then
      remote.call("fse-std", "reset", 1)
      local after = window_tint(p)
      check("reset gives the theme's colour back", type(after) == "table" and math.abs(after.b - 0x14 / 255) < 0.01,
        serpent.line(after))
      -- (flat game windows: a light theme reaches them too)
      local flat = settings.startup["fstd-flat-game"] and settings.startup["fstd-flat-game"].value
      result.flat = flat
      -- (the side menu's shots compare its top right corner (run_theme_gui.py): windows that reach it at a large GUI
      -- scale go below it, else the shots compare those windows)
      local sc, sw = p.display_scale, p.display_resolution.width
      for n, w in pairs({ theme_test_parts = 560, fstd_theme_editor = 480 }) do
        local f = p.gui.screen[n]
        if f and f.location.x + w * sc > sw - 270 * sc and f.location.y < 140 * sc then
          f.location = { f.location.x, math.floor(140 * sc) }
          theme.follow(f)
        end
      end
      remote.call("fse-std", "set_theme", 1, flat and "aquilo" or "fulgora")
      remote.call("fse-std", "set_vanilla_gui", 1, true)
    elseif t == #THEMES * STEP + 120 then  -- (the game styles are written, the side menu drawn again)
      shot("fulgora-vanilla-gui")
      local bad, n = conflicts(p)
      check("no sprite is written by two tokens", #bad == 0 and n > 0, n .. " sprites; " .. table.concat(bad, "; "))
      own_set_check(p)
      result.tick_stats = native.tick_stats()  -- (the slowest tick: the game styles' pass is in it)
    elseif t == #THEMES * STEP + 121 then
      local status = native.call("draw", "status")
      local st = status and helpers.json_to_table(status) or {}
      check("graph and glow drawn over the GUI", (st.shapes or 0) >= 5, status)
    elseif t == #THEMES * STEP + 122 then
      remote.call("fse-std", "set_vanilla_gui", 1, false)
    elseif t == #THEMES * STEP + 200 then  -- (asked well before its shot: a shot is drawn some ticks later)
      theme.confirm(p, { name = "unplace", title = "Undo", text = "Remove the 40 ghosts bpgen placed? The belts and inserters it planned stay in the plan, so Plan puts them back where they were; nothing you built yourself goes.", data = { n = 40 } })
      check("confirm opens as the opened GUI", p.opened and p.opened.name == "fstd_confirm_unplace")
    elseif t == #THEMES * STEP + 205 then
      shot("confirm")
    elseif t == #THEMES * STEP + 220 then
      shot("vanilla-gui-off")
      local bad = role_paths(p)
      check("live colours reach every role's image sets", #bad == 0, table.concat(bad, ", "))
      check("toast gone after its time", p.gui.screen["fstd_toasts_theme-test"] == nil)
    elseif t == #THEMES * STEP + 222 then
      p.opened = nil  -- (as Esc)
    elseif t == #THEMES * STEP + 224 then
      check("Esc answers no", result.answer and result.answer.yes == false and result.answer.n == 40,
        serpent.line(result.answer))
      local pf = p.gui.screen.theme_test_panel
      check("Esc on a confirm gives Esc back to its window", pf and p.opened == pf, p.opened and p.opened.name)
      remote.call("fse-std", "set_vanilla_gui", 1, true)
    elseif t == #THEMES * STEP + 226 then
      p.opened = nil  -- (Esc on the window)
    elseif t == #THEMES * STEP + 228 then
      check("Esc closes a window, and what sticks to it", p.gui.screen.theme_test_panel == nil
        and p.gui.screen.theme_test_panel__left == nil and p.gui.screen.theme_test_panel__bottom == nil)
      check("on_close hears Esc", closed.theme_test_panel == 1, serpent.line(closed))
      window.create(p, { name = "esc_stay", title = "Stays", width = 300, height = 160, themed = true, esc = false })
      check("esc = false: not the opened GUI", p.opened == nil)
      local w = window.create(p, { name = "esc_win", title = "Esc", width = 300, height = 200, themed = true,
        settings = true })
      check("a window takes Esc when nothing else has it", p.opened == w)
      theme.menu(w, { size = { 200, 100 } })
      check("its settings take Esc", p.opened and p.opened.name == "esc_win__menu", p.opened and p.opened.name)
    elseif t == #THEMES * STEP + 230 then
      check("the window stays while its settings are open", p.gui.screen.esc_win ~= nil and closed.esc_win == nil)
      p.opened = nil  -- (Esc on the settings)
    elseif t == #THEMES * STEP + 232 then
      check("Esc closes the settings, the window gets Esc back", p.gui.screen.esc_win__menu == nil
        and p.gui.screen.esc_win ~= nil and p.opened == p.gui.screen.esc_win)
      theme.menu(p.gui.screen.esc_win, { size = { 200, 100 } })
      theme.menu(p.gui.screen.esc_win, { size = { 200, 100 } })  -- (a second click on the gear)
    elseif t == #THEMES * STEP + 234 then
      check("the gear's second click gives Esc back too", p.gui.screen.esc_win__menu == nil
        and p.opened == p.gui.screen.esc_win)
      result.answers = 0
      theme.confirm(p, { name = "esc_q", text = "Sure?", danger = true })
    elseif t == #THEMES * STEP + 236 then
      local q = p.gui.screen.fstd_confirm_esc_q
      local yes
      for _, row in pairs(q and q.children[2].children or {}) do
        for _, b in pairs(row.children) do if b.tags.yes then yes = b end end
      end
      check("danger = true: yes is a red button", yes and yes.style.name:find("_bad$") ~= nil, yes and yes.style.name)
      check("confirm's buttons are translated", yes and type(yes.caption) == "table" and yes.caption[1] == "fstd.yes"
        and type(q.children[1].children[1].caption) == "table", yes and serpent.line(yes.caption))
      theme.handlers[defines.events.on_gui_click]({ element = yes, player_index = 1, tick = e.tick })
    elseif t == #THEMES * STEP + 238 then
      check("a click on yes answers once, the window gets Esc back", result.answers == 1 and result.answer.yes == true
        and p.gui.screen.esc_win ~= nil and p.opened == p.gui.screen.esc_win, serpent.line({ result.answers,
          p.opened and p.opened.name }))
      local gear
      for _, b in pairs(p.gui.screen.esc_win.children[1].children) do if b.tags.fstd_settings then gear = b end end
      check("the gear's tooltip is translated", gear and type(gear.tooltip) == "table" and gear.tooltip[1] == "fstd.settings")
      p.opened = nil
    elseif t == #THEMES * STEP + 240 then
      check("Esc closed it", p.gui.screen.esc_win == nil and closed.esc_win == 1 and p.gui.screen.esc_stay ~= nil)
      p.gui.screen.esc_stay.destroy()
    elseif t == #THEMES * STEP + 260 then  -- (an edit with the game's windows coloured: only its styles redone)
      remote.call("fse-std", "set_color", 1, "btn", { r = 0.5, g = 0.4, b = 0.9, a = 1 })
      result.edit_from = t
    elseif t >= SCALE0 and t < END - 2 then
      scale_step(p, t - SCALE0, e)
    elseif t == END - 1 then
      helpers.write_file("theme-result.json", helpers.table_to_json(result), false)
    elseif t == END then  -- (a save to load in a second run: colours written on the load)
      storage.saved_at = e.tick
      game.auto_save("theme-reload")
    elseif t == END + 1 then
      helpers.write_file("theme-done.txt", "1", false)
    elseif storage.saved_at and e.tick == storage.saved_at + 30 then
      shot("after-load")
      helpers.write_file("theme-done2.txt", "1", false)
    end
  end,
}

script.on_init(function()
  local fp = remote.interfaces["freeplay"]
  if fp then
    if fp.set_skip_intro then remote.call("freeplay", "set_skip_intro", true) end
    if fp.set_disable_crashsite then remote.call("freeplay", "set_disable_crashsite", true) end
  end
end)

theme.on_confirm(function(player, name, yes, data)
  result.answer = { name = name, yes = yes, n = data and data.n }
  result.answers = (result.answers or 0) + 1
end)

closed = {}
window.on_close(function(_, name) closed[name] = (closed[name] or 0) + 1 end)

events.register({ theme.handlers, window.handlers, handlers })
