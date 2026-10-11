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

-- events fse-std raises for every mod (its control.lua): simulation events of the tick's engine hooks, and data a
-- player's peer sent with native.sync. Both arrive on every peer in the same tick.
data:extend({
  { type = "custom-event", name = "fse-event" },
  { type = "custom-event", name = "fse-sync" },
})

-- the themes: every theme's styles (theme_data.lua), and the event fse-std raises when a player's theme changes
require("theme_data")
data:extend({ { type = "custom-event", name = "fstd-theme-changed" } })

-- the theme window's button on the shortcut bar
data:extend({ { type = "shortcut", name = "fstd-theme", order = "z[fse]-t[theme]", action = "lua", toggleable = true,
  icon = "__fse-std__/graphics/theme-shortcut.png", icon_size = 64,
  small_icon = "__fse-std__/graphics/theme-shortcut.png", small_icon_size = 64 } })
