--[[ CC_RSMP - ui/cli.lua
  Interface en ligne de commande (terminal). S1 : affichage "now playing" minimal
  + sélecteur de résultats de recherche. L'UI interactive complète arrive en S2.
]]
local Utils = require("lib.utils")

local CLI = {}

local function color(c)
  if term.isColor() then term.setTextColor(c) end
end

--- Parse une durée "M:SS" ou "H:MM:SS" présente dans une chaîne -> secondes, ou nil.
function CLI.parseDuration(s)
  if type(s) ~= "string" then return nil end
  local h, m, sec = s:match("(%d+):(%d+):(%d+)")
  if h then return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(sec) end
  local mm, ss = s:match("(%d+):(%d+)")
  if mm then return tonumber(mm) * 60 + tonumber(ss) end
  return nil
end

--- Construit une barre de progression de largeur `width`.
function CLI.bar(frac, width, fillCh, emptyCh)
  frac = math.max(0, math.min(1, frac or 0))
  local n = math.floor(frac * width + 0.5)
  return string.rep(fillCh or "=", n) .. string.rep(emptyCh or " ", width - n)
end

-- Une entrée "ressemble" à un vrai titre si son champ artist contient une durée.
local function looksLikeTrack(it)
  return type(it.artist) == "string" and it.artist:match("%d+:%d+") ~= nil
end

--- Affiche les résultats numérotés et demande un choix.
-- @return table|nil  l'item choisi (playlist -> 1er morceau), ou nil si annulé
function CLI.pickResult(results)
  if not results or #results == 0 then
    print("Aucun resultat.")
    return nil
  end

  local default = 1
  for i, it in ipairs(results) do
    if looksLikeTrack(it) then default = i; break end
  end

  color(colors.yellow); print("Resultats:"); color(colors.white)
  local shown = math.min(#results, 8)
  for i = 1, shown do
    local it = results[i]
    local tag = (it.type == "playlist") and " [playlist]" or ""
    print(string.format("%2d. %s%s", i, Utils.trim(it.name) or "?", tag))
    color(colors.lightGray); print("    " .. (Utils.trim(it.artist) or "")); color(colors.white)
  end

  write(("Choix [%d] (q=annuler): "):format(default))
  local input = read()
  if input == "q" or input == "Q" then return nil end
  local idx = tonumber(input) or default
  local it = results[idx]
  if not it then return nil end
  if it.type == "playlist" and it.playlist_items and it.playlist_items[1] then
    return it.playlist_items[1]
  end
  return it
end

--- Affiche l'écran "lecture en cours".
-- @param state table { song = {name,artist}, elapsed = sec, duration = sec|nil, volume = 0-3 }
function CLI.drawNowPlaying(state)
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)

  color(colors.yellow); print("== CC_Radio - Lecture locale =="); color(colors.white)
  print("")
  print(Utils.trim(state.song.name) or "?")
  color(colors.lightGray); print(Utils.trim(state.song.artist) or ""); color(colors.white)
  print("")

  local dur  = state.duration
  local frac = (dur and dur > 0) and (state.elapsed / dur) or 0
  local tline = Utils.formatTime(state.elapsed)
  if dur then tline = tline .. " / " .. Utils.formatTime(dur) end
  print("[" .. CLI.bar(frac, 24) .. "] " .. tline)
  print("")

  print("Vol: [" .. CLI.bar((state.volume or 0) / 3, 10, "#") .. "] "
    .. string.format("%.1f", state.volume or 0))
  print("")
  color(colors.gray); print("[Haut/Bas] volume   [Q] stop"); color(colors.white)
end

return CLI
