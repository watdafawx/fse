-- The themes fse-std ships: colours and shapes, read by data.lua (which makes every theme's styles) and by the
-- control stage (which writes edited colours into those styles while the game runs, with the fse loader).
--
-- A theme is a table of tokens (colours, {r, g, b, a} 0..1) plus its shape:
--   shape   "vanilla" (the game's own grey textures, copied), "square", "soft" or "round" (our white tiles)
--   glass   blur what is behind the panels (2.0's background_blur), panels see-through by their alpha
--   pad     the window's padding, gap the space between things
--   mono    text in fse-std's monospace font (Cascadia Mono)
--   light   a light theme: dark icons (the close button's)
-- On white tiles a token is the colour itself; on vanilla textures a token is compared with VANILLA (the game's
-- own colours) and the texture is tinted by the ratio, so it can get darker or change hue, never lighter.

local function c(hex, a)
  local n = tonumber(hex:sub(2), 16)
  return { r = math.floor(n / 65536) / 255, g = math.floor(n / 256) % 256 / 255, b = n % 256 / 255, a = a or 1 }
end

local M = {}

-- the tokens, in the order the editor shows them; `edit` ones get a colour picker
M.TOKENS = {
  { "win", "Window", edit = true }, { "section", "Panels", edit = true }, { "inset", "Inset" }, { "deep", "Preview" },
  { "btn", "Buttons", edit = true }, { "btn_on", "Accent", edit = true }, { "ok", "Main action", edit = true },
  { "slot", "Slots" }, { "field", "Text fields" }, { "drag", "Drag bar" },
  { "title", "Title", edit = true }, { "caption", "Headings", edit = true }, { "ink", "Text", edit = true },
  { "ink_dim", "Dim text" }, { "btn_ink", "Button text" }, { "btn_on_ink", "Accent text" }, { "ok_ink", "Main action text" },
  { "field_ink", "Field text" },
}

-- the game's own colours (the vanilla theme): what tints of vanilla textures are worked out from
M.VANILLA = {
  win = c("#313031"), section = c("#3a393a"), inset = c("#414041"), deep = c("#242324"),
  btn = c("#8e8e8e"), btn_on = c("#e39827"), ok = c("#5eb663"), slot = c("#3a3a3a"), field = c("#8e8e8e"),
  drag = c("#4a4a4a"),
  title = c("#ffe6c0"), caption = c("#ffe6c0"), ink = c("#ffffff"), ink_dim = c("#a8a8a8"),
  btn_ink = c("#000000"), btn_on_ink = c("#000000"), ok_ink = c("#000000"), field_ink = c("#000000"),
}

M.list = {
  { name = "vanilla", title = "Vanilla", shape = "vanilla", pad = 8, gap = 8, tokens = M.VANILLA },
  { name = "compact", title = "Compact", shape = "square", pad = 4, gap = 4, tokens = {
    win = c("#2b2b2b"), section = c("#333333"), inset = c("#222222"), deep = c("#0e0e0e"),
    btn = c("#7a7a7a"), btn_on = c("#e39827"), ok = c("#4fae3c"), slot = c("#8d8d8d"), field = c("#8a8a8a"),
    drag = c("#444444"),
    title = c("#ffe6c0"), caption = c("#ffe6c0"), ink = c("#dddddd"), ink_dim = c("#999999"),
    btn_ink = c("#000000"), btn_on_ink = c("#000000"), ok_ink = c("#000000"), field_ink = c("#000000") } },
  { name = "flat", title = "Flat dark", shape = "soft", pad = 10, gap = 8, tokens = {
    win = c("#1e2127"), section = c("#22262d"), inset = c("#181b20"), deep = c("#0f1115"),
    btn = c("#2d333c"), btn_on = c("#2f6fa8"), ok = c("#2f9e6b"), slot = c("#2a2f37"), field = c("#14171b"),
    drag = c("#2c313a"),
    title = c("#e6edf3"), caption = c("#7cc7ff"), ink = c("#d6dde5"), ink_dim = c("#8b95a1"),
    btn_ink = c("#d6dde5"), btn_on_ink = c("#ffffff"), ok_ink = c("#ffffff"), field_ink = c("#d6dde5") } },
  { name = "blueprint", title = "Blueprint", shape = "square", mono = true, pad = 10, gap = 8, tokens = {
    win = c("#123a6b"), section = c("#164377"), inset = c("#0f3260"), deep = c("#0a2547"),
    btn = c("#1b4c85"), btn_on = c("#8fc1ff"), ok = c("#ffffff"), slot = c("#1e4f88"), field = c("#0f3260"),
    drag = c("#2a5c96"),
    title = c("#ffffff"), caption = c("#bfe0ff"), ink = c("#e3f0ff"), ink_dim = c("#8fb5e0"),
    btn_ink = c("#e3f0ff"), btn_on_ink = c("#0a2547"), ok_ink = c("#0a2547"), field_ink = c("#ffffff") } },
  { name = "platform", title = "Space platform", shape = "soft", pad = 10, gap = 8, tokens = {
    win = c("#2a3138"), section = c("#2e363e"), inset = c("#20262c"), deep = c("#0b0f13"),
    btn = c("#434e59"), btn_on = c("#3d93c4"), ok = c("#f2c230"), slot = c("#3a444e"), field = c("#161b20"),
    drag = c("#f2c230"),
    title = c("#e9f1f7"), caption = c("#9fd3f0"), ink = c("#dfe7ee"), ink_dim = c("#8fa0ae"),
    btn_ink = c("#e9f1f7"), btn_on_ink = c("#ffffff"), ok_ink = c("#1c1c1c"), field_ink = c("#dfe7ee") } },
  { name = "vulcanus", title = "Vulcanus", shape = "soft", pad = 10, gap = 8, tokens = {
    win = c("#1c1614"), section = c("#231a17"), inset = c("#140f0d"), deep = c("#0a0706"),
    btn = c("#332723"), btn_on = c("#ff8a3d"), ok = c("#ffb04a"), slot = c("#2a201c"), field = c("#0e0a08"),
    drag = c("#5a2a14"),
    title = c("#ffb070"), caption = c("#ff8a3d"), ink = c("#f0e2d8"), ink_dim = c("#a88c7c"),
    btn_ink = c("#f0e2d8"), btn_on_ink = c("#1a0d06"), ok_ink = c("#1a0d06"), field_ink = c("#f0e2d8") } },
  { name = "gleba", title = "Gleba", shape = "round", pad = 12, gap = 9, tokens = {
    win = c("#1f2a1e"), section = c("#233023"), inset = c("#18211a"), deep = c("#0e140e"),
    btn = c("#2f412b"), btn_on = c("#b4568f"), ok = c("#8bc34a"), slot = c("#2a3a27"), field = c("#111a10"),
    drag = c("#3a5232"),
    title = c("#e8f5c8"), caption = c("#e58bc4"), ink = c("#dfeccf"), ink_dim = c("#93a886"),
    btn_ink = c("#dfeccf"), btn_on_ink = c("#ffffff"), ok_ink = c("#142010"), field_ink = c("#dfeccf") } },
  { name = "fulgora", title = "Fulgora", shape = "soft", pad = 10, gap = 8, tokens = {
    win = c("#17132a"), section = c("#1c1736"), inset = c("#120f22"), deep = c("#08061a"),
    btn = c("#251f47"), btn_on = c("#6a4cff"), ok = c("#5ef0ff"), slot = c("#221c42"), field = c("#0c0a1c"),
    drag = c("#3e3280"),
    title = c("#e8e2ff"), caption = c("#c3b6ff"), ink = c("#e0dbf5"), ink_dim = c("#8e86b8"),
    btn_ink = c("#e0dbf5"), btn_on_ink = c("#ffffff"), ok_ink = c("#0a0820"), field_ink = c("#e0dbf5") } },
  { name = "aquilo", title = "Aquilo", shape = "soft", light = true, pad = 10, gap = 8, tokens = {
    win = c("#e9f2f8"), section = c("#ffffff"), inset = c("#f6fafd"), deep = c("#d5e5f0"),
    btn = c("#dbe8f2"), btn_on = c("#1f6fa8"), ok = c("#2a9d8f"), slot = c("#e3eef6"), field = c("#ffffff"),
    drag = c("#c6dbea"),
    title = c("#17405e"), caption = c("#1f6fa8"), ink = c("#1d3445"), ink_dim = c("#5e7c92"),
    btn_ink = c("#1d3445"), btn_on_ink = c("#ffffff"), ok_ink = c("#ffffff"), field_ink = c("#1d3445") } },
  { name = "crt", title = "CRT terminal", shape = "square", mono = true, pad = 10, gap = 8, tokens = {
    win = c("#050a05"), section = c("#071007"), inset = c("#050a05"), deep = c("#020502"),
    btn = c("#0a1a0c"), btn_on = c("#33ff66"), ok = c("#33ff66"), slot = c("#0a160a"), field = c("#020502"),
    drag = c("#1f5a2a"),
    title = c("#66ff88"), caption = c("#66ff88"), ink = c("#44dd66"), ink_dim = c("#2a8a40"),
    btn_ink = c("#44dd66"), btn_on_ink = c("#020502"), ok_ink = c("#020502"), field_ink = c("#66ff88") } },
  { name = "glass", title = "Frosted glass", shape = "round", glass = true, light = true, pad = 12, gap = 9, tokens = {
    win = c("#ebf2f8", 0.5), section = c("#ffffff", 0.22), inset = c("#ffffff", 0.16), deep = c("#e6eef5", 0.3),
    btn = c("#ffffff", 0.3), btn_on = c("#ffffff", 0.9), ok = c("#34c759", 0.9), slot = c("#ffffff", 0.22),
    field = c("#000000", 0.25), drag = c("#ffffff", 0.2),
    title = c("#13222e"), caption = c("#1f5f8f"), ink = c("#13222e"), ink_dim = c("#3d4f5c"),
    btn_ink = c("#13222e"), btn_on_ink = c("#13222e"), ok_ink = c("#ffffff"), field_ink = c("#ffffff") } },
  { name = "glassdark", title = "Dark glass", shape = "round", glass = true, pad = 12, gap = 9, tokens = {
    win = c("#12141a", 0.55), section = c("#ffffff", 0.07), inset = c("#ffffff", 0.06), deep = c("#000000", 0.45),
    btn = c("#ffffff", 0.12), btn_on = c("#0a84ff", 0.85), ok = c("#30d158", 0.85), slot = c("#ffffff", 0.08),
    field = c("#000000", 0.35), drag = c("#ffffff", 0.1),
    title = c("#ffffff"), caption = c("#8fd0ff"), ink = c("#f2f4f7"), ink_dim = c("#a5abb3"),
    btn_ink = c("#f2f4f7"), btn_on_ink = c("#ffffff"), ok_ink = c("#04120a"), field_ink = c("#f2f4f7") } },
}

M.by_name = {}
for i, t in ipairs(M.list) do
  t.index = i
  M.by_name[t.name] = t
end

-- What each component (a role) is:
--   type     its style type (data.lua) and what element shows it (the live-colour probe)
--   vanilla  the game's style it copies (the vanilla theme) / stands for (colouring the game's own windows)
--   ink      the token of its text (sel_ink: when toggled / selected); font: its font
--   sets     its image sets: each { data path, engine path, token, how, kind = tile, small = small tile }
--            (data path: keys in the style prototype; engine path: fields of the engine's style, the last one an
--            image set; nested sub-styles are named in `nest` = { "dotted.data.path" = { type, parent } })
local function button_sets(dpre, epre, token, sel, kind, small)
  local function d(k) local t = { table.unpack(dpre) }; t[#t + 1] = k; return t end
  local function e(k) local t = { table.unpack(epre) }; t[#t + 1] = k; return t end
  return {
    { d("default_graphical_set"), e("defaultGraphicalSet"), token, "same", kind = kind, small = small },
    { d("hovered_graphical_set"), e("hoveredGraphicalSet"), token, "lighter", kind = kind, small = small },
    { d("clicked_graphical_set"), e("clickedGraphicalSet"), token, "darker", kind = kind, small = small },
    { d("disabled_graphical_set"), e("disabledGraphicalSet"), token, "faded", kind = kind, small = small },
    { d("selected_graphical_set"), e("selectedGraphicalSet"), sel, "same", kind = kind, small = small },
    { d("selected_hovered_graphical_set"), e("selectedHoveredGraphicalSet"), sel, "lighter", kind = kind, small = small },
    { d("selected_clicked_graphical_set"), e("selectedClickedGraphicalSet"), sel, "darker", kind = kind, small = small },
  }
end
local function one(dkey, ekey, token, how, kind, small)
  return { { dkey }, { ekey }, token, how or "same", kind = kind, small = small }
end
local function frame(token, kind, vanilla, small)
  return { type = "frame", vanilla = vanilla, sets = { one("graphical_set", "graphicalSet", token, "same", kind, small) } }
end
local function button(token, sel, kind, vanilla, ink, sel_ink)
  return { type = "button", vanilla = vanilla, ink = ink, sel_ink = sel_ink, sets = button_sets({}, {}, token, sel, kind) }
end
local function empty(token, how, kind, vanilla, small)
  return { type = "empty", vanilla = vanilla, sets = { one("graphical_set", "graphicalSet", token, how, kind, small) } }
end
local function label(ink, vanilla, font) return { type = "label", ink = ink, vanilla = vanilla, font = font } end
local function concat(...)
  local out = {}
  for _, list in ipairs({ ... }) do for _, v in ipairs(list) do out[#out + 1] = v end end
  return out
end

M.ROLES = {
  -- panels
  window = frame("win", "panel", "frame"),
  section = frame("section", "panel", "bordered_frame"),
  inset = frame("inset", "inset", "inside_shallow_frame"),
  deep = frame("deep", "inset", "inside_deep_frame"),
  stat = frame("inset", "inset", "inside_shallow_frame"),
  toast = frame("section", "panel", "frame"),
  badge = frame("btn_on", "flat", "frame", true),
  -- (own = true: only ours, it never colours the game's style it copies: that style has a role of its own)
  -- buttons
  button = button("btn", "btn_on", "button", "button", "btn_ink", "btn_on_ink"),
  tab = button("btn", "btn_on", "button", "button", "btn_ink", "btn_on_ink"),
  rtab = button("btn", "win", "button", "button", "btn_ink", "title"),  -- (a rail / folder tab: the open one is the window's colour)
  ok = button("ok", "ok", "button", "confirm_button", "ok_ink", "ok_ink"),
  pulse = button("ok", "ok", "button", "confirm_button", "ok_ink", "ok_ink"),
  tool = button("btn", "btn_on", "button", "tool_button", "btn_ink", "btn_on_ink"),
  slot = button("slot", "btn_on", "outline", "slot_button", "btn_ink", "btn_on_ink"),
  row = button("field", "btn_on", "flat", "list_box_item", "ink", "btn_on_ink"),  -- (a list's row: left-aligned, as the game's)
  close = button("win", "win", "flat", "frame_action_button", "title", "title"),  -- (a window's close button: its colour)
  -- inputs
  field = { type = "textbox", vanilla = "textbox", ink = "field_ink", sets = {
    one("default_background", "defaultBackground", "field", "same", "outline"),
    one("active_background", "activeBackground", "field", "lighter", "outline"),
    one("disabled_background", "disabledBackground", "field", "faded", "outline") } },
  check = { type = "checkbox", vanilla = "checkbox", ink = "ink",
    sets = button_sets({}, {}, "field", "field", "outline", true) },
  radio = { type = "radiobutton", vanilla = "radiobutton", ink = "ink",
    sets = button_sets({}, {}, "field", "field", "outline", true) },
  slider = { type = "slider", vanilla = "slider", nest = { button = { type = "button_style", parent = "slider_button" } },
    sets = concat({
      one("full_bar", "fullBar", "btn_on", "same", "flat", true),
      one("full_bar_disabled", "fullBarDisabled", "btn_on", "faded", "flat", true),
      one("empty_bar", "emptyBar", "field", "same", "outline", true),
      one("empty_bar_disabled", "emptyBarDisabled", "field", "faded", "outline", true),
    }, button_sets({ "button" }, { "buttonStyle" }, "btn", "btn_on", "button", true)) },
  dropdown = { type = "dropdown", vanilla = "dropdown", ink = "btn_ink",
    nest = { button_style = { type = "button_style", parent = "dropdown_button" } },
    sets = button_sets({ "button_style" }, { "buttonStyle" }, "btn", "btn_on", "button") },
  scroll = { type = "scroll", vanilla = "scroll_pane",
    nest = { vertical_scrollbar_style = { type = "vertical_scrollbar_style" },
      horizontal_scrollbar_style = { type = "horizontal_scrollbar_style" },
      ["vertical_scrollbar_style.thumb_button_style"] = { type = "button_style" },
      ["horizontal_scrollbar_style.thumb_button_style"] = { type = "button_style" } },
    sets = concat({
      one("graphical_set", "graphicalSet", "deep", "same", "inset"),
      { { "vertical_scrollbar_style", "background_graphical_set" }, { "verticalScrollBarStyle", "backgroundGraphicalSet" },
        "deep", "darker", kind = "flat", small = true },
      { { "horizontal_scrollbar_style", "background_graphical_set" }, { "horizontalScrollBarStyle", "backgroundGraphicalSet" },
        "deep", "darker", kind = "flat", small = true },
    }, button_sets({ "vertical_scrollbar_style", "thumb_button_style" }, { "verticalScrollBarStyle", "thumbButtonStyle" },
      "btn", "btn_on", "flat", true),
      button_sets({ "horizontal_scrollbar_style", "thumb_button_style" }, { "horizontalScrollBarStyle", "thumbButtonStyle" },
        "btn", "btn_on", "flat", true)) },
  list = { type = "list", vanilla = "list_box", ink = "ink", sel_ink = "btn_on_ink",
    nest = { item_style = { type = "button_style", parent = "list_box_item" },
      scroll_pane_style = { type = "scroll_pane_style", parent = "list_box_scroll_pane" } },
    sets = concat({ { { "scroll_pane_style", "graphical_set" }, { "scrollPaneStyle", "graphicalSet" }, "field", "same",
      kind = "outline" } }, button_sets({ "item_style" }, { "itemStyle" }, "field", "btn_on", "flat")) },
  tabbed = { type = "tabbed", vanilla = "tabbed_pane",
    nest = { tab_content_frame = { type = "frame_style", parent = "tabbed_pane_frame" } },
    sets = { { { "tab_content_frame", "graphical_set" }, { "contentFrame", "graphicalSet" }, "inset", "same", kind = "inset" } } },
  ntab = { type = "tab", vanilla = "tab", ink = "btn_ink", sel_ink = "caption",
    sets = button_sets({}, {}, "btn", "inset", "button") },
  progress = { type = "progress", vanilla = "progressbar", sets = {
    one("bar_background", "background", "deep", "same", "inset", true),
    one("bar", "bar", "white", "same", "flat", true) } },
  -- lines and bars
  drag = empty("drag", "same", "flat", "draggable_space_header"),
  line = empty("ink_dim", "faded", "flat", "draggable_space_header", true),
  bar = empty("btn_on", "same", "flat", "draggable_space_header", true),
  bar2 = empty("ok", "same", "flat", "draggable_space_header", true),
  -- text
  title = label("title", "frame_title"),
  caption = label("caption", "caption_label"),
  text = label("ink", "label"),
  dim = label("ink_dim", "label"),
  big = label("title", "label", "default-large-bold"),
  badge_text = label("btn_on_ink", "label", "default-small-bold"),
}

M.ROLES.row.sets[1].none = true  -- (its normal state draws nothing: theme_data.lua)
for _, role in ipairs({ "stat", "toast", "badge", "tab", "rtab", "pulse", "close", "row", "line", "bar", "bar2" }) do M.ROLES[role].own = true end

-- every frame and button style of the game and of other mods (data-final-fixes.lua lists them), which "colour the
-- game's own windows" tints too: the map, the quick bar, the shortcut bar, every window. Control stage only.
function M.game_styles()
  if M._game then return M._game end
  local md = prototypes.mod_data["fstd-game-styles"]
  local out = {}
  for _, s in ipairs(md and md.data.styles or {}) do
    local name, kind, token = s[1], s[2], s[3]
    local sets
    local fonts = {}
    if kind == "label" then
      -- (text only in flat game windows: on the game's own textures the backgrounds stay dark)
      sets = {}
      fonts = { { "fontColor", token, flat = true }, { "hoveredFontColor", token, flat = true } }
    elseif kind == "frame" or kind == "scroll" then
      -- (a background set is mostly a slot grid: the slot colour)
      sets = { { nil, { "graphicalSet" }, token, "same" }, { nil, { "backgroundGraphicalSet" }, "slot", "same" } }
    elseif kind == "tab" then
      sets = { { nil, { "defaultGraphicalSet" }, token, "same" }, { nil, { "hoveredGraphicalSet" }, token, "lighter" },
        { nil, { "clickedGraphicalSet" }, token, "darker" }, { nil, { "disabledGraphicalSet" }, token, "faded" },
        { nil, { "selectedGraphicalSet" }, token, "lighter" } }
    else
      -- (button text: only when the game's buttons are flat tiles, which a theme can make dark)
      fonts = { { "defaultFontColor", "btn_ink", flat = true }, { "hoveredFontColor", "btn_ink", flat = true },
        { "clickedFontColor", "btn_ink", flat = true } }
      sets = { { nil, { "defaultGraphicalSet" }, token, "same" }, { nil, { "hoveredGraphicalSet" }, token, "lighter" },
        { nil, { "clickedGraphicalSet" }, token, "darker" }, { nil, { "disabledGraphicalSet" }, token, "faded" } }
    end
    out[#out + 1] = { style = name, type = kind, sets = sets, fonts = fonts }
  end
  M._game = out
  return out
end

--- a role's image sets (see ROLES)
function M.sets(role) return M.ROLES[role].sets or {} end

-- the white tiles in graphics/theme.png (make_theme_png.py draws them with the same numbers)
M.STEP = 32
M.SHAPES = { square = { row = 0, corner = 8 }, soft = { row = 1, corner = 8 }, round = { row = 2, corner = 12 },
  small = { row = 3, corner = 4 } }  -- (small: the same kinds for thin things: bars, handles, badges)
M.KINDS = { panel = 0, button = 1, inset = 2, flat = 3, outline = 4 }

-- colour helpers (shared with the control stage)
function M.mix(a, b, t)
  return { r = a.r + (b.r - a.r) * t, g = a.g + (b.g - a.g) * t, b = a.b + (b.b - a.b) * t, a = a.a + (b.a - a.a) * t }
end
local WHITE, BLACK = { r = 1, g = 1, b = 1, a = 1 }, { r = 0, g = 0, b = 0, a = 1 }
function M.lighter(col, t)
  local m = M.mix(col, WHITE, t or 0.15); m.a = col.a; return m
end
function M.darker(col, t)
  local m = M.mix(col, BLACK, t or 0.2); m.a = col.a; return m
end
function M.faded(col, a) return { r = col.r, g = col.g, b = col.b, a = col.a * (a or 0.5) } end

-- a set's colour from its token's colour ("same", "lighter", "darker", "faded")
function M.derive(col, how)
  if how == "lighter" then return M.lighter(col, 0.12) end
  if how == "darker" then return M.darker(col, 0.15) end
  if how == "faded" then return M.faded(col, 0.5) end
  return col
end

-- the theme's colour for a token with a player's edits over it
function M.color(theme, edits, token)
  if token == "white" then return { r = 1, g = 1, b = 1, a = 1 } end  -- (a progress bar: coloured by LuaStyle.color)
  return edits and edits[token] or theme.tokens[token]
end

-- what a texture's tint is for a colour: white tiles take the colour itself, vanilla textures the ratio to the
-- game's own colour (a tint can't brighten: capped at 1)
-- (tints are premultiplied: a see-through colour has its r, g, b scaled by its alpha, or it adds up to white)
function M.tint(theme, token, col)
  local t = col
  if theme.shape == "vanilla" then
    local ref = M.VANILLA[token] or col
    local function q(x, y) return y > 0.001 and math.min(1, x / y) or 1 end
    t = { r = q(col.r, ref.r), g = q(col.g, ref.g), b = q(col.b, ref.b), a = col.a }
  end
  return { r = t.r * t.a, g = t.g * t.a, b = t.b * t.a, a = t.a }
end

return M
