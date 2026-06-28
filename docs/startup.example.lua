--[[ Exemple de script de démarrage automatique.
  Copiez ce fichier vers /startup.lua sur l'ordinateur pour lancer CC_Radio au boot,
  avec redémarrage automatique en cas de crash.
  Adaptez MODE et les options à votre usage.
]]
local MODE = "broadcaster" -- "broadcaster" | "client" | "local"
local ARGS = {}            -- ex: {"--label", "Ma Radio"} ou {"--id", "5"}

while true do
  local ok, err = pcall(function()
    shell.run("CC_Radio", MODE, table.unpack(ARGS))
  end)
  if ok then break end -- sortie normale (X / Ctrl+T)
  printError("CC_Radio a plante: " .. tostring(err))
  print("Redemarrage dans 5 s...")
  sleep(5)
end
