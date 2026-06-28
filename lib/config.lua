--[[ CC_RSMP - lib/config.lua
  Lecture / écriture de la configuration persistante (config.json).
  Le fichier JSON est fusionné avec DEFAULTS : toute clé manquante reprend sa valeur par défaut.
]]
local Config = {}

Config.PATH = "config.json"

-- Valeurs par défaut. api_url corrigée d'après le code source réel de terreng
-- (Cloud Run, et non l'URL cloudfunctions du brief).
Config.DEFAULTS = {
  station_label          = "CC Radio",
  default_mode           = "broadcaster",     -- "broadcaster" | "client" | "local"
  default_volume         = 1.0,               -- volume broadcaster (0.0 - 3.0)
  local_volume           = 1.0,               -- volume local client (0.0 - 3.0)
  loop                   = "off",             -- "off" | "one" | "all"
  shuffle                = false,
  api_url                = "https://ipod-2to6magyna-uc.a.run.app/",
  api_version            = "2.1",             -- param ?v= attendu par l'API terreng
  rednet_protocol_prefix = "CC_RSMP",
  auto_discover          = true,
  monitor_side           = "auto",
  chunk_size_kb          = 16,                -- spike S0 : 16 KiB OK (round-trip intègre, ~3.2x sérialisé)
  audio_encoding         = "base64",          -- "base64" (~1.34x) | "raw" (~3.2x) — spike S3
  http_retries           = 2,                 -- nb de tentatives supplémentaires sur échec HTTP
  meta_interval_sec      = 5,
  discovery_interval_sec = 30,
  log_level              = "info",            -- "debug" | "info" | "warn" | "error"
  max_queue_size         = 50,
  history_size           = 10,
}

--- Charge la config depuis `path` (ou Config.PATH), complétée par les défauts.
function Config.load(path)
  path = path or Config.PATH
  local data = {}
  if fs.exists(path) then
    local f = fs.open(path, "r")
    if f then
      local raw = f.readAll()
      f.close()
      local ok, parsed = pcall(textutils.unserialiseJSON, raw)
      if ok and type(parsed) == "table" then data = parsed end
    end
  end
  for k, v in pairs(Config.DEFAULTS) do
    if data[k] == nil then data[k] = v end
  end
  return data
end

--- Sauvegarde `cfg` en JSON.
function Config.save(cfg, path)
  path = path or Config.PATH
  local f = fs.open(path, "w")
  if not f then return false, "Impossible d'ouvrir " .. path end
  f.write(textutils.serialiseJSON(cfg))
  f.close()
  return true
end

--- Réécrit une config neuve (valeurs par défaut) et la renvoie.
function Config.reset(path)
  local fresh = {}
  for k, v in pairs(Config.DEFAULTS) do fresh[k] = v end
  Config.save(fresh, path)
  return fresh
end

return Config
