--[[ CC_RSMP - ui/app.lua
  Interface unifiée sur le TERMINAL (inspirée du programme de terreng) :
  - écran d'accueil : choix du mode (Broadcast / Client / Local) ;
  - onglets Now Playing / Search / Queue, recherche scrollable et cliquable, contrôles.

  L'app est pilotée par un `ctx` fourni par le moteur (broadcaster/client/local) :
    ctx.mode        "broadcaster" | "client" | "local"
    ctx.cfg         configuration
    ctx.np()        -> { name, artist, elapsed, duration, state, volume, signal, clients, label }
    ctx.queueList() -> { {name, artist}, ... }  (chansons à venir)
    ctx.dispatch(action, args) -> exit:boolean
      actions : playpause skip prev volup voldown loop shuffle
                playnow|enqueue|playnext {song}   remove {index}   status   exit

  Le monitor est géré séparément par le moteur (companion tactile, voir ui/gui.lua).
]]
local Widgets    = require("ui.widgets")
local GUI        = require("ui.gui")
local Downloader = require("core.downloader")
local Utils      = require("lib.utils")

local App = {}

local TABS = { "Now Playing", "Search", "Queue" }

local function setColor(c) if term.isColor() then term.setTextColor(c) end end
local function clear() term.setBackgroundColor(colors.black); term.clear() end

--- Restaure un terminal (et un monitor) propres pour rendre la main au shell.
function App.cleanup(mon)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  if mon then
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1, 1)
  end
end
local function trunc(s, n) s = Utils.trim(s) or ""; if #s > n then return s:sub(1, n - 1) .. ">" end return s end

-- ───────────────────────── Écran d'accueil ─────────────────────────

