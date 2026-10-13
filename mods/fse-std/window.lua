-- Windows for mod GUIs: a title bar to move them by, a close button, a corner to resize them by (with the fse
-- std plugin), and the position and size each player left them at.
--
--   local frame, content = window.create(player, { name = "my_window", title = "My window",
--     width = 400, height = 300, resizable = true, close = true, min_width = 200, min_height = 120, settings = false })
--   content.add{...}                       -- your elements
--   window.on_close(function(player, name) ... end)
--   window.on_resize(function(player, name, width, height) ... end)   -- while the grip is dragged (GUI units)
--   events.register({ input.handlers, window.handlers, ... })
-- themed = true: the window, its title bar and its content follow the player's theme (theme.lua); register
-- theme.handlers too.
-- settings = true: a settings button (a gear) left of the close button, tagged { fstd_settings = name }: on its
-- click, open the window's settings with theme.menu(frame, {size}) (a panel under the title bar's right end).
-- esc (default true): the window becomes the player's opened GUI when nothing else is (player.opened), so Esc and E
-- close it as they close the game's windows, and on_close hears it. A window that stays open while the player uses
-- the game's own windows says esc = false. (A mod that closes it on on_gui_closed itself still can: it then wins.)
--   window.close(player, name)             -- closes it as its X does (what is stuck to it goes too; on_close hears it)
--   window.reset_place(player, name)       -- forgets its place and size (create it again: first size, centred)
-- Sizes are in GUI units (as style.width) at 100 %: the window is drawn at its scale (below) times display_scale
-- in pixels. Without a size the window is 400 x 300.
--   window.size(player, name) -> width, height   (what the library set: Lua can't read a style's size back)
-- Window scale (fse-std 0.8): every window is drawn at the player's setting "Window size" (fstd-window-scale), or at
-- its own Size, on top of the game's GUI scale; capped so it (with what sticks out of it) fits the screen (fit =
-- false: never). Everything fse-std makes or themes scales with it, fonts included; theme.adopt and theme.scale_tree
-- scale a mod's own elements too (theme.lua).
--   window.scale(player, name) -> scale, wanted, capped   (1 = 100 %; capped: the screen made it smaller)
--   window.set_scale(player, name, scale or nil)  -- its own Size (nil: the setting's); drawn at it at once
--   window.size_setting(parent, name) -> drop-down   -- "Size" for its settings: Default (the setting), 75 % ... 200 %
--   window.on_scale(fn(player, name, scale, {want, capped, old, element}))  -- drawn at another scale (done in place)
--   window.room(player, name) -> width, height    -- GUI units at 100 % that fit the screen at its wanted scale

local input = require("__fse-std__/input")
local theme = require("__fse-std__/theme")

local M = {}
local closers = {}
local resizers = {}
local resizing = {}  -- player_index -> {name, x, y, w, h}  (momentary: not saved)
local last_left = {}
-- (closed with Esc, closed on the next tick: storage.fstd_escaped = player_index -> { [element index] = name }, in
-- the save, so a player joining between the two ticks gets it too)
local function saved(player_index, name) return theme.saved(player_index, name) end
local S = theme.scale

function M.on_close(fn) closers[#closers + 1] = fn end
function M.on_resize(fn) resizers[#resizers + 1] = fn end

function M.size(player, name)
  local s = saved(player.index, name)
  return s.width, s.height
end

--- the scale a window is drawn at -> scale (1 = 100 %), wanted (its Size, else the setting), capped (the screen made
--- it smaller than wanted)
function M.scale(player, name)
  local frame = player.gui.screen[name]
  local f, want, capped = theme.window_scale(player, name, { root = frame })
  if frame and frame.tags.fstd_scale then f = frame.tags.fstd_scale; capped = f < want - 0.001 end
  return f, want, capped
end

--- a window's own Size (1.5 = 150 %; nil: the player's setting), drawn at it at once when it is open
function M.set_scale(player, name, scale)
  saved(player.index, name).scale = scale
  local frame = player.gui.screen[name]
  if frame and frame.valid then theme.refit(player, frame) end
end

M.on_scale = theme.on_scale

--- GUI units (at 100 %) of screen a window has at the scale it wants: lay it out to fit in that
function M.room(player, name)
  local _, want = theme.window_scale(player, name)
  local res, sc = player.display_resolution, player.display_scale * want
  return math.floor((res.width - 16) / sc), math.floor((res.height - 16) / sc)
end

--- a "Size" drop-down for a window's settings (theme.menu): Default (the player's setting), then each size; it sets
--- the window's own Size (window.set_scale). Returns the drop-down.
function M.size_setting(parent, name)
  local player = game.get_player(parent.player_index)
  local own = saved(player.index, name).scale
  local items, pick = { { "fstd.size-default", S.pct(theme.setting_scale(player)) } }, 1
  for i, c in ipairs(theme.themes.SCALE_CHOICES) do
    items[#items + 1] = { "fstd.percent", c }
    if own and S.pct(own) == c then pick = i + 1 end
  end
  local f = theme.field(parent, { "fstd.size" }, { "fstd.size-tooltip" })
  return theme.add(f, { type = "drop-down", items = items, selected_index = pick, tags = { fstd_scale_pick = name },
    tooltip = { "fstd.size-tooltip" } }, "dropdown")
end

--- forgets where a window was and its size (a "Reset size and place" button: { "fstd.reset-place" }); create it
--- again to show it at its first size, centred
function M.reset_place(player, name)
  local s = saved(player.index, name)
  s.location, s.width, s.height = nil, nil, nil
end

--- closes a window as its X does: it and what is stuck to it (theme.attach) go, on_close hears it
function M.close(player, name)
  local frame = player.gui.screen[name]
  if not frame then return end
  frame.destroy()
  for _, c in pairs(player.gui.screen.children) do  -- (what was attached to it: theme.attach)
    local a = c.tags.fstd_attach
    if a and a.owner == name and c.get_mod() == script.mod_name then c.destroy() end
  end
  for _, fn in ipairs(closers) do fn(player, name) end
end

function M.create(player, opts)
  local name = assert(opts.name, "window.create: name is required")
  local screen = player.gui.screen
  if screen[name] then screen[name].destroy() end
  local esc = opts.esc ~= false
  local s = saved(player.index, name)
  -- (a style's width can be set, not read: the window always gets a size, and the library keeps it)
  s.width = s.width or opts.width or 400
  s.height = s.height or opts.height or 300
  -- (its scale: its Size or the setting, capped to the screen; everything added to it is drawn at it)
  local f = theme.window_scale(player, name, { width = s.width, height = s.height, fit = opts.fit })
  local frame = screen.add({ type = "frame", name = name, direction = "vertical",
    tags = { fstd_window = name, fstd_esc = esc or nil, fstd_scale = f, fstd_scaled = f ~= 1 or nil,
      fstd_nofit = opts.fit == false or nil } })
  theme.forget_scales()
  local bar = frame.add({ type = "flow", direction = "horizontal" })
  bar.drag_target = frame
  bar.style.horizontal_spacing = 8
  local title = bar.add({ type = "label", caption = opts.title or name, style = "frame_title", ignored_by_interaction = true })
  local filler = bar.add({ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true })
  filler.style.height = 24
  filler.style.horizontally_stretchable = true
  local th = opts.themed and theme.of(player)
  if th then
    theme.apply(title, "title", nil, th)
    theme.apply(filler, "drag", { height = 24, horizontally_stretchable = true }, th)
  end
  if opts.settings then
    local gear = bar.add({ type = "sprite-button", style = "frame_action_button",
      sprite = th and theme.settings_sprite(th) or "fstd-settings", tags = { fstd_settings = name }, tooltip = { "fstd.settings" } })
    if th then theme.apply(gear, "close", nil, th) end
  end
  if opts.close ~= false then
    local close = bar.add({ type = "sprite-button", style = "frame_action_button",
      sprite = th and theme.close_sprite(th) or "utility/close", tags = { fstd_close = name }, tooltip = { "gui.close" } })
    if th then theme.apply(close, "close", nil, th) end
  end
  local content = frame.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  content.style.horizontally_stretchable = true
  content.style.vertically_stretchable = true
  if th then theme.apply(content, "inset", { horizontally_stretchable = true, vertically_stretchable = true }, th) end
  frame.style.width = s.width
  frame.style.height = s.height
  if th then theme.apply(frame, "window", { width = s.width, height = s.height }, th) end
  if opts.resizable ~= false and input.native() then
    local foot = frame.add({ type = "flow", direction = "horizontal" })
    local push = foot.add({ type = "empty-widget", ignored_by_interaction = true })
    push.style.horizontally_stretchable = true
    local grip = foot.add({ type = "empty-widget", style = "fstd_resize_grip", raise_hover_events = true,
      tags = { fstd_resize = name, min_w = opts.min_width or 160, min_h = opts.min_height or 100 },
      tooltip = { "fstd.resize" } })
    grip.style.top_margin = -4
  end
  theme.scale_tree(frame)  -- (what isn't themed: the title bar's flow, the grip, an unthemed window's frame)
  if opts.remember ~= false and s.location then
    frame.location = s.location
    theme.refit_soon(player, name)  -- (kept on the screen, with what gets attached to it)
  else
    frame.force_auto_center()
  end
  -- (Esc closes it: the player's opened GUI, unless another one is open, the game's or a mod's)
  if esc and player.opened_gui_type == defines.gui_type.none then player.opened = frame end
  return frame, content
end

-- the element with this index on the player's screen (a window a confirm or a menu took Esc from), or nil
local function by_index(player, index)
  for _, c in pairs(player.gui.screen.children) do
    if c.index == index then return c end
  end
end

--- gives Esc back to a window after something of its own (theme.confirm, theme.menu) had it: `child` is that
--- something's tags. Called once the child is gone.
function M.give_back(player, tags)
  local i = tags and tags.fstd_return
  local w = i and by_index(player, i)
  if w and w.valid and w.visible and player.opened_gui_type == defines.gui_type.none then player.opened = w end
end

--- `child` (a confirm, a menu) becomes the player's opened GUI; the window that was (one of this mod's) gets Esc back
--- when the child goes (give_back)
function M.open_child(player, child)
  local was = player.opened_gui_type == defines.gui_type.custom and player.opened
  if was and was.valid and was ~= child and was.tags.fstd_window and was.get_mod() == script.mod_name then
    local tags = child.tags
    tags.fstd_return = was.index
    child.tags = tags
  end
  player.opened = child
end

M.handlers = {
  -- a window's Size (size_setting): its own scale, drawn at it at once
  [defines.events.on_gui_selection_state_changed] = function(e)
    local el = e.element
    local name = el and el.valid and el.tags.fstd_scale_pick
    if not name or el.get_mod() ~= script.mod_name then return end
    local c = theme.themes.SCALE_CHOICES[el.selected_index - 1]
    M.set_scale(game.get_player(e.player_index), name, c and c / 100 or nil)
  end,
  [defines.events.on_gui_click] = function(e)
    local el = e.element
    if not (el and el.valid) then return end
    local name = el.tags.fstd_close
    if not name or el.get_mod() ~= script.mod_name then return end
    M.close(game.get_player(e.player_index), name)
  end,
  -- Esc (or E, or another GUI opened over it): the window closes on the next tick. Not at once: a mod that closes
  -- its window on this event itself runs after the library, and finds it still there. A window that is the opened
  -- GUI again by then (a confirm or a menu of its own took Esc for a moment, or the mod set it back) stays.
  [defines.events.on_gui_closed] = function(e)
    local el = e.element
    if not (el and el.valid and el.tags.fstd_esc and el.tags.fstd_window and el.get_mod() == script.mod_name) then
      return
    end
    storage.fstd_escaped = storage.fstd_escaped or {}
    local list = storage.fstd_escaped[e.player_index] or {}
    storage.fstd_escaped[e.player_index] = list
    list[el.index] = el.name
  end,
  [defines.events.on_gui_location_changed] = function(e)
    local el = e.element
    if el and el.valid and el.tags.fstd_window then
      saved(e.player_index, el.tags.fstd_window).location = el.location
    end
  end,
  -- resizing: press on the grip, the window follows the cursor until the button goes up
  [defines.events.on_tick] = function()
    local list = storage.fstd_escaped
    if list then
      storage.fstd_escaped = nil
      for i, wins in pairs(list) do
        local player = game.get_player(i)
        for index, name in pairs(player and wins or {}) do
          local frame = player.gui.screen[name]
          local now = player.opened_gui_type == defines.gui_type.custom and player.opened
          local child = now and now.valid and now.tags.fstd_return == index
          if frame and frame.valid and frame.index == index and now ~= frame and not child then
            M.close(player, name)
          end
        end
      end
    end
    if not input.native() then return end
    for _, player in pairs(game.connected_players) do
      local i = player.index
      local r = resizing[i]
      local h = input.hovered[i]
      local grip = h and h.valid and h.tags.fstd_resize
      if r or grip then
        local m = input.this_tick()
        if m then
          if not r then
            if m.left and not last_left[i] then
              -- (only this mod's own windows: every mod using the library sees every grip, but the size it needs
              -- lives in the storage of the mod that made the window)
              local win = player.gui.screen[grip]
              local s = win and win.get_mod() == script.mod_name and saved(i, grip)
              if s and s.width and s.height then
                resizing[i] = { name = grip, x = m.x, y = m.y, w = s.width, h = s.height,
                  min_w = h.tags.min_w, min_h = h.tags.min_h }
              end
            end
          else
            local frame = player.gui.screen[r.name]
            if not (frame and frame.valid) or not m.left then
              resizing[i] = nil
            else
              local scale = player.display_scale * theme.scale_of(frame)  -- (sizes at 100 %)
              local s = saved(i, r.name)
              s.width = math.max(r.min_w, math.floor(r.w + (m.x - r.x) / scale))
              s.height = math.max(r.min_h, math.floor(r.h + (m.y - r.y) / scale))
              -- (drawn at the window's scale; a themed window keeps its size through a theme change: its tweak)
              theme.style(frame, { width = s.width, height = s.height })
              theme.follow(frame)
              for _, fn in ipairs(resizers) do fn(player, r.name, s.width, s.height) end
            end
          end
          last_left[i] = m.left
        end
      else
        last_left[i] = nil
      end
    end
  end,
}

theme.window = M  -- (theme.confirm opens its dialog with it: theme.lua can't require this file back)
return M
