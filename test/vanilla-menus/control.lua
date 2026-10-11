-- the game's own menus with "colour the game's own windows" on (run_vanilla_menus.py [--flat]): each menu a script
-- can open, opened in turn and shot (menus-<name>.png), on a light theme where what isn't coloured shows most.

local THEME = "aquilo"
local GAP = 50

local function place(p, name, dx)
  local pos = { p.position.x + dx, p.position.y - 4 }
  return p.surface.create_entity({ name = name, position = pos, force = p.force })
end

local MENUS = {
  { "inventory", function(p) p.opened = defines.gui_type.controller end },
  { "chest", function(p)
    local c = place(p, "iron-chest", 2)
    c.insert({ name = "iron-plate", count = 50 })
    p.opened = c
  end },
  { "assembler", function(p)
    local a = place(p, "assembling-machine-2", 5)
    a.set_recipe("iron-gear-wheel")
    p.opened = a
  end },
  { "furnace", function(p) p.opened = place(p, "stone-furnace", 9) end },
  { "production", function(p) p.opened = defines.gui_type.production end },
  { "bonus", function(p) p.opened = defines.gui_type.bonus end },
  { "trains", function(p) p.opened = defines.gui_type.trains end },
  { "logistic", function(p) p.opened = defines.gui_type.logistic end },
  { "blueprint-library", function(p) p.opened = defines.gui_type.blueprint_library end },
  { "achievements", function(p) p.opened = defines.gui_type.achievement end },
  { "map", function(p) p.set_controller({ type = defines.controllers.remote, position = p.position }) end },
}

script.on_init(function()
  local fp = remote.interfaces["freeplay"]
  if fp then
    if fp.set_skip_intro then remote.call("freeplay", "set_skip_intro", true) end
    if fp.set_disable_crashsite then remote.call("freeplay", "set_disable_crashsite", true) end
  end
end)

local log_lines = {}

script.on_event(defines.events.on_tick, function(e)
  local p = game.get_player(1)
  if not p then return end
  if e.tick == 30 then
    remote.call("fse-std", "set_theme", 1, THEME)
    remote.call("fse-std", "set_vanilla_gui", 1, true)
  end
  local t = e.tick - 120  -- (the game styles' colours are written within a second)
  if t < 0 then return end
  local i, k = math.floor(t / GAP) + 1, t % GAP
  local m = MENUS[i]
  if not m then
    if k == 0 and i == #MENUS + 1 then
      helpers.write_file("menus-log.txt", table.concat(log_lines, "\n"), false)
      helpers.write_file("menus-done.txt", "1", false)
    end
    return
  end
  if k == 0 then
    local ok, err = pcall(m[2], p)
    log_lines[#log_lines + 1] = m[1] .. ": " .. (ok and "opened" or ("not opened: " .. tostring(err)))
  elseif k == 14 and (m[1] == "blueprint-library" or m[1] == "bonus" or m[1] == "production") then  -- (which styles?)
    local function ptr(v) if type(v) == "table" and v.ptr and v.ptr ~= 0 then return v end end
    local byptr = {}
    local holder = p.gui.screen.fstd_probe and p.gui.screen.fstd_probe.game
    for _, c in pairs(holder and holder.children or {}) do
      local w = ptr(native.read(c, "guiElement.target.widget"))
      local st = w and ptr(native.read(w, "style.parent"))
      if st then byptr[st.ptr] = c.style.name end
    end
    local root = ptr(native.read(ptr(native.read(ptr(native.read(p.gui.screen.fstd_probe, "guiElement.target.widget")), "guiInstance")), "baseWidget"))
    local seen, n = {}, 0
    local function visit(w, depth, inside)
      n = n + 1
      if n > 8000 or depth > 40 then return end
      local ww = tonumber((native.read(w, "size.width"))) or 0
      if ww > 60 and not w.type:find("Flow") and not w.type:find("Label") then
        local st = ptr(native.read(w, "style.parent"))
        local key = w.type .. " " .. (st and (byptr[st.ptr] or ("?" .. st.ptr)) or "-") .. " " .. ww
        seen[key] = (seen[key] or 0) + 1
      end
      local lay = ptr(native.read(w, "layout"))
      if lay then visit(lay, depth + 1, inside) end
      for _, f in ipairs({ "children", "privateChildren" }) do
        local list = native.read(w, f)
        if type(list) == "table" then for _, c in ipairs(list) do if ptr(c) then visit(c, depth + 1, inside) end end end
      end
    end
    if root then visit(root, 0, false) end
    log_lines[#log_lines + 1] = m[1] .. " widgets: " .. serpent.line(seen)
  elseif k == 14 and m[1] == "map" then  -- (which game style is the remote view's frame?)
    local function ptr(v) if type(v) == "table" and v.ptr and v.ptr ~= 0 then return v end end
    local byptr = {}
    local holder = p.gui.screen.fstd_probe and p.gui.screen.fstd_probe.game
    for _, c in pairs(holder and holder.children or {}) do
      local w = ptr(native.read(c, "guiElement.target.widget"))
      local st = w and ptr(native.read(w, "style.parent"))
      if st then byptr[st.ptr] = c.style.name end
    end
    local root = ptr(native.read(ptr(native.read(ptr(native.read(p.gui.screen.fstd_probe, "guiElement.target.widget")), "guiInstance")), "baseWidget"))
    local found = {}
    local n = 0
    local W = p.display_resolution.width
    local function visit(w, depth)
      n = n + 1
      if n > 8000 or depth > 40 then return end
      local width = tonumber((native.read(w, "size.width"))) or 0
      if width > W * 0.6 and #found < 40 then
        local st = ptr(native.read(w, "style.parent"))
        local text = native.read(w, "text")
        found[#found + 1] = { type = w.type, depth = depth, w = width, h = tonumber((native.read(w, "size.height"))),
          text = type(text) == "string" and text:sub(1, 20) or nil, style = st and (byptr[st.ptr] or ("?" .. st.ptr)) }
      end
      local lay = ptr(native.read(w, "layout"))
      if lay then visit(lay, depth + 1) end
      for _, f in ipairs({ "children", "privateChildren" }) do
        local list = native.read(w, f)
        if type(list) == "table" then for _, c in ipairs(list) do if ptr(c) then visit(c, depth + 1) end end end
      end
    end
    if root then visit(root, 0) end
    log_lines[#log_lines + 1] = "remote view frames: " .. serpent.line(found)
  elseif k == 15 then
    game.take_screenshot({ player = 1, path = "menus-" .. m[1] .. ".png", show_gui = true,
      resolution = { p.display_resolution.width, p.display_resolution.height }, daytime = 0 })
  elseif k == 40 then
    p.opened = nil
    if p.controller_type == defines.controllers.remote then p.exit_remote_view() end
  end
end)
