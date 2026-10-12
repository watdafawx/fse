-- styles for the fse-std library
local styles = data.raw["gui-style"].default

-- the frame that follows the cursor while dragging
styles.fstd_ghost = {
  type = "frame_style",
  parent = "tooltip_frame",
  padding = 4,
  horizontal_flow_style = { type = "horizontal_flow_style", vertical_align = "center", horizontal_spacing = 6 },
}

-- the corner a window is resized by
styles.fstd_resize_grip = {
  type = "empty_widget_style",
  parent = "draggable_space",
  width = 16,
  height = 16,
  left_margin = 0,
  right_margin = 0,
}

-- a colour swatch's frame (the theme window): a grey 1 px line, so a swatch shows on a panel of its own colour
do
  local themes = require("themes")
  local soft = themes.SHAPES.soft
  styles.fstd_swatch_frame = {
    type = "frame_style",
    padding = 1,
    graphical_set = { base = { filename = "__fse-std__/graphics/theme.png", size = 1,
      position = { themes.KINDS.flat * themes.STEP + soft.corner, soft.row * themes.STEP + soft.corner },
      tint = { 0.45, 0.45, 0.45 } } },
    horizontal_flow_style = { type = "horizontal_flow_style", horizontal_spacing = 0 },
  }
end

-- events fse-std raises for every mod (its control.lua): simulation events of the tick's engine hooks, and data a
-- player's peer sent with native.sync. Both arrive on every peer in the same tick.
data:extend({
  { type = "custom-event", name = "fse-event" },
  { type = "custom-event", name = "fse-sync" },
})

-- the themes: every theme's styles (theme_data.lua), and the event fse-std raises when a player's theme changes
local theme_data = require("theme_data")
theme_data.fonts()
theme_data.roles(false)  -- (adopt()'s variants: data-final-fixes.lua)
data:extend({ { type = "custom-event", name = "fstd-theme-changed" } })

-- a window's settings button (window.create{settings = true}), white and for light themes black
data:extend({
  { type = "sprite", name = "fstd-settings", filename = "__fse-std__/graphics/settings.png", size = 64, scale = 0.5,
    flags = { "gui-icon" } },
  { type = "sprite", name = "fstd-settings-black", filename = "__fse-std__/graphics/settings-black.png", size = 64,
    scale = 0.5, flags = { "gui-icon" } },
})

-- black copies of the game's white title bar icons that have no black one (theme.lua: on light themes)
local us = data.raw["utility-sprites"].default
for _, n in ipairs({ "search" }) do
  local s = us[n] and table.deepcopy(us[n])
  if s then
    s.type, s.name, s.invert_colors = "sprite", "fstd-black-" .. n, true
    data:extend({ s })
  end
end

-- the theme window's button on the shortcut bar
data:extend({ { type = "shortcut", name = "fstd-theme", order = "z[fse]-t[theme]", action = "lua", toggleable = true,
  icon = "__fse-std__/graphics/theme-shortcut.png", icon_size = 64,
  small_icon = "__fse-std__/graphics/theme-shortcut.png", small_icon_size = 64 } })
