--[[ CC_RSMP - ui/gui.lua
  Interface graphique sur monitor : détection, layouts broadcaster/client, rendu,
  et mapping des touches tactiles (monitor_touch) vers des actions.
]]
local Widgets = require("ui.widgets")
local Utils   = require("lib.utils")

local GUI = {}

GUI.MIN_W, GUI.MIN_H = 26, 12

-- Boutons (id = nom d'action, interprété par broadcaster/client).
GUI.BROADCASTER_ITEMS = {
  { id = "prev", label = "<<" }, { id = "playpause", label = "|>" },
  { id = "skip", label = ">>" }, { id = "shuffle", label = "SHUF" },
  { id = "loop", label = "LOOP" },
}
GUI.CLIENT_ITEMS = {
  { id = "voldown", label = "VOL-" }, { id = "volup", label = "VOL+" },
  { id = "status", label = "STAT" }, { id = "disconnect", label = "DISC" },
}

--- Détecte un monitor utilisable. @return mon, w, h  OU  nil, errstr
function GUI.detect(cfg)
  local mon = peripheral.find("monitor")
  if not mon then return nil, "aucun monitor detecte" end
  pcall(mon.setTextScale, 0.5)
  local w, h = mon.getSize()
  if w < GUI.MIN_W or h < GUI.MIN_H then
    return nil, ("monitor trop petit (%dx%d, min %dx%d)"):format(w, h, GUI.MIN_W, GUI.MIN_H)
  end
  return mon, w, h
end

function GUI.buttons(kind, w, h)
  local items = (kind == "client") and GUI.CLIENT_ITEMS or GUI.BROADCASTER_ITEMS
  return Widgets.buttonRow(items, w, h - 2, 3)
end

--- Mappe une touche tactile en id d'action. @return string|nil
function GUI.handleTouch(buttons, x, y)
  local b = Widgets.hitTest(buttons, x, y)
  return b and b.id or nil
end

local function clearMon(mon)
  mon.setBackgroundColor(colors.black)
  mon.clear()
end
GUI.clear = clearMon

local function progress(mon, w, elapsed, duration)
  local frac = (duration and duration > 0) and (elapsed / duration) or 0
  Widgets.hbar(mon, 2, 6, w - 16, frac, colors.lime, colors.gray)
  local tline = Utils.formatTime(elapsed) .. (duration and duration > 0 and (" / " .. Utils.formatTime(duration)) or "")
  Widgets.text(mon, w - 13, 6, tline, colors.white, colors.black)
end

function GUI.drawBroadcaster(mon, state, playlist, audio, nClients, buttons)
  local w = select(1, mon.getSize())
  clearMon(mon)
  Widgets.text(mon, 2, 1, "CC_RADIO", colors.yellow, colors.black)
  if state.playbackState == "playing" then
    Widgets.text(mon, w - 8, 1, "ON AIR", colors.red, colors.black)
  else
    Widgets.text(mon, w - 6, 1, "IDLE", colors.gray, colors.black)
  end

  Widgets.text(mon, 2, 3, (state.song and Utils.trim(state.song.name) or "(rien)"):sub(1, w - 2), colors.white, colors.black)
  Widgets.text(mon, 2, 4, (state.song and Utils.trim(state.song.artist) or ""):sub(1, w - 2), colors.lightGray, colors.black)

  progress(mon, w, state.elapsed or 0, state.duration)

  Widgets.text(mon, 2, 8, ("Vol %.1f   Clients: %d"):format(audio.volume, nClients or 0), colors.white, colors.black)
  local modes = {}
  if playlist.loop ~= "off" then modes[#modes + 1] = "loop:" .. playlist.loop end
  if playlist.shuffle then modes[#modes + 1] = "shuffle" end
  Widgets.text(mon, 2, 9, table.concat(modes, " "), colors.lime, colors.black)

  for _, b in ipairs(buttons) do
    local active = (b.id == "shuffle" and playlist.shuffle)
        or (b.id == "loop" and playlist.loop ~= "off")
        or (b.id == "playpause" and state.playbackState == "playing")
    Widgets.drawButton(mon, b, active)
  end
end

function GUI.drawClient(mon, view, audio, buttons)
  local w = select(1, mon.getSize())
  clearMon(mon)
  Widgets.text(mon, 2, 1, "CC_RADIO CLIENT", colors.yellow, colors.black)
  local sigColor = (view.signal == "connected") and colors.lime
      or (view.signal == "lost") and colors.red or colors.gray
  Widgets.text(mon, w - #(view.signal or "") - 1, 1, view.signal or "", sigColor, colors.black)

  Widgets.text(mon, 2, 3, (Utils.trim(view.title) or "---"):sub(1, w - 2), colors.white, colors.black)
  Widgets.text(mon, 2, 4, (Utils.trim(view.author) or ""):sub(1, w - 2), colors.lightGray, colors.black)

  progress(mon, w, view.position or 0, view.duration)

  local vol = (audio and audio.volume) or view.volume or 0
  Widgets.text(mon, 2, 8, ("Vol local %.1f"):format(vol), colors.white, colors.black)
  if view.lost and view.lost > 0 then
    Widgets.text(mon, 2, 9, "Pertes: " .. view.lost, colors.orange, colors.black)
  end

  for _, b in ipairs(buttons) do Widgets.drawButton(mon, b, false) end
end

return GUI
