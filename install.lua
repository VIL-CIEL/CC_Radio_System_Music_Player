--[[ CC_RSMP - install.lua
  Installeur / mise à jour autonome. Télécharge tous les fichiers du programme
  depuis le dépôt GitHub (raw). Réexécutable pour mettre à jour.

  Usage (sur un ordinateur CC: Tweaked) :
    wget https://raw.githubusercontent.com/VIL-CIEL/CC_Radio_System_Music_Player/main/install.lua install.lua
    install
]]
local REPO = "https://raw.githubusercontent.com/VIL-CIEL/CC_Radio_System_Music_Player/main/"

local FILES = {
  "CC_Radio.lua",
  "install.lua",
  "core/audio.lua", "core/broadcaster.lua", "core/client.lua", "core/downloader.lua",
  "core/network.lua", "core/playlist.lua", "core/player.lua", "core/prereq.lua",
  "lib/base64.lua", "lib/config.lua", "lib/discovery.lua", "lib/logger.lua", "lib/utils.lua",
  "ui/cli.lua", "ui/gui.lua", "ui/help.lua", "ui/widgets.lua",
}

local function download(path)
  local r = http.get(REPO .. path)
  if not r then return false end
  local data = r.readAll()
  r.close()
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(path, "w")
  if not f then return false end
  f.write(data)
  f.close()
  return true
end

print("Installation de CC_RSMP...")
if not http then
  printError("HTTP desactive cote serveur. Activez http_enabled dans computercraft-server.toml.")
  return
end

local okN, failN = 0, 0
for _, path in ipairs(FILES) do
  if download(path) then
    okN = okN + 1
    print("[OK] " .. path)
  else
    failN = failN + 1
    printError("[X] " .. path)
  end
end

print(("Termine : %d fichiers, %d echec(s)."):format(okN, failN))
if failN == 0 then
  print("Installation reussie ! Lancement de CC_Radio...")
  sleep(1)
  shell.run("CC_Radio")
end
