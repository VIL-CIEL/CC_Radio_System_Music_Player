--[[ CC_RSMP - ui/gui.lua
  Affichage compagnon sur monitor (tactile) : un rendu unifié "now playing + boutons"
  pour les trois modes. Le terminal porte l'interface complète (voir ui/app.lua) ;
  le monitor sert d'affichage et de télécommande en complément.
]]
local Widgets = require("ui.widgets")
local Utils   = require("lib.utils")

local GUI = {}

GUI.MIN_W, GUI.MIN_H = 26, 12

-- Boutons compagnons (id = action interprétée par ctx.dispatch).
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

function GUI.companionButtons(kind, w, h)
  local items = (kind == "client") and GUI.CLIENT_ITEMS or GUI.BROADCASTER_ITEMS
  return Widgets.buttonRow(items, w, h - 2, 3)
end

--- Mappe une touche tactile en id d'action. @return string|nil
function GUI.handleTouch(buttons, x, y)
  local b = Widgets.hitTest(buttons, x, y)
  return b and b.id or nil
end

local function txt(mon, x, y, s, fg) Widgets.text(mon, x, y, s, fg or colors.white, colors.black) end

--- Affiche le panneau compagnon. snap = ctx.np().
function GUI.drawCompanion(mon, snap, kind, buttons)
  local w = select(1, mon.getSize())
  mon.setBackgroundColor(colors.black); mon.clear()

  local title = "CC_RADIO" .. ((snap.label and snap.label ~= "") and (" " .. snap.label) or "")
  txt(mon, 2, 1, title:sub(1, w - 8), colors.yellow)
  if kind == "client" then
    local sig = snap.signal or "?"
    local c = (sig == "connected") and colors.lime or (sig == "lost") and colors.red or colors.gray
    txt(mon, w - #sig - 1, 1, sig, c)
  elseif snap.state == "playing" then
    txt(mon, w - 8, 1, "ON AIR", colors.red)
  else
    txt(mon, w - 6, 1, "IDLE", colors.gray)
  end

  txt(mon, 2, 3, (Utils.trim(snap.name) or "---"):sub(1, w - 2))
  txt(mon, 2, 4, (Utils.trim(snap.artist) or ""):sub(1, w - 2), colors.lightGray)

  local dur = snap.duration or 0
  local frac = (dur > 0) and ((snap.elapsed or 0) / dur) or 0
  Widgets.hbar(mon, 2, 6, w - 14, frac, colors.lime, colors.gray)
  txt(mon, w - 11, 6, Utils.formatTime(snap.elapsed or 0) .. (dur > 0 and ("/" .. Utils.formatTime(dur)) or ""))

  local line = ("Vol %.1f"):format(snap.volume or 0)
  if kind == "broadcaster" then line = line .. "   Clients: " .. (snap.clients or 0) end
  txt(mon, 2, 8, line)
  if kind == "client" and snap.label then txt(mon, 2, 9, "Station: " .. snap.label, colors.lightGray) end

  for _, b in ipairs(buttons) do Widgets.drawButton(mon, b, false) end
end

return GUI
