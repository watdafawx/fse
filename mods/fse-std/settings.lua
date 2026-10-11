-- fstd-flat-game: draw the game's own windows with fse-std's white tiles, so a theme can colour them any colour
-- (light themes too). A startup setting: it changes the game's styles, so it needs a restart.
data:extend({
  { type = "bool-setting", name = "fstd-flat-game", setting_type = "startup", default_value = false, order = "a" },
})
