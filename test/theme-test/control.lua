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



local T0 = 60
local STEP = 6

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
    elseif t == #THEMES * STEP + 299 then
      helpers.write_file("theme-result.json", helpers.table_to_json(result), false)
    elseif t == #THEMES * STEP + 300 then  -- (a save to load in a second run: colours written on the load)
      storage.saved_at = e.tick
      game.auto_save("theme-reload")
    elseif t == #THEMES * STEP + 301 then
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
