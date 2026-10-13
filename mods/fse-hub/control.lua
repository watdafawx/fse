-- fse hub: one button (the mod-gui bar, top left) for everything fse adds. In the main menu the same hub is
-- the "fse hub" button the web plugin draws over the game window's corner.
--
-- The window (fse-std, themed, settings behind the gear) has four views on a rail out of its left edge: Hub (loader,
-- engine profiler, agents), Mods (the mod manager: added / updated dates, load order, portal updates), Startup (what
-- took the game how long to start) and Get mods (the fse mod catalog, fse_tools.catalog: installs need a restart to
-- load). The per-player "Docked" setting puts the rail back inside the window as a row of tabs. Mods, Startup and Get
-- mods ask Python (fse_tools.mods / .startup) on a worker thread (native.start), so a tick never waits; the Dashboard
-- button opens the web pages in a panel over the game (web.open).
--
-- Single player only: what the hub shows (this computer's mods folder, its profiler, Python's answers) comes from the
-- loader on this computer, so its GUI can't be game state every peer agrees on. In multiplayer there is no button.

local mod_gui = require("mod-gui")
local events = require("__fse-std__/events")
local input = require("__fse-std__/input")
local window = require("__fse-std__/window")
local theme = require("__fse-std__/theme")

local NAME = "fse_hub"
local PAGE = 100
local DIM = { 0.55, 0.55, 0.55 }
local BIG_TOOL = { size = 28, font = "default-large-bold" }  -- (the pager's and the search's small buttons: easy to hit)
local FN_W = 280  -- (the profiler's function names: longer ones are cut, the whole name in their tooltip)

local function loaded()
  return type(native) == "table" and type(native.plugins) == "function" and type(native.call) == "function"
    and not script.level.is_simulation
end

-- the hub works here: the loader on this computer, and no other peer (see the top)
local function available()
  return not game.is_multiplayer() and loaded()
end

local function plugins()
  local list = {}
  for p in pairs(loaded() and native.plugins() or {}) do list[#list + 1] = p end
  table.sort(list)
  return list
end

local function has(plugin)
  if not loaded() then return false end
  local ok, list = pcall(native.plugins)
  return ok and type(list) == "table" and list[plugin] ~= nil
end

local function find(el, name)
  if not (el and el.valid) then return nil end
  if el.name == name then return el end
  for _, c in pairs(el.children) do
    local f = find(c, name)
    if f then return f end
  end
end

-- a themed element: parent.add(spec) with a role (fse-std themes.lua) and style values of our own
local function T(parent, spec, role, tweak) return theme.add(parent, spec, role, tweak) end

-- Window scale (fse-std 0.8): the hub is drawn at its own scale on top of the game's. Every size here is in GUI
-- units at 100 %: themed elements' tweaks, the window, the rail and the menu scale by themselves; a plain element's
-- sizes go through style() and a part built again gets scaled() (its plain flows and tables: spacing, margins).
local function style(el, values)
  if theme.style then return theme.style(el, values) end
  for k, v in pairs(values) do el.style[k] = v end
  return el
end
local function scaled(el)
  if theme.scale_tree and el and el.valid then theme.scale_tree(el) end
  return el
end

-- an error for a locale parameter: ours are localised already, Python's are text
local function err(x) return type(x) == "table" and x or tostring(x) end

-- (GUI Unifyer reskins the mod button bar but knows only its own list of buttons: ours take its button style, its
-- "_selected" one while on, so they match the others)
local style_there = {}  -- style name -> exists (prototypes don't change while the game runs)
local function style_ok(name)
  local v = style_there[name]
  if v == nil then
    v = prototypes.style[name] ~= nil
    style_there[name] = v
  end
  return v
end

local function gu_style(button, on)
  local base
  if script.active_mods["GUI_Unifyer"] or script.active_mods["GUI_Unifyer_Unified"] then
    local ok, s = pcall(function() return game.get_player(button.player_index).mod_settings["gu_button_style_setting"] end)
    base = ok and s and s.value
  end
  if not (base and style_ok(base)) then
    button.style = mod_gui.button_style
    button.toggled = on == true
    return
  end
  local selected = base .. "_selected"
  if on and style_ok(selected) then
    button.style = selected
    button.toggled = false
  else
    button.style = base
    button.toggled = on == true
  end
end

-- the button only where the hub works (a save opened without the loader, or hosted, keeps no button); lit while the
-- hub is open
local function sync_button(player)
  local flow = mod_gui.get_button_flow(player)
  local b = flow.fse_hub_button
  if available() and not b then
    b = flow.add({ type = "sprite-button", name = "fse_hub_button", sprite = "virtual-signal/signal-F",
      style = mod_gui.button_style, tooltip = { "fse-hub.button-tooltip" } })
  elseif not available() and b then
    b.destroy()
    return
  end
  if b then gu_style(b, player.gui.screen[NAME] ~= nil) end
end

local function web_url(path)
  if not has("web") then return nil end
  local base = native.call("web", "url")
  if not base then return nil end
  -- (base is ".../?token=...": a page goes before the query)
  return (base:gsub("/%?", "/" .. (path or "") .. "?", 1))
end

-- a web page in the panel over the game (older web plugins: the browser)
local function open_page(path)
  if has("web") and native.call("web", "open", path) then return end
  local url = web_url(path)
  if url and has("std") then native.call("std", "open", url) end
end

-- a message to one player: a toast (fse-std), the chat on an older fse-std
local function say(player, text, seconds)
  if not (player and player.valid and player.connected) then return end
  if theme.toast then theme.toast(player, text, { seconds = seconds or 6 }) else player.print(text) end
end

---------------------------------------------------------------------------------------------------------------------
-- data from Python, on a worker thread

local JOBS = {
  mods = "fse_tools.mods:listing",
  portal = "fse_tools.mods:portal",
  startup = "fse_tools.startup:report",
  catalog = "fse_tools.catalog:listing",
  update = "fse_tools.update:check",
}
local jobs = {}   -- kind -> job id
local data = {}   -- kind -> the answer as a table, or { error = "..." }
local by = {}     -- kind -> the player index who asked (their answer goes to them only)
local announced = false  -- (the newer fse said in chat once a session)
local views = {}  -- player_index -> what each view shows (sort, search, page)

local function fetch(kind, fn, input)
  if jobs[kind] or not has("py") then return end
  local id, e = native.start("py", fn or JOBS[kind], input or "")
  if id then jobs[kind] = id else data[kind] = { error = e or { "fse-hub.could-not-start" } } end
end

local function view(player_index)
  local v = views[player_index]
  if not v then
    v = { mods = { sort = "load", dir = 1, search = "", filter = 1, page = 1 },
          startup = { sort = "total_est", dir = -1, search = "", page = 1 },
          catalog = { sort = "name", dir = 1, search = "", page = 1 } }
    views[player_index] = v
  end
  return v
end

-- "Docked" off: the views as a row of tabs inside the window (per player)
local function docked(player)
  return not (storage.fhub_inside and storage.fhub_inside[player.index])
end

---------------------------------------------------------------------------------------------------------------------
-- formatting (game Lua has no os.date)

local function day(t)
  if not t then return "" end
  local z = math.floor(t / 86400) + 719468
  local era = math.floor(z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local d = doy - math.floor((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  local y = yoe + era * 400 + (m <= 2 and 1 or 0)
  return string.format("%04d-%02d-%02d", y, m, d)
end

local function size(b)
  if not b then return "" end
  if b >= 1048576 then return { "fse-hub.mb", string.format("%.1f", b / 1048576) } end
  return { "fse-hub.kb", math.ceil(b / 1024) }
end

local function secs(s, digits)
  if not s then return "?" end
  if s >= 60 and not digits then return { "fse-hub.min-s", math.floor(s / 60), math.floor(s % 60 + 0.5) } end
  return { "fse-hub.s", string.format("%." .. (digits or 1) .. "f", s) }
end

local function vkey(v)
  local k = {}
  for n in tostring(v):gmatch("%d+") do k[#k + 1] = tonumber(n) end
  return k
end

local function newer(a, b)
  local x, y = vkey(a), vkey(b)
  for i = 1, math.max(#x, #y) do
    if (x[i] or 0) ~= (y[i] or 0) then return (x[i] or 0) > (y[i] or 0) end
  end
  return false
end

-- a list of localised strings joined with ", " (nested: a localised string takes 20 parameters)
local function joined(list)
  if #list == 0 then return "" end
  local out = { "" }
  for i, x in ipairs(list) do
    if i > 1 then out[#out + 1] = ", " end
    out[#out + 1] = x
    if #out >= 19 and i < #list then
      local rest = {}
      for j = i + 1, #list do rest[#rest + 1] = list[j] end
      out[#out + 1] = ", "
      out[#out + 1] = joined(rest)
      break
    end
  end
  return out
end

---------------------------------------------------------------------------------------------------------------------
-- a sortable, searchable, paged table: headers are clickable labels.
-- A cell: text or a localised string, { caption =, tooltip = }, { button =, tags =, tooltip =, enabled = }, { bar = }

local function grid(parent, tab, cols, rows, state)
  local shown = {}  -- (a column with hide = true is left out: one with nothing in it)
  for _, c in ipairs(cols) do if not c.hide then shown[#shown + 1] = c end end
  cols = shown
  local key = state.sort
  local col
  for _, c in ipairs(cols) do if c.key == key then col = c end end
  local sorter = col and col.sort or function(r) return r[key] end
  table.sort(rows, function(a, b)
    local x, y = sorter(a), sorter(b)
    if x == y then return (a.name or "") < (b.name or "") end
    if x == nil then return false end
    if y == nil then return true end
    if state.dir > 0 then return x < y else return x > y end
  end)
  local pages = math.max(1, math.ceil(#rows / PAGE))
  state.page = math.min(state.page, pages)
  local first = (state.page - 1) * PAGE + 1
  local last = math.min(#rows, first + PAGE - 1)

  local pager = parent.add({ type = "flow", direction = "horizontal" })
  pager.style.vertical_align = "center"
  T(pager, { type = "button", caption = "◀", tags = { fhub_page = tab, d = -1 }, enabled = state.page > 1,
    tooltip = { "fse-hub.page-back" } }, "tool", BIG_TOOL)
  T(pager, { type = "label", caption = #rows == 0 and { "fse-hub.none" } or { "fse-hub.range", first, last, #rows } }, "text")
  T(pager, { type = "button", caption = "▶", tags = { fhub_page = tab, d = 1 }, enabled = state.page < pages,
    tooltip = { "fse-hub.page-next" } }, "tool", BIG_TOOL)

  local scroll = T(parent, { type = "scroll-pane", horizontal_scroll_policy = "never" }, "scroll",
    { vertically_stretchable = true, horizontally_stretchable = true })
  local t = style(scroll.add({ type = "table", column_count = #cols, draw_horizontal_line_after_headers = true }),
    { horizontal_spacing = 12 })
  for _, c in ipairs(cols) do
    local arrow = c.key == key and (state.dir > 0 and " ▲" or " ▼") or ""
    T(t, { type = "label", caption = { "", c.caption or "", arrow }, tooltip = { "fse-hub.sort" },
      tags = { fhub_sort = tab, key = c.key, desc = c.desc or false } }, "caption")
  end
  for i = first, last do
    local r = rows[i]
    for _, c in ipairs(cols) do
      local cell = c.cell(r, i)
      if type(cell) == "table" and cell.button then
        T(t, { type = "button", caption = cell.button, tags = cell.tags, tooltip = cell.tooltip,
          enabled = cell.enabled ~= false }, "button")
      elseif type(cell) == "table" and cell.bar then
        T(t, { type = "progressbar", value = math.min(1, math.max(0, cell.bar)) }, "progress", { width = 120 })
      else
        local caption, tooltip = cell, nil
        if type(cell) == "table" and (cell.caption ~= nil or cell.tooltip ~= nil) then caption, tooltip = cell.caption, cell.tooltip end
        if caption == nil then caption = "" elseif type(caption) ~= "table" then caption = tostring(caption) end
        T(t, { type = "label", caption = caption, tooltip = tooltip }, "text",
          { maximal_width = c.width, font_color = r.enabled == false and DIM or nil })
      end
    end
  end
end

local function message(parent, text)
  T(parent, { type = "label", caption = text }, "text", { single_line = false })
end

local function note(parent, text)
  T(parent, { type = "label", caption = text }, "dim", { single_line = false })
end

---------------------------------------------------------------------------------------------------------------------
-- Mods view

local FILTERS = { { "fse-hub.filter-all" }, { "fse-hub.filter-enabled" }, { "fse-hub.filter-disabled" },
  { "fse-hub.filter-added" }, { "fse-hub.filter-update" } }

local function render_mods(player)
  local frame = player.gui.screen[NAME]
  local body = frame and find(frame, "fhub_mods_body")
  if not body then return end
  body.clear()
  local d = data.mods
  if not d then
    fetch("mods")
    return message(body, { "fse-hub.reading-mods" })
  end
  if d.error then return message(body, { "fse-hub.mods-error", err(d.error) }) end
  local state = view(player.index).mods
  local portal = data.portal and not data.portal.error and data.portal or (data.portal and data.portal.cached) or {}
  local now = input.now() and input.now() / 1000  -- (ms)
  local search = state.search:lower()
  local rows = {}
  local any_portal = false  -- (the Portal column only once the portal has said something about a mod)
  for _, m in ipairs(d.mods or {}) do
    local p = portal[m.name]
    if p then any_portal = true end
    m.update = p and p.version and newer(p.version, m.version) and p.version or nil
    local hay = (m.name .. " " .. (m.title or "") .. " " .. (m.author or "")):lower()
    -- (the test runs' own helper mods, zzzz-test-*: not the player's)
    local ok = not m.name:find("^zzzz%-test%-") and (search == "" or hay:find(search, 1, true))
    local f = state.filter
    ok = ok and (f == 1 or (f == 2 and m.enabled) or (f == 3 and not m.enabled)
      or (f == 4 and now and m.added and now - m.added < 7 * 86400) or (f == 5 and m.update ~= nil))
    if ok then rows[#rows + 1] = m end
  end
  note(body, { "", { "fse-hub.mods-info", d.total or 0, d.enabled or 0 },
    data.portal and data.portal.error and { "fse-hub.portal-error", err(data.portal.error) } or "" })
  grid(body, "mods", {
    { key = "load", caption = "#", cell = function(m) return m.load or "" end },
    { key = "name", caption = { "fse-hub.col-mod" }, width = 260, sort = function(m) return (m.title or m.name):lower() end,
      cell = function(m)
        return { caption = m.title or m.name, tooltip = { "", m.name .. " " .. m.version,
          (m.author or "") ~= "" and { "fse-hub.by", m.author } or "", "\n" .. (m.description or "") .. "\n" .. m.file,
          m.enabled and "" or { "", "\n", { "fse-hub.disabled" } } } }
      end },
    { key = "version", caption = { "fse-hub.col-version" }, sort = function(m) return m.version end, cell = function(m) return m.version end },
    { key = "added", caption = { "fse-hub.col-added" }, desc = true, cell = function(m) return day(m.added) end },
    { key = "updated", caption = { "fse-hub.col-updated" }, desc = true, cell = function(m) return day(m.updated) end },
    { key = "size", caption = { "fse-hub.col-size" }, desc = true, cell = function(m) return size(m.size) end },
    { key = "update", caption = { "fse-hub.col-portal" }, hide = not any_portal,
      sort = function(m) return m.update and 0 or 1 end,
      cell = function(m)
        if m.update then return { caption = "[color=255,200,100]" .. m.update .. "[/color]", tooltip = { "fse-hub.portal-newer" } } end
        return portal[m.name] and { "fse-hub.latest" } or ""
      end },
  }, rows, state)
end

---------------------------------------------------------------------------------------------------------------------
-- Get mods view: the fse mod catalog (github.com/watdafawx/fse-mods)

local function render_catalog(player)
  local frame = player.gui.screen[NAME]
  local body = frame and find(frame, "fhub_catalog_body")
  if not body then return end
  body.clear()
  local d = data.catalog
  if not d then
    fetch("catalog")
    return message(body, { "fse-hub.reading-index" })
  end
  local state = view(player.index).catalog
  local search = state.search:lower()
  local fse = native.version()
  local rows = {}
  for _, m in ipairs(d.mods or {}) do
    local needs, words = {}, {}
    if m.fse and newer(m.fse, fse) then
      needs[#needs + 1] = { "fse-hub.needs-fse", m.fse }
      words[#words + 1] = "fse " .. m.fse
    end
    for _, p in ipairs(m.plugins or {}) do
      if not has(p) then
        needs[#needs + 1] = { "fse-hub.needs-plugin", p }
        words[#words + 1] = "plugin " .. p
      end
    end
    m.blocked = #needs > 0  -- (fse and plugins come only with an fse release; missing mods from the portal)
    for _, n in ipairs(m.missing or {}) do
      needs[#needs + 1] = n
      words[#words + 1] = n
    end
    m.needs = table.concat(words, ", ")  -- (to sort by)
    m.needs_text = joined(needs)
    m.state = not m.installed and "install" or newer(m.version, m.installed) and "update" or "latest"
    local hay = (m.name .. " " .. (m.title or "") .. " " .. (m.author or "") .. " " .. (m.description or "")):lower()
    if search == "" or hay:find(search, 1, true) then rows[#rows + 1] = m end
  end
  note(body, { "", { "fse-hub.catalog-info", #(d.mods or {}), d.index or "" },
    d.error and { "", " · ", err(d.error) } or "" })
  if jobs.install then message(body, { "fse-hub.installing", tostring(data.installing) }) end
  grid(body, "catalog", {
    { key = "name", caption = { "fse-hub.col-mod" }, width = 300, sort = function(m) return (m.title or m.name):lower() end,
      cell = function(m)
        return { caption = m.title or m.name, tooltip = { "", m.name, m.author and { "fse-hub.by", m.author } or "", "\n"
          .. (m.description or "") .. (m.repo and ("\n" .. m.repo) or "") } }
      end },
    { key = "version", caption = { "fse-hub.col-version" }, cell = function(m) return m.version end },
    { key = "installed", caption = { "fse-hub.col-installed" }, sort = function(m) return m.installed or "" end,
      cell = function(m) return m.installed or "" end },
    { key = "state", caption = "", cell = function(m)
        if m.state == "latest" then return { "fse-hub.installed" } end
        return { button = m.state == "update" and { "fse-hub.update" } or { "fse-hub.install" },
          tags = { fhub = "install", mod = m.name }, enabled = not jobs.install and not m.blocked,
          tooltip = m.blocked and { "fse-hub.blocked-tooltip" } or { "fse-hub.install-tooltip", m.name, m.version } }
      end },
    { key = "needs", caption = { "fse-hub.col-needs" }, width = 220, cell = function(m)
        return m.needs ~= "" and { caption = { "", "[color=255,200,100]", m.needs_text, "[/color]" },
          tooltip = { "fse-hub.needs-tooltip" } } or ""
      end },
  }, rows, state)
end

---------------------------------------------------------------------------------------------------------------------
-- Startup view

local function render_startup(player)
  local frame = player.gui.screen[NAME]
  local body = frame and find(frame, "fhub_startup_body")
  if not body then return end
  body.clear()
  local d = data.startup
  if not d then
    fetch("startup")
    return message(body, { "fse-hub.reading-log" })
  end
  if d.error then return message(body, { "fse-hub.startup-error", err(d.error) }) end
  T(body, { type = "label", caption = { "fse-hub.started-in", secs(d.total) } }, "caption")
  -- (two phases a row: the mods below get the room)
  local phases = style(body.add({ type = "table", column_count = 6 }), { horizontal_spacing = 10 })
  for _, p in ipairs(d.phases or {}) do
    T(phases, { type = "label", caption = p.name, tooltip = p.what ~= "" and p.what or nil }, "text")
    T(phases, { type = "progressbar", value = d.total and d.total > 0 and math.min(1, (p.seconds or 0) / d.total) or 0 },
      "progress", { width = 110 })
    T(phases, { type = "label", caption = secs(p.seconds) }, "text", { minimal_width = 70 })
  end
  theme.separator(body)
  local state = view(player.index).startup
  local search = state.search:lower()
  local rows, top = {}, 0
  for _, m in ipairs(d.mods or {}) do
    top = math.max(top, m.total_est or 0)
    if search == "" or m.name:lower():find(search, 1, true) then rows[#rows + 1] = m end
  end
  local stage_tip = function(m)
    local parts = {}
    for stage, s in pairs(m.stages or {}) do parts[#parts + 1] = stage .. " " .. string.format("%.2f", s) end
    table.sort(parts)
    return table.concat(parts, "\n")
  end
  local function s2(v) return secs(v or 0, 2) end
  grid(body, "startup", {
    { key = "name", caption = { "fse-hub.col-mod" }, width = 240, sort = function(m) return m.name:lower() end,
      cell = function(m) return { caption = m.name, tooltip = stage_tip(m) } end },
    { key = "lua", caption = { "fse-hub.col-lua" }, desc = true, cell = function(m) return s2(m.lua) end },
    { key = "sprites_est", caption = { "fse-hub.col-sprites" }, desc = true, cell = function(m) return s2(m.sprites_est) end },
    { key = "sounds_est", caption = { "fse-hub.col-sounds" }, desc = true, cell = function(m) return s2(m.sounds_est) end },
    { key = "total_est", caption = { "fse-hub.col-total" }, desc = true, cell = function(m) return s2(m.total_est) end },
    { key = "bar", caption = "", sort = function(m) return m.total_est end,
      cell = function(m) return { bar = top > 0 and (m.total_est or 0) / top or 0 } end },
  }, rows, state)
  note(body, { "fse-hub.startup-note" })
end

---------------------------------------------------------------------------------------------------------------------
-- Hub view

local function profile_rows(table_el)
  table_el.clear()
  for _, h in ipairs({ "fse-hub.prof-function", "fse-hub.prof-ms", "fse-hub.prof-calls" }) do
    T(table_el, { type = "label", caption = { h } }, "caption")
  end
  local p = has("profiler") and native.call("profiler", "profile", "hub")
  p = p and helpers.json_to_table(p)
  if not (p and p.active) then
    T(table_el, { type = "label", caption = { "fse-hub.prof-stopped" } }, "dim")
    table_el.add({ type = "empty-widget" })
    table_el.add({ type = "empty-widget" })
    return
  end
  local n = 0
  for _, f in ipairs(p.functions or {}) do
    if f.calls > 0 and n < 10 then
      n = n + 1
      T(table_el, { type = "label", caption = f.name, tooltip = f.name }, "text", { maximal_width = FN_W })
      T(table_el, { type = "label", caption = string.format("%.3f", f.ms_per_tick) }, "text")
      T(table_el, { type = "label", caption = string.format("%.1f", f.calls_per_tick) }, "text")
    end
  end
end

-- a newer fse on GitHub (fse_tools.update): the version, and Update when this install can update itself
local function update_row(flow)
  flow.clear()
  local u = data.update
  if data.updated then
    T(flow, { type = "label", caption = { "", "[color=120,220,120]", { "fse-hub.updated", data.updated }, "[/color]" } }, "text")
    return
  end
  if not (u and u.newer) then return end
  if not (u.installable or jobs.update_install) then
    -- (a dev build, or a release without its checksum: one sentence saying what to do; the release's page in the tooltip)
    local why = tostring(u.why or ""):find("sha256") and "fse-hub.update-no-sha" or "fse-hub.update-manual"
    T(flow, { type = "label", caption = { why, u.latest, u.current }, tooltip = { "", u.url or "", "\n", u.notes or "" } },
      "text", { single_line = false, maximal_width = 700 })
    return
  end
  T(flow, { type = "label", caption = { "fse-hub.update-out", u.latest, u.current }, tooltip = u.notes }, "text")
  if jobs.update_install then
    T(flow, { type = "label", caption = { "fse-hub.downloading" } }, "dim")
  else
    T(flow, { type = "button", caption = { "fse-hub.update" }, tags = { fhub = "update" },
      tooltip = { "fse-hub.update-tooltip", u.latest } }, "ok")
  end
end

local function hub_view(content)
  local build = native.build and native.build() or {}
  T(content, { type = "label", caption = { "fse-hub.about", native.version(), tostring(build.build or "?"):sub(1, 8),
    table.concat(plugins(), ", ") } }, "text", { single_line = false })
  local up = content.add({ type = "flow", name = "fhub_update", direction = "horizontal" })
  up.style.vertical_align = "center"
  update_row(up)
  local links = content.add({ type = "flow", direction = "horizontal" })
  local bp = remote.interfaces["bpgen"] and "bpgen" or remote.interfaces["bpgen-companion"] and "bpgen-companion"
  if bp and remote.interfaces[bp].open_window then  -- (bpgen's mod; "bpgen-companion" before 0.6)
    T(links, { type = "button", caption = "bpgen", tags = { fhub = "bpgen" }, tooltip = { "fse-hub.bpgen-tooltip" } }, "button")
  end
  if has("web") then
    T(links, { type = "button", caption = { "fse-hub.dashboard" }, tags = { fhub = "dashboard" },
      tooltip = { "fse-hub.dashboard-tooltip" } }, "button")
    T(links, { type = "button", caption = { "fse-hub.copy-link" }, tags = { fhub = "copy" },
      tooltip = { "fse-hub.copy-link-tooltip" } }, "button")
  end
  theme.separator(content)
  local prow = content.add({ type = "flow", direction = "horizontal" })
  prow.style.vertical_align = "center"
  T(prow, { type = "label", caption = { "fse-hub.engine-profile" } }, "caption")
  if has("profiler") then
    T(prow, { type = "button", caption = { "fse-hub.start" }, tags = { fhub = "start" },
      tooltip = { "fse-hub.start-tooltip" } }, "button")
    T(prow, { type = "button", caption = { "fse-hub.stop" }, tags = { fhub = "stop" } }, "button")
  end
  local scroll = T(content, { type = "scroll-pane", name = "fhub_scroll" }, "scroll", { vertically_stretchable = true })
  local prof = style(scroll.add({ type = "table", name = "fhub_profile", column_count = 3 }), { horizontal_spacing = 16 })
  prof.style.column_alignments[2], prof.style.column_alignments[3] = "right", "right"
  profile_rows(prof)
  if remote.interfaces.agent then
    theme.separator(content)
    local names = {}
    for n in pairs(remote.call("agent", "list") or {}) do names[#names + 1] = n end
    T(content, { type = "label", caption = { "fse-hub.agents",
      #names > 0 and table.concat(names, ", ") or { "fse-hub.agents-none" } } }, "text")
  end
end

---------------------------------------------------------------------------------------------------------------------

local TABS = { "hub", "mods", "startup", "catalog" }
local RAIL_W = 112  -- (the rail of views out of the window's left edge, GUI units)
local TAB_NAMES = { { "fse-hub.tab-hub" }, { "fse-hub.tab-mods" }, { "fse-hub.tab-startup" }, { "fse-hub.tab-catalog" } }
local RENDER = { mods = render_mods, startup = render_startup, catalog = render_catalog }

local function render(player, tab)
  if RENDER[tab] then RENDER[tab](player) end
  local frame = player.gui.screen[NAME]
  scaled(frame and find(frame, "fhub_" .. tab .. "_body"))
end

-- the open view's tools and body, in the window's page flow
local function page(player, tab)
  local frame = player.gui.screen[NAME]
  local holder = frame and find(frame, "fhub_page")
  if not holder then return end
  holder.clear()
  if tab == "hub" then
    hub_view(holder)
  else
    local v = view(player.index)
    local controls = holder.add({ type = "flow", direction = "horizontal" })
    style(controls, { vertical_align = "center", horizontal_spacing = 6 })
    -- (a search icon before the field says what it is; theme.search gives it a clear button)
    local th = theme.of(player)
    local light = theme.themes.by_name[th.carrier] and theme.themes.by_name[th.carrier].light
    controls.add({ type = "sprite", sprite = light and helpers.is_valid_sprite_path("fstd-black-search") and "fstd-black-search"
      or "utility/search",
      tooltip = { "fse-hub.search-tooltip" } })
    local search = theme.search(controls, "fhub_" .. tab, { "fse-hub.search-tooltip" })
    theme.apply(search.children[1], "field", { width = 230 }).text = v[tab].search
    if search.children[2] then theme.apply(search.children[2], "tool", BIG_TOOL) end
    if tab == "mods" then
      T(controls, { type = "drop-down", items = FILTERS, selected_index = v.mods.filter, tags = { fhub_filter = "mods" },
        tooltip = { "fse-hub.filter-tooltip" } }, "dropdown")
      T(controls, { type = "button", caption = { "fse-hub.check-portal" }, tags = { fhub = "portal" },
        tooltip = { "fse-hub.check-portal-tooltip" } }, "button")
    end
    T(controls, { type = "button", caption = { "fse-hub.reload" }, tags = { fhub = "reload", tab = tab },
      tooltip = { "fse-hub.reload-tooltip-" .. tab } }, "button")
    local inner = holder.add({ type = "flow", direction = "vertical", name = "fhub_" .. tab .. "_body" })
    inner.style.vertically_stretchable = true
    inner.style.horizontally_stretchable = true
    render(player, tab)
  end
  scaled(holder)
end

-- the view tabs: the rail's (docked) or the row inside the window
local function tab_row(player)
  local rail = player.gui.screen[NAME .. "__left"]
  return rail and rail.get_mod() == script.mod_name and rail.fhub_rail or find(player.gui.screen[NAME], "fhub_tabs")
end

-- the view tabs show tab i as the open one
local function mark_tab(player, i)
  local row = tab_row(player)
  if row then for _, b in pairs(row.children) do b.toggled = b.tags.fhub_tab == i end end
end

-- the window's rail and settings (theme.attach)
local function drop_attached(player)
  for _, c in pairs(player.gui.screen.children) do
    local a = c.tags.fstd_attach
    if a and a.owner == NAME and c.get_mod() == script.mod_name then c.destroy() end
  end
end

local function close(player)
  local frame = player.gui.screen[NAME]
  if frame then frame.destroy() end
  drop_attached(player)
  sync_button(player)
end

local function open(player, tab)
  drop_attached(player)  -- (built again: another layout, or its first size)
  local frame, content = window.create(player, { name = NAME, title = { "fse-hub.title" }, width = 760, height = 500,
    min_width = 420, min_height = 260, themed = true, settings = true })
  player.opened = frame  -- (Esc closes it)
  sync_button(player)
  if not loaded() then
    message(content, { "fse-hub.no-loader" })
    return frame
  end
  local v = view(player.index)
  v.tab = tab or v.tab or "hub"
  local selected = 1
  for i, name in ipairs(TABS) do if name == v.tab then selected = i end end
  if docked(player) then
    -- (the rail's own flow: a frame's spacing is the theme's)
    local rail = theme.attach(frame, "left", { size = { RAIL_W, #TABS * 34 + 8 }, along = 40, overlap = 6,
      role = "inset", direction = "vertical", padding = 4 })
    local flow = style(rail.add({ type = "flow", name = "fhub_rail", direction = "vertical" }), { vertical_spacing = 4 })
    for i, caption in ipairs(TAB_NAMES) do
      T(flow, { type = "button", caption = caption, toggled = i == selected, tags = { fhub_tab = i } }, "rtab",
        { width = RAIL_W - 8, height = 30 })
    end
    scaled(rail)
  else
    local row = theme.tabs(content, TAB_NAMES, selected, "fhub_tab")
    row.name = "fhub_tabs"
    style(row, { bottom_margin = 6 })
  end
  local holder = content.add({ type = "flow", name = "fhub_page", direction = "vertical" })
  holder.style.vertically_stretchable = true
  holder.style.horizontally_stretchable = true
  page(player, v.tab)
  scaled(content)
  return frame
end

-- the window's settings (the gear by its close button)
local function settings(player)
  local frame = player.gui.screen[NAME]
  local sized = window.size_setting ~= nil  -- (the window's own Size: fse-std 0.8)
  local m = frame and theme.menu(frame, { size = { 250, sized and 210 or 168 }, keep_opened = true })
  if not m then return end
  T(m, { type = "label", caption = { "fse-hub.title" } }, "caption")
  T(m, { type = "checkbox", name = "fhub_docked", caption = { "fstd.docked" }, state = docked(player),
    tooltip = { "fstd.docked-tooltip" } }, "check")
  if sized then window.size_setting(m, NAME) end
  local wide = { horizontally_stretchable = true, minimal_width = 0, height = 28 }
  if remote.interfaces["fse-std"] and remote.interfaces["fse-std"].open_theme then
    T(m, { type = "button", caption = { "fstd.theme-button" }, tags = { fhub = "theme" },
      tooltip = { "fstd.theme-button-tooltip" } }, "button", wide)
  end
  T(m, { type = "button", caption = { "fstd.reset-place" }, tags = { fhub = "reset_size" },
    tooltip = { "fstd.reset-place-tooltip" } }, "button", wide)
end

local function rerender(kind)
  for _, player in pairs(game.connected_players) do
    local frame = player.gui.screen[NAME]
    if frame and (kind == "update" or kind == "update_install") then
      local row = find(frame, "fhub_update")
      if row then update_row(row); scaled(row) end
    elseif frame then
      render(player, kind)
    end
  end
end

local function install(name, player_index)
  if jobs.install then return end
  data.installing, data.install, by.install = name, nil, player_index
  fetch("install", "fse_tools.catalog:install", name)
  rerender("catalog")
end

local function click(e)
  local el = e.element
  if not (el and el.valid) then return end
  local player = game.get_player(e.player_index)
  if el.name == "fse_hub_button" then
    if player.gui.screen[NAME] then close(player) else open(player) end
    return
  end
  if el.get_mod() ~= script.mod_name then return end
  local tags = el.tags
  if tags.fstd_settings == NAME then return settings(player) end
  local v = view(player.index)
  if tags.fhub_tab then
    v.tab = TABS[tags.fhub_tab]
    mark_tab(player, tags.fhub_tab)
    return page(player, v.tab)
  elseif tags.fhub_sort then
    local s = v[tags.fhub_sort]
    if s.sort == tags.key then s.dir = -s.dir else s.sort, s.dir = tags.key, tags.desc and -1 or 1 end
    s.page = 1
    return render(player, tags.fhub_sort)
  elseif tags.fhub_page then
    local s = v[tags.fhub_page]
    s.page = math.max(1, s.page + tags.d)
    return render(player, tags.fhub_page)
  end
  local action = tags.fhub
  if not action then return end
  if action == "bpgen" then
    close(player)
    remote.call(remote.interfaces["bpgen"] and "bpgen" or "bpgen-companion", "open_window", player.index)
  elseif action == "update" then
    by.update_install = player.index
    fetch("update_install", "fse_tools.update:install", "")
    rerender("update")
  elseif action == "dashboard" then
    open_page("")
  elseif action == "copy" then
    local url = web_url("")
    if url and input.clipboard_set(url) then say(player, { "fse-hub.link-copied" }, 3) end
  elseif action == "portal" then
    data.portal = nil
    fetch("portal")
    say(player, { "fse-hub.asking-portal" }, 3)
  elseif action == "install" then
    install(tags.mod, player.index)
  elseif action == "reload" then
    data[tags.tab] = nil
    render(player, tags.tab)
  elseif action == "start" or action == "stop" then
    native.call("profiler", action)
    native.call("profiler", "profile", "hub")  -- (a fresh baseline)
    local p = find(player.gui.screen[NAME], "fhub_profile")
    if p then profile_rows(p); scaled(p) end
  elseif action == "theme" then
    local menu = player.gui.screen[NAME .. "__menu"]
    if menu then menu.destroy() end
    remote.call("fse-std", "open_theme", player.index)
  elseif action == "reset_size" then
    -- (its place and size; its own Size stays: that is a setting of its own)
    if window.reset_place then window.reset_place(player, NAME)
    elseif storage.fstd_windows and storage.fstd_windows[player.index] then storage.fstd_windows[player.index][NAME] = nil end
    open(player, v.tab)
  end
end

local function poll()
  for kind, id in pairs(jobs) do
    local status, out = native.poll(id)
    if status ~= "pending" then
      jobs[kind] = nil
      if status == "done" then
        data[kind] = helpers.json_to_table(out) or { error = { "fse-hub.unreadable" } }
      else
        data[kind] = { error = tostring(out) }
      end
      local who = by[kind] and game.get_player(by[kind])
      by[kind] = nil
      if kind == "update" and data.update.newer and not announced then
        announced = true  -- (single player: the one player)
        for _, p in pairs(game.connected_players) do
          p.print({ "fse-hub.update-announce", data.update.latest, data.update.current })
        end
      elseif kind == "update_install" then
        local r = data.update_install
        if r.ok then data.updated = r.version end
        say(who, r.ok and { "fse-hub.updated", r.version } or { "fse-hub.update-failed", err(r.error) }, 8)
      end
      if kind == "install" then
        local r = data.install
        say(who, r.ok and { "fse-hub.install-done", r.name, r.version, r.pypath and { "fse-hub.install-pypath" } or "" }
          or { "fse-hub.install-failed", err(r.error) }, 8)
        data.catalog, data.mods = nil, nil
        kind = "catalog"
      end
      rerender(kind == "portal" and "mods" or kind)
    end
  end
end

local function refresh()
  -- (the button only where the hub works: a save that moved to multiplayer, or lost the loader, drops it)
  for _, player in pairs(game.connected_players) do
    local b = mod_gui.get_button_flow(player).fse_hub_button
    if (b ~= nil) ~= available() then sync_button(player) end
  end
  if not available() then return end
  -- (once a session: is there a newer fse?)
  if not data.update and not jobs.update and has("py") then fetch("update", nil, native.version()) end
  if not has("profiler") then return end
  for _, player in pairs(game.connected_players) do
    local frame = player.gui.screen[NAME]
    local v = views[player.index]
    if frame and (not v or v.tab == "hub") then
      local p = find(frame, "fhub_profile")
      if p then profile_rows(p); scaled(p) end
    end
  end
end

local function sync_all()
  for _, player in pairs(game.players) do sync_button(player) end
end

-- the window closed by its X (window.lua): unlit at once
window.on_close(function(player, name) if name == NAME then sync_button(player) end end)

-- typed in (or cleared) a view's search box
theme.on_search(function(player, name, text)
  local tab = name:match("^fhub_(.+)$")
  local s = tab and view(player.index)[tab]
  if not s or type(s) ~= "table" then return end
  s.search, s.page = text, 1
  render(player, tab)
end)

local safe = require("__fse-std__/safe")
script.on_init(safe.guard("fse-hub", sync_all))
script.on_configuration_changed(safe.guard("fse-hub", sync_all))
script.on_nth_tick(60, safe.guard("fse-hub", refresh))
script.on_nth_tick(10, safe.guard("fse-hub", function() if next(jobs) then poll() end end))

-- for tests
remote.add_interface("fse-hub", { open = function(pi, tab) open(game.get_player(pi), tab) end,
  close = function(pi) close(game.get_player(pi)) end,
  url = function(path) return web_url(path) end,
  install = function(name, pi) install(name, pi) end,
  settings = function(pi) settings(game.get_player(pi)) end,
  docked = function(pi, on)
    local player = game.get_player(pi)
    storage.fhub_inside = storage.fhub_inside or {}
    storage.fhub_inside[pi] = (not on) or nil
    if player.gui.screen[NAME] then open(player, view(pi).tab) end
  end,
  -- where the window and its rail are (pixels), its size (GUI units at 100 %) and scale, the screen
  geometry = function(pi)
    local p = game.get_player(pi)
    local f = p.gui.screen[NAME]
    if not f then return nil end
    local rail = p.gui.screen[NAME .. "__left"]
    local w, h = window.size(p, NAME)
    return { x = f.location.x, y = f.location.y, w = w or 760, h = h or 500, ds = p.display_scale,
      scale = theme.scale_of and theme.scale_of(f) or 1, rail_x = rail and rail.location.x,
      rail_y = rail and rail.location.y, res_w = p.display_resolution.width, res_h = p.display_resolution.height,
      menu = p.gui.screen[NAME .. "__menu"] ~= nil }
  end,
  -- the hub button's look: { style, toggled } or nil
  button_state = function(pi)
    local b = mod_gui.get_button_flow(game.get_player(pi)).fse_hub_button
    return b and { style = b.style.name, toggled = b.toggled } or nil
  end,
  -- the view tabs' captions on the rail (docked) or the row inside: { where = "rail"|"inside", n }
  tabs = function(pi)
    local row = tab_row(game.get_player(pi))
    return row and { where = row.name == "fhub_rail" and "rail" or "inside", n = #row.children } or nil
  end,
  update_row = function(pi)  -- (the Hub view's update line: "label" / "[button]" per element)
    local frame = game.get_player(pi).gui.screen[NAME]
    local row = frame and find(frame, "fhub_update")
    if not row then return nil end
    local parts = {}
    for _, c in pairs(row.children) do parts[#parts + 1] = c.type == "button" and "[button]" or "label" end
    return table.concat(parts, " ")
  end,
  button = function(pi, mod)  -- (a catalog row's Install button: "enabled", "disabled" or nil)
    local function walk(el)
      if el.type == "button" and el.tags.mod == mod then return el.enabled and "enabled" or "disabled" end
      for _, c in pairs(el.children) do
        local r = walk(c)
        if r then return r end
      end
    end
    local frame = game.get_player(pi).gui.screen[NAME]
    return frame and walk(frame)
  end,
  loaded = function(kind)
    local d = data[kind]
    if d == nil then return false end
    if d.error then return type(d.error) == "table" and "error" or d.error end
    return true
  end })

events.register({ input.handlers, window.handlers, theme.handlers, {
  [defines.events.on_gui_click] = click,
  [defines.events.on_gui_closed] = function(e)  -- (Esc)
    local el = e.element
    if el and el.valid and el.name == NAME and el.get_mod() == script.mod_name then
      close(game.get_player(e.player_index))
    end
  end,
  [defines.events.on_gui_checked_state_changed] = function(e)
    local el = e.element
    if not (el and el.valid and el.name == "fhub_docked" and el.get_mod() == script.mod_name) then return end
    local player = game.get_player(e.player_index)
    storage.fhub_inside = storage.fhub_inside or {}
    storage.fhub_inside[player.index] = (not el.state) or nil
    open(player, view(player.index).tab)  -- (built again that way; its settings close with it)
  end,
  [defines.events.on_gui_selection_state_changed] = function(e)
    local el = e.element
    if not (el and el.valid and el.tags.fhub_filter) then return end
    local s = view(e.player_index).mods
    s.filter, s.page = el.selected_index, 1
    render_mods(game.get_player(e.player_index))
  end,
  [defines.events.on_player_created] = function(e) sync_button(game.get_player(e.player_index)) end,
  [defines.events.on_player_joined_game] = function(e) sync_button(game.get_player(e.player_index)) end,
  [defines.events.on_runtime_mod_setting_changed] = function(e)
    local b = e.setting == "gu_button_style_setting" and e.player_index
      and mod_gui.get_button_flow(game.get_player(e.player_index)).fse_hub_button
    if b then sync_button(game.get_player(e.player_index)) end
  end,
} })
