-- fstd-flat-game: draw the game's own windows with fse-std's white tiles, so a theme can colour them any colour
-- (light themes too). A startup setting: it changes the game's styles, so it needs a restart.
data:extend({
  { type = "bool-setting", name = "fstd-flat-game", setting_type = "startup", default_value = false, order = "a" },
})

-- fstd-default-theme: the theme a player starts with until they pick their own (a map setting: changing it moves
-- the players still on the default)
local names = {}
for _, th in ipairs(require("themes").list) do names[#names + 1] = th.name end
data:extend({
  { type = "string-setting", name = "fstd-default-theme", setting_type = "runtime-global", default_value = "vanilla",
    allowed_values = names, order = "b" },
})

-- fstd-window-scale: how big every fse-std window is drawn, on top of the game's own GUI scale (a window's Size in its
-- settings overrides it for that window). Per player, changed at once.
do
  local choices = require("themes").SCALE_CHOICES
  data:extend({
    { type = "int-setting", name = "fstd-window-scale", setting_type = "runtime-per-user", default_value = 100,
      allowed_values = choices, order = "c" },
  })
end
