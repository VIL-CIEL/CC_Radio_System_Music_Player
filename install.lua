--[[ CC_RSMP - install.lua
  Installeur : télécharge le fichier unique CC_Radio.lua puis le lance.
  Usage : wget run https://raw.githubusercontent.com/VIL-CIEL/CC_Radio_System_Music_Player/main/install.lua
  Désinstallation : delete CC_Radio.lua
]]
local URL = "https://raw.githubusercontent.com/VIL-CIEL/CC_Radio_System_Music_Player/main/dist/CC_Radio.lua"

print("Installation de CC_Radio...")
if not http then
  printError("HTTP desactive cote serveur (http_enabled dans computercraft-server.toml).")
  return
end
local r = http.get(URL)
if not r then
  printError("Echec du telechargement.")
  return
end
local data = r.readAll(); r.close()
local f = fs.open("CC_Radio.lua", "w")
f.write(data); f.close()

print("Installe ! Fichier unique : CC_Radio.lua")
print("Lancer       : CC_Radio")
print("Desinstaller : delete CC_Radio.lua")
sleep(1)
shell.run("CC_Radio")
