-- fse-bridge: runs commands queued by the fse web plugin (POST /api/game) on the game thread and answers.
--
-- A command is {interface, function, args}: remote.call(interface, function, table.unpack(args)), so every mod with
-- a remote interface can be driven over HTTP. Built in, under interface "$game":
--   status       tick, players, surfaces, active mod count
--   interfaces   every remote interface and its functions (what an agent can call)
--   print(text)  a chat message
--   subscribe(event) / unsubscribe(event)   a game event (on_research_finished, ...) sent out as "game/<event>"
--
-- Remote mods (programs outside the game, any language): they long-poll GET /api/events for what the game emits
-- and answer with POST /api/game. A mod talks to its remote half through the interface "fse-remote":
--   emit(name, data)     an event out ("srq/need_pick", any JSON-able table)
--   connected(client)    is the program polling as `client` there now (or in the last 3 s)?
--   clients()            the names of the programs there now
-- Without the fse loader (no `native` table) it does nothing: emit is dropped, connected is false.

-- ---- events out -----------------------------------------------------------------------------------------------

local function emit(name, data)
  if not native then return false end
  local ok, text = pcall(helpers.table_to_json, { name = name, data = data })
  if not ok then error("emit " .. tostring(name) .. ": can't be JSON: " .. tostring(text)) end
  native.call("web", "emit", text)
  return true
end

local clients_tick, clients_set = -1, {}
local function clients()
  if not native then return {} end
  -- (once per tick at most: a mod may ask on every event)
  if clients_tick ~= game.tick then
    clients_tick, clients_set = game.tick, {}
    for _, name in pairs(helpers.json_to_table(native.call("web", "clients") or "[]") or {}) do
      clients_set[name] = true
    end
  end
  return clients_set
end

-- a game event as plain data: Lua objects become {object_name, name, unit_number, index, position, ...}
local function plain(v, depth)
  local t = type(v)
  if t == "userdata" then
    local out = { object_name = v.object_name }
    if not v.valid then return out end
    for _, k in pairs({ "name", "unit_number", "index", "type", "position", "surface_index", "level" }) do
      local ok, x = pcall(function() return v[k] end)
      if ok and type(x) ~= "userdata" and type(x) ~= "function" then out[k] = x end
    end
    local ok, force = pcall(function() return v.force end)
    if ok and type(force) == "userdata" then out.force = force.name end
    return out
  elseif t == "table" then
    if depth > 3 then return nil end
    local out = {}
    for k, x in pairs(v) do out[k] = plain(x, depth + 1) end
    return out
  elseif t == "function" then
    return nil
  end
  return v
end

local function forward(e)
  local name = (storage.event_names or {})[e.name]
  if name then pcall(emit, "game/" .. name, plain(e, 0)) end
end

local reserved = { on_tick = true }  -- (the bridge's own)
local function register_subscriptions()
  for event_name in pairs(storage.subscriptions or {}) do
    script.on_event(defines.events[event_name], forward)
  end
end

local function subscribe(event_name, on)
  local id = defines.events[event_name]
  if not id then error("no event " .. tostring(event_name)) end
  if reserved[event_name] then error(event_name .. " can't be forwarded (every tick: poll a remote interface instead)") end
  storage.subscriptions = storage.subscriptions or {}
  storage.event_names = storage.event_names or {}
  storage.subscriptions[event_name] = on or nil
  storage.event_names[id] = on and event_name or nil
  script.on_event(id, on and forward or nil)
  return on
end

remote.add_interface("fse-remote", {
  emit = emit,
  connected = function(client) return clients()[client] == true end,
  clients = function()
    local out = {}
    for name in pairs(clients()) do out[#out + 1] = name end
    table.sort(out)
    return out
  end,
})

script.on_load(register_subscriptions)

-- ---- commands in -----------------------------------------------------------------------------------------------

local function builtin(fn, args)
  if fn == "subscribe" or fn == "unsubscribe" then
    return subscribe(args[1], fn == "subscribe")
  elseif fn == "status" then
    local players = {}
    for _, p in pairs(game.connected_players) do
      players[#players + 1] = { name = p.name, index = p.index, surface = p.surface.name,
        position = p.position, controller = p.controller_type }
    end
    local surfaces = {}
    for _, s in pairs(game.surfaces) do surfaces[#surfaces + 1] = s.name end
    local mods = 0
    for _ in pairs(script.active_mods) do mods = mods + 1 end
    return { tick = game.tick, ticks_played = game.ticks_played, speed = game.speed, players = players,
      surfaces = surfaces, mods = mods }
  elseif fn == "interfaces" then
    local out = {}
    for name, fns in pairs(remote.interfaces) do
      local list = {}
      for f in pairs(fns) do list[#list + 1] = f end
      table.sort(list)
      out[name] = list
    end
    return out
  elseif fn == "print" then
    game.print("[fse] " .. tostring(args[1]))
    return true
  end
  error("no built-in " .. tostring(fn) .. " (status, interfaces, print, subscribe, unsubscribe)")
end

local function run(c)
  local args = c.args or {}
  if c.interface == "$game" then return pcall(builtin, c["function"], args) end
  local iface = remote.interfaces[c.interface]
  if not iface then return false, "no remote interface " .. tostring(c.interface) end
  if not iface[c["function"]] then return false, c.interface .. " has no function " .. tostring(c["function"]) end
  return pcall(remote.call, c.interface, c["function"], table.unpack(args))
end

local function answer(c, ok, res)
  local reply = { id = c.id, ok = ok }
  if ok then reply.result = res else reply.error = tostring(res) end
  local okj, text = pcall(helpers.table_to_json, reply)
  if not okj then  -- (a Lua object in the result can't be JSON: say so instead)
    text = helpers.table_to_json({ id = c.id, ok = false, error = "result can't be sent as JSON: " .. tostring(text) })
  end
  native.call("web", "reply", text)
end

-- (guarded: a bad command or answer is logged and skipped, never the end of the game)
local function guarded(fn)
  return function(e)
    local ok, err = pcall(fn, e)
    if not ok then log("[" .. script.mod_name .. "] error (handled): " .. tostring(err)) end
  end
end
script.on_event(defines.events.on_tick, guarded(function()
  -- (not in the main menu's background simulation: it runs mods too, and the hub button over the menu must stay)
  if not native or script.level.is_simulation then return end
  local cmds = native.call("web", "take")
  if not cmds or cmds == "[]" then return end
  for _, c in pairs(helpers.json_to_table(cmds) or {}) do
    answer(c, run(c))
  end
end))