function App.home()
  local btns = {}
  local function draw()
    clear()
    local w = select(1, term.getSize())
    term.setCursorPos(math.max(1, math.floor((w - 8) / 2)), 2)
    setColor(colors.yellow); term.write("CC_RADIO"); setColor(colors.white)
    term.setCursorPos(2, 4); setColor(colors.lightGray); term.write("Choisissez un mode :"); setColor(colors.white)
    local items = {
      { id = "broadcaster", label = "[B] Broadcast (serveur radio)" },
      { id = "client",      label = "[C] Client (recepteur)" },
      { id = "local",       label = "[L] Lecture locale" },
      { id = "quit",        label = "[Q] Quitter" },
    }
    btns = {}
    local y = 6
    for _, it in ipairs(items) do
      local b = { id = it.id, label = " " .. it.label, x = 2, y = y, w = w - 3, h = 2,
        bg = (it.id == "quit") and colors.gray or colors.blue }
      Widgets.drawButton(term, b, false)
      btns[#btns + 1] = b
      y = y + 3
    end
  end
  draw()
  local choice
  while choice == nil do
    local ev = { os.pullEvent() }
    if ev[1] == "mouse_click" then
      local b = Widgets.hitTest(btns, ev[3], ev[4])
      if b then choice = b.id; break end
    elseif ev[1] == "char" then
      local c = ev[2]:lower()
      if c == "b" then choice = "broadcaster"
      elseif c == "c" then choice = "client"
      elseif c == "l" then choice = "local"
      elseif c == "q" then choice = "quit" end
    elseif ev[1] == "term_resize" then
      draw()
    end
  end
  App.cleanup()
  return choice ~= "quit" and choice or nil
end

-- ───────────────────────── Rendu des onglets ─────────────────────────

-- Calcule les zones cliquables des onglets. @return liste {name,x,w}, index 1..3
local function tabRegions()
  local regions, x = {}, 1
  for i, name in ipairs(TABS) do
    local label = " " .. name .. " "
    regions[i] = { i = i, x = x, w = #label, label = label }
    x = x + #label + 1
  end
  return regions
end

local function drawTabs(ui)
  term.setCursorPos(1, 1); term.setBackgroundColor(colors.gray); term.clearLine()
  for _, r in ipairs(tabRegions()) do
    term.setCursorPos(r.x, 1)
    if r.i == ui.tab then
      term.setBackgroundColor(colors.white); setColor(colors.black)
    else
      term.setBackgroundColor(colors.gray); setColor(colors.white)
    end
    term.write(r.label)
  end
  term.setBackgroundColor(colors.black); setColor(colors.white)
end

local function drawNowPlaying(ctx, ui)
  local w, h = term.getSize()
  local s = ctx.np()
  term.setCursorPos(2, 3); setColor(colors.white); term.write(trunc(s.name or "---", w - 2))
  term.setCursorPos(2, 4); setColor(colors.lightGray); term.write(trunc(s.artist or "", w - 2)); setColor(colors.white)

  local dur = s.duration or 0
  local frac = (dur > 0) and ((s.elapsed or 0) / dur) or 0
  Widgets.hbar(term, 2, 6, w - 14, frac, colors.lime, colors.gray)
  term.setCursorPos(w - 11, 6)
  term.write(Utils.formatTime(s.elapsed or 0) .. (dur > 0 and ("/" .. Utils.formatTime(dur)) or ""))

  term.setCursorPos(2, 8)
  term.write(("Vol %.1f"):format(s.volume or 0))
  if s.state then term.write("   " .. s.state) end
  if ctx.mode == "broadcaster" then
    term.write("   Clients: " .. (s.clients or 0))
  elseif ctx.mode == "client" then
    term.setCursorPos(2, 9); setColor(colors.lightGray)
    term.write("Station: " .. (s.label or "?") .. "  [" .. (s.signal or "?") .. "]"); setColor(colors.white)
  end

  -- Boutons de contrôle (bas)
  local items
  if ctx.mode == "client" then
    items = { { id = "voldown", label = "V-" }, { id = "volup", label = "V+" },
      { id = "status", label = "STAT" }, { id = "exit", label = "QUIT" } }
  else
    items = { { id = "prev", label = "<<" }, { id = "playpause", label = "|>" },
      { id = "skip", label = ">>" }, { id = "loop", label = "LOOP" },
      { id = "shuffle", label = "SHUF" }, { id = "exit", label = "QUIT" } }
  end
  ui.npButtons = Widgets.buttonRow(items, w, h - 2, 3)
  for _, b in ipairs(ui.npButtons) do Widgets.drawButton(term, b, false) end
end

local function drawList(items, ui, top, bottom, renderItem)
  local rows = bottom - top + 1
  local maxScroll = math.max(0, #items - rows)
  if ui.scroll > maxScroll then ui.scroll = maxScroll end
  if ui.scroll < 0 then ui.scroll = 0 end
  ui.rowMap = {} -- ligne écran -> index item
  for r = 0, rows - 1 do
    local idx = ui.scroll + r + 1
    local y = top + r
    term.setCursorPos(1, y); term.clearLine()
    if items[idx] then
      ui.rowMap[y] = idx
      renderItem(idx, items[idx], y, idx == ui.selected)
    end
  end
  if #items > rows then -- indicateur de scroll
    term.setCursorPos(select(1, term.getSize()), top)
    setColor(colors.gray); term.write(ui.scroll > 0 and "^" or "|")
    term.setCursorPos(select(1, term.getSize()), bottom)
    term.write(ui.scroll < maxScroll and "v" or "|"); setColor(colors.white)
  end
end

local function drawSearch(ctx, ui)
  local w, h = term.getSize()
  -- barre de recherche
  ui.searchBtn = { id = "search", x = 2, y = 3, w = w - 3, h = 1 }
  term.setCursorPos(2, 3); term.setBackgroundColor(colors.gray); setColor(colors.white)
  term.write(trunc(" Rechercher: " .. (ui.query ~= "" and ui.query or "(cliquer / touche /)"), w - 3))
  term.setBackgroundColor(colors.black); setColor(colors.white)

  local results = ui.results or {}
  local bottom = ui.selected and (h - 3) or (h - 1)
  if #results == 0 then
    term.setCursorPos(2, 5); setColor(colors.lightGray)
    term.write(ui.searching and "Recherche..." or "Aucun resultat. Lancez une recherche.")
    setColor(colors.white)
  else
    drawList(results, ui, 5, bottom, function(idx, it, y, seld)
      term.setCursorPos(1, y)
      term.setBackgroundColor(seld and colors.blue or colors.black)
      setColor(colors.white)
      term.write(" " .. trunc(it.name or "?", w - 2))
      term.setBackgroundColor(colors.black)
    end)
  end
  -- actions sur sélection
  if ui.selected and results[ui.selected] then
    ui.selButtons = Widgets.buttonRow(
      { { id = "playnow", label = "Play" }, { id = "playnext", label = "Next" },
        { id = "enqueue", label = "Queue" } }, w, h - 1, 1)
    for _, b in ipairs(ui.selButtons) do Widgets.drawButton(term, b, false) end
  else
    ui.selButtons = nil
  end
end

local function drawQueue(ctx, ui)
  local w, h = term.getSize()
  local q = ctx.queueList()
  term.setCursorPos(2, 3); setColor(colors.cyan); term.write("File (" .. #q .. ")"); setColor(colors.white)
  if #q == 0 then
    term.setCursorPos(2, 5); setColor(colors.lightGray); term.write("(vide)"); setColor(colors.white)
  else
    drawList(q, ui, 5, h - 1, function(idx, it, y, seld)
      term.setCursorPos(1, y); setColor(colors.white)
      term.write(("%2d. %s"):format(idx, trunc(it.name or "?", w - 5)))
    end)
  end
end

local function render(ctx, ui)
  clear()
  drawTabs(ui)
  if ui.tab == 1 then drawNowPlaying(ctx, ui)
  elseif ui.tab == 2 then drawSearch(ctx, ui)
  else drawQueue(ctx, ui) end
  local _, h = term.getSize()
  term.setCursorPos(1, h); setColor(colors.gray)
  term.write(" [1/2/3] onglets  [/] recherche  [X] quitter"); setColor(colors.white)
end

-- ───────────────────────── Interactions ─────────────────────────

local function runSearch(ctx, ui)
  local w, h = term.getSize()
  term.setCursorPos(2, 3); term.setBackgroundColor(colors.gray); term.clearLine()
  setColor(colors.white); term.write(" Rechercher: ")
  term.setBackgroundColor(colors.black)
  local q = read()
  if not q or q == "" then return end
  ui.query, ui.searching, ui.results, ui.selected, ui.scroll = q, true, nil, nil, 0
  render(ctx, ui)
  local results = Downloader.search(ctx.cfg, q)
  ui.searching = false
  ui.results = results or {}
end

-- @return exit:boolean
local function onChar(ctx, ui, c)
  c = c:lower()
  if c == "1" then ui.tab, ui.scroll = 1, 0
  elseif c == "2" then ui.tab, ui.scroll = 2, 0
  elseif c == "3" then ui.tab, ui.scroll = 3, 0
  elseif c == "/" then ui.tab = 2; runSearch(ctx, ui)
  elseif c == "x" then return ctx.dispatch("exit")
  elseif ui.tab == 1 then
    local map = { p = "playpause", s = "skip", b = "prev", ["+"] = "volup",
      ["="] = "volup", ["-"] = "voldown", l = "loop", z = "shuffle" }
    if map[c] then return ctx.dispatch(map[c]) end
  end
  return false
end

local function onScroll(ui, dir)
  if ui.tab == 2 or ui.tab == 3 then ui.scroll = math.max(0, ui.scroll + dir) end
end

-- @return exit:boolean
local function onClick(ctx, ui, x, y)
  if y == 1 then -- barre d'onglets
    for _, r in ipairs(tabRegions()) do
      if x >= r.x and x < r.x + r.w then ui.tab, ui.scroll, ui.selected = r.i, 0, nil; return false end
    end
    return false
  end
  if ui.tab == 1 and ui.npButtons then
    local b = Widgets.hitTest(ui.npButtons, x, y)
    if b then return ctx.dispatch(b.id) end
  elseif ui.tab == 2 then
    if ui.searchBtn and x >= ui.searchBtn.x and x < ui.searchBtn.x + ui.searchBtn.w and y == ui.searchBtn.y then
      runSearch(ctx, ui); return false
    end
    if ui.selButtons then
      local b = Widgets.hitTest(ui.selButtons, x, y)
      if b and ui.results[ui.selected] then
        ctx.dispatch(b.id, { song = ui.results[ui.selected] })
        ui.selected = nil
        return false
      end
    end
    if ui.rowMap and ui.rowMap[y] then ui.selected = ui.rowMap[y] end
  elseif ui.tab == 3 then
    if ui.rowMap and ui.rowMap[y] then ctx.dispatch("remove", { index = ui.rowMap[y] }) end
  end
  return false
end

--- Boucle principale de l'interface terminal.
function App.run(ctx)
  local ui = { tab = 1, scroll = 0, query = "", results = nil, selected = nil }
  render(ctx, ui)
  local timer = os.startTimer(0.5)
  while true do
    local ev = { os.pullEvent() }
    local e = ev[1]
    if e == "timer" and ev[2] == timer then
      render(ctx, ui); timer = os.startTimer(0.5)
    elseif e == "char" then
      if onChar(ctx, ui, ev[2]) then return end
      render(ctx, ui)
    elseif e == "mouse_click" then
      if onClick(ctx, ui, ev[3], ev[4]) then return end
      render(ctx, ui)
    elseif e == "mouse_scroll" then
      onScroll(ui, ev[2]); render(ctx, ui)
    elseif e == "term_resize" then
      render(ctx, ui)
    end
  end
end

--- Boucle compagnon sur le monitor (affichage + boutons tactiles).
function App.monitor(ctx, mon)
  local w, h = mon.getSize()
  local buttons = GUI.companionButtons(ctx.mode, w, h)
  local function draw() GUI.drawCompanion(mon, ctx.np(), ctx.mode, buttons) end
  draw()
  local timer = os.startTimer(0.5)
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "monitor_touch" then
      local id = GUI.handleTouch(buttons, ev[3], ev[4])
      if id then ctx.dispatch(id == "disconnect" and "exit" or id) end
      draw()
    elseif ev[1] == "timer" and ev[2] == timer then
      draw(); timer = os.startTimer(0.5)
    end
  end
end

App._internal = { tabRegions = tabRegions, onClick = onClick, onScroll = onScroll,
  onChar = onChar, render = render }

return App
