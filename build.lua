--[[ CC_RSMP - build.lua
  Génère dist/CC_Radio.lua : un FICHIER UNIQUE exécutable regroupant tous les modules
  (via package.preload) + le point d'entrée. Permet une install/désinstall triviales :
    install  : un seul fichier à télécharger
    désinstall : delete CC_Radio

  Le code source reste modulaire (core/ ui/ lib/) ; relancer build.lua après modification.
  Exécuter sur un ordinateur/émulateur disposant des sources : `build`
]]
local MODULES = {
  "lib.utils", "lib.config", "lib.logger", "lib.base64", "lib.discovery",
  "core.prereq", "core.downloader", "core.audio", "core.playlist", "core.player",
  "core.network", "core.broadcaster", "core.client",
  "ui.widgets", "ui.gui", "ui.cli", "ui.help", "ui.app",
}
local ENTRY = "CC_Radio.lua"
local OUT   = "dist/CC_Radio.lua"

local function readAll(path)
  local f = assert(fs.open(path, "r"), "introuvable: " .. path)
  local s = f.readAll(); f.close()
  return s
end

local parts = {
  "-- CC_RSMP - fichier unique genere par build.lua (NE PAS EDITER A LA MAIN)",
  "-- Source modulaire: VIL-CIEL/CC_Radio_System_Music_Player ; credit audio: terreng (MIT)",
  "local preload = {}",
}
for _, m in ipairs(MODULES) do
  local path = m:gsub("%.", "/") .. ".lua"
  parts[#parts + 1] = ("preload[%q] = function(...)"):format(m)
  parts[#parts + 1] = readAll(path)
  parts[#parts + 1] = "end"
end
parts[#parts + 1] = "for k, v in pairs(preload) do package.preload[k] = v end"
parts[#parts + 1] = "-- ===================== point d'entree ====================="
parts[#parts + 1] = readAll(ENTRY)

local data = table.concat(parts, "\n")
if not fs.exists("dist") then fs.makeDir("dist") end
local o = assert(fs.open(OUT, "w"))
o.write(data); o.close()
print(("Bundle ecrit: %s (%d octets, %d modules)"):format(OUT, #data, #MODULES))
