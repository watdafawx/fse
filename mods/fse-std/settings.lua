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
