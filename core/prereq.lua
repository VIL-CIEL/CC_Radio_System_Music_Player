--[[ CC_RSMP - core/prereq.lua
  Détection du matériel (modem, speaker, monitor) et vérification des prérequis logiciels.
  Note : peripheral.find renvoie l'OBJET wrappé en premier (le nom s'obtient via
  peripheral.getName) — contrairement à ce qu'indique le brief.
]]
local Prereq = {}

--- CC: Tweaked >= 1.100.0 : l'API audio doit être disponible.
function Prereq.hasAudioApi()
  return (pcall(require, "cc.audio.dfpwm"))
end

--- @return string|nil name, table|nil modem
function Prereq.findModem()
  local modem = peripheral.find("modem")
  if not modem then return nil end
  return peripheral.getName(modem), modem
end

--- @return table liste des speakers wrappés (peut être vide)
function Prereq.findSpeakers()
  return { peripheral.find("speaker") }
end

--- @return table|nil monitor wrappé
function Prereq.findMonitor()
  return peripheral.find("monitor")
end

--- Vérifie les prérequis pour un mode donné.
-- @param mode string "broadcaster" | "client" | "local"
-- @return table { ok, errors={}, warnings={}, modem, modem_name, speakers, monitor }
function Prereq.check(mode)
  local r = { ok = true, errors = {}, warnings = {} }

  if not Prereq.hasAudioApi() then
    r.ok = false
    r.errors[#r.errors + 1] = "CC: Tweaked >= 1.100.0 requis (API cc.audio.dfpwm absente)."
  end

  r.modem_name, r.modem = Prereq.findModem()
  r.speakers = Prereq.findSpeakers()
  r.monitor  = Prereq.findMonitor()

  -- Modem : obligatoire dès qu'il y a du réseau.
  if (mode == "broadcaster" or mode == "client") and not r.modem then
    r.ok = false
    r.errors[#r.errors + 1] = "Aucun modem détecté (obligatoire pour le réseau)."
  end

  -- Speaker : obligatoire en client, optionnel ailleurs.
  if mode == "client" and #r.speakers == 0 then
    r.ok = false
    r.errors[#r.errors + 1] = "Aucun speaker détecté (obligatoire en mode client)."
  elseif (mode == "broadcaster" or mode == "local") and #r.speakers == 0 then
    r.warnings[#r.warnings + 1] = "Aucun speaker : pas de lecture locale (broadcast seul)."
  end

  if not r.monitor then
    r.warnings[#r.warnings + 1] = "Aucun monitor : interface graphique indisponible (CLI uniquement)."
  end

  return r
end

return Prereq
