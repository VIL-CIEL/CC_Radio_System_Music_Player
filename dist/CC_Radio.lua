-- CC_RSMP - fichier unique genere par build.lua (NE PAS EDITER A LA MAIN)
-- Source modulaire: VIL-CIEL/CC_Radio_System_Music_Player ; credit audio: terreng (MIT)
local preload = {}
preload["lib.utils"] = function(...)
--[[ CC_RSMP - lib/utils.lua
  Fonctions utilitaires partagées : parsing d'arguments, formatage, helpers tables.
]]
local Utils = {}

--- Parse les arguments shell.
-- Convention : "--key value" -> flags.key = value ; "--flag" seul -> flags.flag = true.
-- @param argv table  liste d'arguments (le `...` du programme)
-- @return table { positional = { ... }, flags = { [key] = value|true } }
function Utils.parseArgs(argv)
  local res = { positional = {}, flags = {} }
  local i = 1
  while i <= #argv do
    local a = argv[i]
    if type(a) == "string" and a:sub(1, 2) == "--" then
      local key = a:sub(3)
      local nxt = argv[i + 1]
      if nxt ~= nil and not (type(nxt) == "string" and nxt:sub(1, 2) == "--") then
        res.flags[key] = nxt
        i = i + 2
      else
        res.flags[key] = true
        i = i + 1
      end
    else
      res.positional[#res.positional + 1] = a
      i = i + 1
    end
  end
  return res
end

--- Formate des secondes en "m:ss".
function Utils.formatTime(sec)
  sec = math.max(0, math.floor(tonumber(sec) or 0))
  return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

--- Borne une valeur dans [lo, hi].
function Utils.clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi else return v end
end

--- Vrai si la séquence `t` contient `val`.
function Utils.contains(t, val)
  for _, v in ipairs(t) do
    if v == val then return true end
  end
  return false
end

--- Coerce une chaîne CLI en booléen / nombre / chaîne.
function Utils.coerce(v)
  if v == true or v == false then return v end
  if v == "true" then return true end
  if v == "false" then return false end
  local n = tonumber(v)
  if n ~= nil then return n end
  return v
end

--- Supprime les espaces en début/fin de chaîne.
function Utils.trim(s)
  if type(s) ~= "string" then return s end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Extrait l'identifiant vidéo YouTube d'une URL (ou renvoie l'id si déjà brut).
-- @return string|nil
function Utils.extractYtId(url)
  if type(url) ~= "string" then return nil end
  return url:match("youtu%.be/([%w_%-]+)")
      or url:match("[?&]v=([%w_%-]+)")
      or (url:match("^[%w_%-]+$") and url)
      or nil
end

--- Copie superficielle d'une table.
function Utils.shallowCopy(t)
  local r = {}
  for k, v in pairs(t) do r[k] = v end
  return r
end

return Utils

end
preload["lib.config"] = function(...)
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
  sync_lead_ms           = 1000,              -- avance (ms) envoi->lecture client (latence ; synchro inter-clients)
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

end
preload["lib.logger"] = function(...)
--[[ CC_RSMP - lib/logger.lua
  Logger à niveaux : écrit dans un fichier et, en option, sur le terminal.
  Usage : local log = Logger.new({ level = "info" }) ; log:info("message")
]]
local Logger = {}
Logger.__index = Logger

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }
local COLORS = {
  debug = colors.gray,
  info  = colors.white,
  warn  = colors.yellow,
  error = colors.red,
}

--- Crée un logger.
-- @param opts table { path = "CC_Radio.log", level = "info", toTerm = true }
function Logger.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Logger)
  self.path   = opts.path or "CC_Radio.log"
  self.level  = LEVELS[opts.level or "info"] or LEVELS.info
  self.toTerm = opts.toTerm ~= false -- défaut : true
  return self
end

function Logger:setLevel(level)
  self.level = LEVELS[level] or self.level
end

function Logger:_write(level, msg)
  if (LEVELS[level] or LEVELS.info) < self.level then return end
  local stamp = textutils.formatTime(os.time(), true)
  local line  = string.format("[%s] [%s] %s", stamp, level:upper(), tostring(msg))

  local f = fs.open(self.path, "a")
  if f then f.writeLine(line); f.close() end

  if self.toTerm then
    if term.isColor() then
      local prev = term.getTextColor()
      term.setTextColor(COLORS[level] or colors.white)
      print(line)
      term.setTextColor(prev)
    else
      print(line)
    end
  end
end

function Logger:debug(m) self:_write("debug", m) end
function Logger:info(m)  self:_write("info",  m) end
function Logger:warn(m)  self:_write("warn",  m) end
function Logger:error(m) self:_write("error", m) end

return Logger

end
preload["lib.base64"] = function(...)
--[[ CC_RSMP - lib/base64.lua
  Encodage/décodage base64 (arithmétique, sans dépendre des opérateurs bit Lua 5.3).
  Sert à transmettre les chunks DFPWM binaires via rednet : la sérialisation d'une
  string binaire gonfle ~3.2x (échappements), alors que sa version base64 ~1.34x.
  Mesuré : encode/décode ~6 ms pour 16 KiB (négligeable vs ~2.7 s d'audio/chunk).
]]
local Base64 = {}

local CH = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENC, DEC = {}, {}
for i = 0, 63 do
  local c = CH:sub(i + 1, i + 1)
  ENC[i] = c
  DEC[c:byte()] = i
end

function Base64.encode(data)
  local t, n, i = {}, #data, 1
  while i <= n do
    local b1 = data:byte(i)
    local b2 = data:byte(i + 1)
    local b3 = data:byte(i + 2)
    t[#t + 1] = ENC[math.floor(b1 / 4)]
    t[#t + 1] = ENC[(b1 % 4) * 16 + math.floor((b2 or 0) / 16)]
    if b2 then
      t[#t + 1] = ENC[(b2 % 16) * 4 + math.floor((b3 or 0) / 64)]
      t[#t + 1] = b3 and ENC[b3 % 64] or "="
    else
      t[#t + 1] = "=="
    end
    i = i + 3
  end
  return table.concat(t)
end

function Base64.decode(s)
  local t, i, n = {}, 1, #s
  while i <= n do
    local a = DEC[s:byte(i)]
    local b = DEC[s:byte(i + 1)]
    local cb = s:byte(i + 2)
    local db = s:byte(i + 3)
    local c = (cb and cb ~= 61) and DEC[cb] or nil
    local d = (db and db ~= 61) and DEC[db] or nil
    if a and b then
      t[#t + 1] = string.char(a * 4 + math.floor(b / 16))
      if c then t[#t + 1] = string.char((b % 16) * 16 + math.floor(c / 4)) end
      if c and d then t[#t + 1] = string.char((c % 4) * 64 + d) end
    end
    i = i + 4
  end
  return table.concat(t)
end

return Base64

end
preload["lib.discovery"] = function(...)
--[[ CC_RSMP - lib/discovery.lua
  Découverte de station : écoute les annonces DISCO du broadcaster, et envoi du join.
]]
local Discovery = {}

--- Attend une annonce DISCO et renvoie les infos du broadcaster.
-- Envoie d'abord une requête "who" : les stations répondent aussitôt (même sans musique).
-- @return table|nil { id, label, song_title }
function Discovery.findBroadcaster(net, timeout)
  net:announce({ type = "who" })
  local sender, msg, mproto = net:receiveAny(timeout or 10)
  while sender do
    if mproto == net.P.DISCO and type(msg) == "table" and msg.type == "announce" then
      return { id = msg.broadcaster_id or sender, label = msg.label, song_title = msg.song_title }
    end
    sender, msg, mproto = net:receiveAny(timeout or 10)
  end
  return nil
end

--- Liste toutes les stations actives (annonces uniques) sur une fenêtre de temps.
-- Envoie "who" pour que les stations se signalent immédiatement.
-- @return table liste de { id, label, song_title }
function Discovery.listBroadcasters(net, seconds)
  net:announce({ type = "who" })
  local seen, list = {}, {}
  local deadline = os.epoch("utc") + (seconds or 2) * 1000
  while true do
    local left = (deadline - os.epoch("utc")) / 1000
    if left <= 0 then break end
    local sender, msg, mproto = net:receiveAny(left)
    if not sender then break end
    if mproto == net.P.DISCO and type(msg) == "table" and msg.type == "announce" then
      local id = msg.broadcaster_id or sender
      if not seen[id] then
        seen[id] = true
        list[#list + 1] = { id = id, label = msg.label or ("Station " .. id), song_title = msg.song_title }
      end
    end
  end
  return list
end

--- Envoie un message DISCO:join au broadcaster (ou en broadcast si id absent).
function Discovery.join(net, broadcasterId, label)
  net:join(broadcasterId, {
    type = "join",
    client_id = os.getComputerID(),
    label = label,
  })
end

return Discovery

end
preload["core.prereq"] = function(...)
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

end
preload["core.downloader"] = function(...)
--[[ CC_RSMP - core/downloader.lua
  Recherche et streaming audio via l'API terreng (computercraft-streaming-music).
  Contrat (validé sur l'API en direct) :
    - recherche : GET <api>?v=<ver>&search=<query>  -> JSON (liste de {id,name,artist,type?})
    - download  : GET <api>?v=<ver>&id=<id> (binary) -> flux DFPWM
                  on lit d'abord 4 octets (header) puis des chunks de chunkBytes.
  Le champ `id` correspond à l'identifiant vidéo YouTube.
  Crédit : terreng (MIT) — voir CREDITS.md.
]]
local Downloader = {}

-- http.get avec quelques tentatives (robustesse réseau).
local function httpGet(url, headers, binary, retries)
  retries = retries or 0
  local r, err
  for attempt = 0, retries do
    r, err = http.get(url, headers, binary)
    if r then return r end
    if attempt < retries then os.sleep(1) end
  end
  return nil, (tostring(err) .. " (apres " .. (retries + 1) .. " tentatives)")
end

function Downloader.searchUrl(cfg, query)
  return cfg.api_url .. "?v=" .. textutils.urlEncode(cfg.api_version)
      .. "&search=" .. textutils.urlEncode(query)
end

function Downloader.downloadUrl(cfg, id)
  return cfg.api_url .. "?v=" .. textutils.urlEncode(cfg.api_version)
      .. "&id=" .. textutils.urlEncode(id)
end

--- Recherche synchrone.
-- @return table|nil results, string|nil err
function Downloader.search(cfg, query)
  local r, err = httpGet(Downloader.searchUrl(cfg, query), nil, false, cfg.http_retries)
  if not r then return nil, "Echec de la recherche: " .. tostring(err) end
  local body = r.readAll()
  r.close()
  local ok, parsed = pcall(textutils.unserialiseJSON, body)
  if not ok or type(parsed) ~= "table" then
    return nil, "Reponse de recherche invalide (JSON illisible)"
  end
  return parsed
end

-- ── Flux de téléchargement (lecture par chunks) ──────────────────────────────
local Stream = {}
Stream.__index = Stream
Downloader.Stream = Stream

--- Ouvre un flux binaire pour un id.
-- @return Stream|nil stream, string|nil err
function Downloader.openStream(cfg, id)
  local h, err = httpGet(Downloader.downloadUrl(cfg, id), nil, true, cfg.http_retries) -- binary
  if not h then return nil, "Echec du telechargement: " .. tostring(err) end
  local chunkBytes = (cfg.chunk_size_kb or 16) * 1024
  return setmetatable({
    handle = h,
    chunkBytes = chunkBytes,
    header = h.read(4), -- 4 premiers octets, recollés au 1er chunk (cf. terreng)
    first = true,
  }, Stream)
end

--- Lit le prochain chunk DFPWM brut (string), ou nil en fin de flux.
function Stream:read()
  if not self.handle then return nil end
  local n = self.first and (self.chunkBytes - 4) or self.chunkBytes
  local chunk = self.handle.read(n)
  if not chunk then self:close(); return nil end
  if self.first then
    chunk = (self.header or "") .. chunk
    self.first = false
  end
  return chunk
end

function Stream:close()
  if self.handle then
    self.handle.close()
    self.handle = nil
  end
end

return Downloader

end
preload["core.audio"] = function(...)
--[[ CC_RSMP - core/audio.lua
  Moteur audio : décodage DFPWM, playback multi-speakers avec backpressure, volume.
  Le décodage et le playback sont séparés du réseau pour pouvoir, en S3, broadcaster
  les chunks DFPWM bruts et ne décoder que côté lecture.
]]
local dfpwm = require("cc.audio.dfpwm")

local Audio = {}
Audio.__index = Audio

Audio.SAMPLE_RATE = 48000 -- Hz : débit de lecture du speaker CC:T

--- @param opts table { speakers = {...}, volume = 1.0 }
function Audio.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Audio)
  self.decoder  = dfpwm.make_decoder()
  self.speakers = opts.speakers or { peripheral.find("speaker") }
  self.volume   = math.max(0, math.min(3, opts.volume or 1.0))
  return self
end

function Audio:hasOutput()
  return #self.speakers > 0
end

function Audio:setVolume(v)
  self.volume = math.max(0, math.min(3, v))
  return self.volume
end

--- Décode un chunk DFPWM brut -> table PCM (amplitudes [-128,127]).
function Audio:decode(chunk)
  return self.decoder(chunk)
end

--- Joue un buffer PCM décodé sur TOUS les speakers, avec backpressure.
-- Interruptible : Audio:stop() envoie "rsmp_audio_abort" pour débloquer l'attente
-- (speaker.stop() n'émet pas "speaker_audio_empty", ce qui bloquait pause/skip).
function Audio:playPCM(pcm)
  self.playing = true
  for _, spk in ipairs(self.speakers) do
    while self.playing do
      if spk.playAudio(pcm, self.volume) then break end
      -- buffer plein : attendre qu'il se libère, ou un abandon (pause/skip/stop)
      local ev = os.pullEvent()
      if ev == "rsmp_audio_abort" then self.playing = false end
    end
    if not self.playing then break end
  end
end

--- Décode puis joue un chunk DFPWM brut.
function Audio:playChunk(chunk)
  self:playPCM(self:decode(chunk))
end

--- Joue l'intégralité d'un flux (objet exposant :read() -> chunk|nil).
-- @param onChunk function|nil  appelée après chaque chunk avec le nb total de samples joués
function Audio:streamPlay(stream, onChunk)
  local samples = 0
  while true do
    local chunk = stream:read()
    if not chunk then break end
    local pcm = self:decode(chunk)
    samples = samples + #pcm
    self:playPCM(pcm)
    if onChunk then onChunk(samples) end
  end
  return samples
end

--- Arrête immédiatement tous les speakers (flush des buffers) et débloque playPCM.
function Audio:stop()
  self.playing = false
  for _, spk in ipairs(self.speakers) do pcall(spk.stop) end
  os.queueEvent("rsmp_audio_abort")
end

--- Convertit un nombre de samples en secondes.
function Audio.samplesToSeconds(n)
  return n / Audio.SAMPLE_RATE
end

return Audio

end
preload["core.playlist"] = function(...)
--[[ CC_RSMP - core/playlist.lua
  Gestion de la file de lecture : queue, historique, shuffle, loop (off/one/all).
  Logique pure (aucune E/S audio/réseau) -> entièrement testable hors-jeu.
  La file est volatile (propre à chaque session) : aucune persistance disque.
  Les préférences loop/shuffle sont gérées hors de la file (config.json).
]]
local Playlist = {}
Playlist.__index = Playlist

--- @param opts table { loop, shuffle, maxQueue, maxHistory }
function Playlist.new(opts)
  opts = opts or {}
  return setmetatable({
    queue      = {},                       -- chansons à venir [{id,name,artist,...}]
    history    = {},                       -- jouées, plus récente en tête
    current    = nil,                      -- chanson en cours
    loop       = opts.loop or "off",       -- "off" | "one" | "all"
    shuffle    = opts.shuffle or false,
    maxQueue   = opts.maxQueue or 50,
    maxHistory = opts.maxHistory or 10,
  }, Playlist)
end

--- Ajoute une chanson (en fin, ou en tête si atFront).
-- @return boolean ok, string|nil err
function Playlist:add(song, atFront)
  if #self.queue >= self.maxQueue then return false, "Queue pleine (" .. self.maxQueue .. ")" end
  if atFront then
    table.insert(self.queue, 1, song)
  else
    self.queue[#self.queue + 1] = song
  end
  return true
end

function Playlist:clear()
  self.queue = {}
end

function Playlist:size()
  return #self.queue
end

--- Renvoie jusqu'à n chansons à venir (sans les retirer).
function Playlist:upcoming(n)
  local out = {}
  for i = 1, math.min(n or 3, #self.queue) do out[i] = self.queue[i] end
  return out
end

function Playlist:_pushHistory(song)
  if not song then return end
  table.insert(self.history, 1, song)
  while #self.history > self.maxHistory do table.remove(self.history) end
end

--- Avance vers la chanson suivante en respectant loop/shuffle.
-- Met à jour current et history. @return table|nil song
function Playlist:advance()
  local prev = self.current

  if self.loop == "one" and prev then
    return prev -- rejoue la même; current/history inchangés
  end

  if prev then self:_pushHistory(prev) end

  local nextSong
  if #self.queue > 0 then
    if self.shuffle then
      nextSong = table.remove(self.queue, math.random(1, #self.queue))
    else
      nextSong = table.remove(self.queue, 1)
    end
  elseif self.loop == "all" and #self.history > 0 then
    -- Reconstruire la queue depuis l'historique, dans l'ordre de lecture d'origine.
    local restored = {}
    for i = #self.history, 1, -1 do restored[#restored + 1] = self.history[i] end
    self.queue = restored
    self.history = {}
    if self.shuffle then
      nextSong = table.remove(self.queue, math.random(1, #self.queue))
    else
      nextSong = table.remove(self.queue, 1)
    end
  end

  self.current = nextSong
  return nextSong
end

--- Revient à la chanson précédente (depuis l'historique).
-- @return table|nil song
function Playlist:goPrev()
  if #self.history == 0 then return nil end
  local prevSong = table.remove(self.history, 1)
  if self.current then table.insert(self.queue, 1, self.current) end
  self.current = prevSong
  return prevSong
end

--- Fait défiler le mode loop : off -> all -> one -> off.
function Playlist:cycleLoop()
  self.loop = ({ off = "all", all = "one", one = "off" })[self.loop] or "off"
  return self.loop
end

function Playlist:toggleShuffle()
  self.shuffle = not self.shuffle
  return self.shuffle
end

return Playlist

end
preload["core.player"] = function(...)
--[[ CC_RSMP - core/player.lua
  Lecteur local (mode standalone). Le moteur (boucle audio + dispatch) est piloté par
  l'interface unifiée (ui/app.lua) sur le terminal, et par le compagnon monitor.
]]
local Downloader = require("core.downloader")
local Audio      = require("core.audio")
local Config     = require("lib.config")
local CLI        = require("ui.cli") -- parseDuration
local App        = require("ui.app")
local GUI        = require("ui.gui")

local Player = {}

-- Résout une chanson via recherche interactive ou id/URL YouTube direct (utilisé au préchargement).
function Player.resolveSong(cfg, query, youtube)
  if youtube then
    local Utils = require("lib.utils")
    local id = Utils.extractYtId(youtube)
    if not id then print("URL/ID YouTube invalide."); return nil end
    return { id = id, name = "(YouTube " .. id .. ")", artist = "" }
  end
  if not query then return nil end
  print("Recherche: " .. query .. " ...")
  local results, err = Downloader.search(cfg, query)
  if not results then print(err or "Echec recherche"); return nil end
  for _, it in ipairs(results) do
    if type(it.artist) == "string" and it.artist:match("%d+:%d+") then
      if it.type == "playlist" and it.playlist_items then return it.playlist_items[1] end
      return it
    end
  end
  return results[1]
end

function Player.runLocal(cfg, playlist)
  local audio = Audio.new({ speakers = { peripheral.find("speaker") }, volume = cfg.local_volume })
  if not audio:hasOutput() then
    printError("Aucun speaker detecte : lecture locale impossible.")
    return
  end
  math.randomseed(os.epoch("utc"))

  local ctrl = { exit = false, paused = false, skip = false, prevReq = false }
  local view = { song = nil, elapsed = 0, duration = nil, state = "stopped" }

  local function audioLoop()
    while not ctrl.exit do
      local song
      if ctrl.prevReq then
        ctrl.prevReq = false
        song = playlist:goPrev() or playlist:advance()
      else
        song = playlist:advance()
      end
      if not song then
        view.song, view.state, view.elapsed = nil, "stopped", 0
        os.pullEvent()
      else
        view.song, view.duration, view.elapsed, view.state =
          song, CLI.parseDuration(song.artist), 0, "playing"
        local stream, err = Downloader.openStream(cfg, song.id)
        if not stream then
          printError(err)
        else
          ctrl.skip = false
          local samples = 0
          while not ctrl.exit and not ctrl.skip do
            while ctrl.paused and not ctrl.exit and not ctrl.skip do
              view.state = "paused"; os.pullEvent("rsmp_resume")
            end
            if ctrl.exit or ctrl.skip then break end
            view.state = "playing"
            local chunk = stream:read()
            if not chunk then break end
            local pcm = audio:decode(chunk)
            samples = samples + #pcm
            audio:playPCM(pcm)
            view.elapsed = Audio.samplesToSeconds(samples)
          end
          stream:close()
        end
      end
    end
  end

  local function dispatch(action, args)
    args = args or {}
    if action == "exit" then
      ctrl.exit = true; audio:stop(); os.queueEvent("rsmp_resume"); return true
    elseif action == "playpause" then
      ctrl.paused = not ctrl.paused
      if ctrl.paused then audio:stop() else os.queueEvent("rsmp_resume") end
    elseif action == "skip" then
      ctrl.skip = true; audio:stop(); os.queueEvent("rsmp_resume")
    elseif action == "prev" then
      ctrl.prevReq = true; ctrl.skip = true; audio:stop(); os.queueEvent("rsmp_resume")
    elseif action == "volup" then audio:setVolume(audio.volume + 0.1)
    elseif action == "voldown" then audio:setVolume(audio.volume - 0.1)
    elseif action == "loop" then cfg.loop = playlist:cycleLoop(); Config.save(cfg)
    elseif action == "shuffle" then cfg.shuffle = playlist:toggleShuffle(); Config.save(cfg)
    elseif action == "playnow" and args.song then
      playlist:add(args.song, true)
      ctrl.skip = true; audio:stop(); os.queueEvent("rsmp_resume"); os.queueEvent("queue_updated")
    elseif action == "playnext" and args.song then
      playlist:add(args.song, true); os.queueEvent("queue_updated")
    elseif action == "enqueue" and args.song then
      playlist:add(args.song); os.queueEvent("queue_updated")
    elseif action == "remove" and args.index then
      table.remove(playlist.queue, args.index)
    end
    return false
  end

  local ctx = {
    mode = "local", cfg = cfg,
    np = function()
      return {
        name = view.song and view.song.name or "---",
        artist = view.song and view.song.artist or "",
        elapsed = view.elapsed, duration = view.duration,
        state = view.state, volume = audio.volume,
      }
    end,
    queueList = function()
      local q = {}
      for i, s in ipairs(playlist.queue) do q[i] = { name = s.name, artist = s.artist } end
      return q
    end,
    dispatch = dispatch,
  }

  local guiMon = select(1, GUI.detect(cfg))
  local tasks = { audioLoop, function() App.run(ctx) end }
  if guiMon then tasks[#tasks + 1] = function() App.monitor(ctx, guiMon) end end
  parallel.waitForAny(table.unpack(tasks))

  audio:stop()
  App.cleanup(guiMon)
  print("Lecture terminee.")
end

return Player

end
preload["core.network"] = function(...)
--[[ CC_RSMP - core/network.lua
  Couche réseau rednet : noms de protocoles, encodage du payload audio, transport.
  Protocoles (préfixe configurable, défaut CC_RSMP) :
    *_AUDIO  broadcaster -> clients : chunks DFPWM (raw/base64)
    *_META   broadcaster -> clients : métadonnées
    *_CMD    client -> broadcaster  : commandes
    *_ACK    broadcaster -> client  : accusés
    *_DISCO  découverte / heartbeat (announce + join)
]]
local base64 = require("lib.base64")

local Network = {}
Network.__index = Network

local function proto(cfg, suffix)
  return (cfg.rednet_protocol_prefix or "CC_RSMP") .. "_" .. suffix
end
Network.proto = proto

--- Encode un chunk DFPWM brut selon cfg.audio_encoding ("base64" | "raw").
-- @return string data, string encoding
function Network.encodeChunk(cfg, raw)
  if cfg.audio_encoding == "base64" then
    return base64.encode(raw), "base64"
  end
  return raw, "raw"
end

--- Décode un chunk reçu selon son encoding annoncé.
function Network.decodeChunk(encoding, data)
  if encoding == "base64" then return base64.decode(data) end
  return data
end

function Network.new(cfg, modemName)
  local self = setmetatable({ cfg = cfg, modemName = modemName }, Network)
  self.P = {
    AUDIO = proto(cfg, "AUDIO"),
    META  = proto(cfg, "META"),
    CMD   = proto(cfg, "CMD"),
    ACK   = proto(cfg, "ACK"),
    DISCO = proto(cfg, "DISCO"),
  }
  return self
end

--- Ouvre rednet sur le modem (détecté si non fourni).
-- @return boolean ok, string|nil err
function Network:open()
  if not self.modemName then
    local m = peripheral.find("modem")
    if not m then return false, "Aucun modem detecte." end
    self.modemName = peripheral.getName(m)
  end
  rednet.open(self.modemName)
  return true
end

function Network:close()
  if self.modemName and rednet.isOpen(self.modemName) then
    rednet.close(self.modemName)
  end
end

-- ── Émission ─────────────────────────────────────────────────────────────────

function Network:broadcastAudio(seq, songId, encData, encoding, total, playAt)
  rednet.broadcast({
    type = "audio_chunk", seq = seq, song_id = songId,
    data = encData, encoding = encoding, total = total,
    play_at = playAt, -- epoch (ms) cible de lecture pour synchroniser les clients
  }, self.P.AUDIO)
end

function Network:broadcastStop(songId)
  rednet.broadcast({ type = "audio_stop", song_id = songId }, self.P.AUDIO)
end

function Network:broadcastMeta(meta)
  rednet.broadcast(meta, self.P.META)
end

function Network:announce(msg)
  rednet.broadcast(msg, self.P.DISCO)
end

function Network:join(broadcasterId, msg)
  if broadcasterId then
    rednet.send(broadcasterId, msg, self.P.DISCO)
  else
    rednet.broadcast(msg, self.P.DISCO)
  end
end

function Network:sendCmd(broadcasterId, msg)
  rednet.send(broadcasterId, msg, self.P.CMD)
end

function Network:sendAck(clientId, msg)
  rednet.send(clientId, msg, self.P.ACK)
end

-- ── Réception ────────────────────────────────────────────────────────────────

--- Reçoit n'importe quel message (tous protocoles). @return sender, msg, protocol
function Network:receiveAny(timeout)
  return rednet.receive(nil, timeout)
end

--- Reçoit sur un protocole donné (suffixe : "AUDIO"/"META"/...).
function Network:receive(suffix, timeout)
  return rednet.receive(self.P[suffix], timeout)
end

return Network

end
preload["core.broadcaster"] = function(...)
--[[ CC_RSMP - core/broadcaster.lua
  Mode broadcaster (serveur radio) : télécharge, décode, joue localement (optionnel),
  diffuse les chunks DFPWM aux clients, envoie les métadonnées, annonce sa présence
  et exécute les commandes reçues.

  Boucles concurrentes : parallel.waitForAny(audioLoop, networkLoop, metaLoop,
  discoveryLoop, uiLoop). Un état partagé `state` + des flags `ctrl` synchronisent
  les commandes locales (clavier) et distantes (rednet) via un handler unique.
]]
local Downloader = require("core.downloader")
local Audio      = require("core.audio")
local Playlist   = require("core.playlist")
local Config     = require("lib.config")
local Network    = require("core.network")
local CLI        = require("ui.cli") -- parseDuration
local GUI        = require("ui.gui")
local App        = require("ui.app")
local Utils      = require("lib.utils")

local Broadcaster = {}

local function nowSec()
  return os.epoch("utc") / 1000
end

-- Résout une chanson sans interaction (auto-sélection du 1er vrai titre).
function Broadcaster.resolveSong(cfg, query, youtube)
  if youtube then
    local id = Utils.extractYtId(youtube)
    if not id then return nil end
    return { id = id, name = "(YouTube " .. id .. ")", artist = "" }
  end
  if not query then return nil end
  local results = Downloader.search(cfg, query)
  if not results then return nil end
  for _, it in ipairs(results) do
    if type(it.artist) == "string" and it.artist:match("%d+:%d+") then
      if it.type == "playlist" and it.playlist_items then return it.playlist_items[1] end
      return it
    end
  end
  return results[1]
end

-- Scanne le réseau pour collecter les noms de stations déjà actives.
-- Envoie une requête "who" ; les broadcasters répondent par une annonce immédiate.
-- @return table { [label_minuscule] = true }
function Broadcaster.scanNames(net, seconds)
  net:announce({ type = "who" })
  local taken = {}
  local deadline = os.epoch("utc") + (seconds or 1.5) * 1000
  while true do
    local left = (deadline - os.epoch("utc")) / 1000
    if left <= 0 then break end
    local sender, msg, proto = net:receiveAny(left)
    if not sender then break end
    if proto == net.P.DISCO and type(msg) == "table" and msg.type == "announce"
        and type(msg.label) == "string" then
      taken[msg.label:lower()] = true
    end
  end
  return taken
end

-- Valide un nom de station (logique pure, testable).
-- @return ok:boolean, reason:nil|"empty"|"taken", cleaned:string
function Broadcaster.validateName(name, taken)
  local clean = Utils.trim(type(name) == "string" and name or "") or ""
  if clean == "" then return false, "empty", clean end
  if taken and taken[clean:lower()] then return false, "taken", clean end
  return true, nil, clean
end

-- Demande un nom de station : non vide et non déjà utilisé sur le réseau.
local function resolveStationName(net, candidate)
  local taken = Broadcaster.scanNames(net, 1.5)
  local name = (type(candidate) == "string") and candidate or nil
  while true do
    if not name or Utils.trim(name) == "" then
      term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
      term.clear(); term.setCursorPos(1, 1)
      print("== CC_Radio - Nouvelle station ==")
      print("")
      write("Nom de la station : ")
      name = read()
    end
    local ok, reason, clean = Broadcaster.validateName(name, taken)
    if ok then
      return clean
    elseif reason == "empty" then
      printError("Le nom ne peut pas etre vide.")
    else
      printError("Nom deja utilise par une autre station. Choisissez-en un autre.")
    end
    name = nil
  end
end

function Broadcaster.run(cfg, parsed)
  local net = Network.new(cfg)
  local ok, err = net:open()
  if not ok then printError(err); return end

  local audio = Audio.new({ speakers = { peripheral.find("speaker") }, volume = cfg.default_volume })
  local localPlay = audio:hasOutput() and not (parsed and parsed.flags["no-speaker"])
  math.randomseed(os.epoch("utc"))

  -- GUI monitor compagnon (auto si présent ; --gui force, erreur si absent).
  local guiMon
  do
    local mon, err = GUI.detect(cfg)
    if mon then
      guiMon = mon
    elseif parsed and parsed.flags.gui then
      printError("Option --gui: " .. tostring(err))
      net:close(); return
    end
  end

  local playlist = Playlist.new({ -- file volatile (vidée à chaque session)
    loop = cfg.loop, shuffle = cfg.shuffle,
    maxQueue = cfg.max_queue_size, maxHistory = cfg.history_size,
  })

  -- Nom de station obligatoire (non vide) et unique sur le réseau.
  print("Recherche des stations existantes...")
  local stationName = resolveStationName(net, parsed and parsed.flags.label)

  local state = {
    label = stationName,
    id = os.getComputerID(),
    clients = {},          -- [id] = { label, last_seen }
    song = nil, duration = nil, elapsed = 0, seq = 0,
    playbackState = "stopped",
  }
  local ctrl = { exit = false, paused = false, skip = false, prevReq = false }

  -- Chanson immédiate via arguments.
  if parsed then
    local q = parsed.flags.query or parsed.positional[2]
    if q or parsed.flags.youtube then
      local song = Broadcaster.resolveSong(cfg, q, parsed.flags.youtube)
      if song then playlist:add(song, true) end
    end
  end

  local function clientCount()
    local n = 0
    for _ in pairs(state.clients) do n = n + 1 end
    return n
  end

  local function buildMeta()
    local up = {}
    for i, s in ipairs(playlist.queue) do up[i] = { id = s.id, title = s.name } end -- file complète (synchro client)
    return {
      type = "meta", broadcaster_id = state.id, label = state.label,
      song_id  = state.song and state.song.id,
      title    = state.song and (Utils.trim(state.song.name) or "---") or "---",
      author   = state.song and (Utils.trim(state.song.artist) or "") or "---",
      duration = state.duration or 0,
      position = math.floor(state.elapsed),
      chunk_seq = state.seq,
      volume   = audio.volume,
      state    = state.playbackState,
      playlist = up,
      loop     = playlist.loop,
      shuffle  = playlist.shuffle,
    }
  end

  -- Handler unique : commandes locales (clavier) et distantes (rednet).
  local function applyCommand(command, args, ackTo)
    args = args or {}
    if command == "pause" then
      ctrl.paused = true; audio:stop()
    elseif command == "resume" then
      ctrl.paused = false; os.queueEvent("rsmp_resume")
    elseif command == "skip" then
      ctrl.skip = true; audio:stop(); os.queueEvent("rsmp_resume")
    elseif command == "prev" then
      ctrl.prevReq = true; ctrl.skip = true; audio:stop(); os.queueEvent("rsmp_resume")
    elseif command == "stop" then
      ctrl.skip = true; playlist:clear(); audio:stop(); os.queueEvent("rsmp_resume")
    elseif command == "volume" then
      if args.level then audio:setVolume(tonumber(args.level) or audio.volume) end
    elseif command == "loop" then
      if args.mode == "off" or args.mode == "one" or args.mode == "all" then
        playlist.loop = args.mode; cfg.loop = args.mode; Config.save(cfg)
      end
    elseif command == "shuffle" then
      playlist.shuffle = args.enabled and true or false
      cfg.shuffle = playlist.shuffle; Config.save(cfg)
    elseif command == "play" or command == "queue" then
      local song = Broadcaster.resolveSong(cfg, args.query, args.url)
      if song then
        playlist:add(song, command == "play")
        os.queueEvent("queue_updated")
      end
    elseif command == "status" then
      net:broadcastMeta(buildMeta())
    end
    if ackTo then net:sendAck(ackTo, { type = "ack", command = command, ok = true }) end
  end

  -- ── Boucles ────────────────────────────────────────────────────────────────

  local function audioLoop()
    while not ctrl.exit do
      local song
      if ctrl.prevReq then
        ctrl.prevReq = false
        song = playlist:goPrev() or playlist:advance()
      else
        song = playlist:advance()
      end

      if not song then
        state.song, state.playbackState, state.elapsed = nil, "stopped", 0
        os.pullEvent() -- réveillé par queue_updated / commande / etc.
      else
        state.song      = song
        state.duration  = CLI.parseDuration(song.artist)
        state.elapsed   = 0
        state.seq       = 0
        state.playbackState = "playing"

        local stream, serr = Downloader.openStream(cfg, song.id)
        if not stream then
          printError(serr)
        else
          ctrl.skip = false
          local samples = 0
          while not ctrl.exit and not ctrl.skip do
            while ctrl.paused and not ctrl.exit and not ctrl.skip do
              state.playbackState = "paused"
              os.pullEvent("rsmp_resume")
            end
            if ctrl.exit or ctrl.skip then break end
            state.playbackState = "playing"

            local chunk = stream:read()
            if not chunk then break end
            state.seq = state.seq + 1

            local encData, encoding = Network.encodeChunk(cfg, chunk)
            -- instant de lecture commun à tous les clients (horloge serveur partagée)
            local playAt = os.epoch("utc") + (cfg.sync_lead_ms or 2000)
            net:broadcastAudio(state.seq, song.id, encData, encoding, nil, playAt)

            if localPlay then
              audio:playPCM(audio:decode(chunk)) -- backpressure -> cadence ~ temps réel
              samples = samples + #chunk * 8
            else
              -- pas de lecture locale : cadencer manuellement (~ durée du chunk)
              samples = samples + #chunk * 8
              os.sleep((#chunk * 8 / Audio.SAMPLE_RATE) * 0.9)
            end
            state.elapsed = Audio.samplesToSeconds(samples)
          end
          stream:close()
          net:broadcastStop(song.id)
        end
      end
    end
  end

  local function networkLoop()
    while not ctrl.exit do
      local sender, msg, mproto = net:receiveAny(1)
      if sender and type(msg) == "table" then
        if mproto == net.P.CMD and msg.type == "cmd" then
          applyCommand(msg.command, msg.args, msg.client_id or sender)
        elseif mproto == net.P.DISCO and msg.type == "join" then
          state.clients[sender] = { label = msg.label, last_seen = nowSec() }
        elseif mproto == net.P.DISCO and msg.type == "who" then
          -- une nouvelle station vérifie l'unicité des noms : on répond aussitôt.
          net:announce({
            type = "announce", broadcaster_id = state.id, label = state.label,
            state = state.playbackState, song_title = state.song and state.song.name,
          })
        end
      end
    end
  end

  local function metaLoop()
    while not ctrl.exit do
      net:broadcastMeta(buildMeta())
      os.sleep(cfg.meta_interval_sec or 5)
    end
  end

  local function discoveryLoop()
    while not ctrl.exit do
      net:announce({
        type = "announce", broadcaster_id = state.id, label = state.label,
        state = state.playbackState, song_title = state.song and state.song.name,
      })
      local cutoff = nowSec() - (cfg.discovery_interval_sec or 30) * 2
      for id, c in pairs(state.clients) do
        if c.last_seen < cutoff then state.clients[id] = nil end
      end
      os.sleep(cfg.discovery_interval_sec or 30)
    end
  end

  -- Dispatch unique : clavier/clic (App.run) et tactile (App.monitor).
  local function dispatch(action, args)
    args = args or {}
    if action == "exit" then
      ctrl.exit = true; audio:stop(); os.queueEvent("rsmp_resume"); return true
    elseif action == "playpause" then applyCommand(ctrl.paused and "resume" or "pause")
    elseif action == "skip" then applyCommand("skip")
    elseif action == "prev" then applyCommand("prev")
    elseif action == "stop" then applyCommand("stop")
    elseif action == "volup" then audio:setVolume(audio.volume + 0.1)
    elseif action == "voldown" then audio:setVolume(audio.volume - 0.1)
    elseif action == "loop" then cfg.loop = playlist:cycleLoop(); Config.save(cfg)
    elseif action == "shuffle" then cfg.shuffle = playlist:toggleShuffle(); Config.save(cfg)
    elseif action == "status" then applyCommand("status")
    elseif action == "playnow" and args.song then
      playlist:add(args.song, true); applyCommand("skip"); os.queueEvent("queue_updated")
    elseif action == "playnext" and args.song then
      playlist:add(args.song, true); os.queueEvent("queue_updated")
    elseif action == "enqueue" and args.song then
      playlist:add(args.song); os.queueEvent("queue_updated")
    elseif action == "remove" and args.index then
      table.remove(playlist.queue, args.index)
    end
    return false
  end

  local ctx = {
    mode = "broadcaster", cfg = cfg,
    np = function()
      return {
        name = state.song and state.song.name or "---",
        artist = state.song and state.song.artist or "",
        elapsed = state.elapsed, duration = state.duration,
        state = state.playbackState, volume = audio.volume,
        clients = clientCount(), label = state.label,
      }
    end,
    queueList = function()
      local q = {}
      for i, s in ipairs(playlist.queue) do q[i] = { name = s.name, artist = s.artist } end
      return q
    end,
    dispatch = dispatch,
  }

  -- Annonce immédiate puis lancement des boucles.
  net:announce({
    type = "announce", broadcaster_id = state.id, label = state.label,
    state = state.playbackState, song_title = state.song and state.song.name,
  })

  local tasks = { audioLoop, networkLoop, metaLoop, discoveryLoop, function() App.run(ctx) end }
  if guiMon then tasks[#tasks + 1] = function() App.monitor(ctx, guiMon) end end
  parallel.waitForAny(table.unpack(tasks))

  net:broadcastStop(state.song and state.song.id)
  audio:stop()
  net:close()
  App.cleanup(guiMon)
  print("Broadcaster arrete.")
end

return Broadcaster

end
preload["core.client"] = function(...)
--[[ CC_RSMP - core/client.lua
  Mode client (récepteur) : se connecte à un broadcaster, reçoit les chunks DFPWM,
  les décode et les joue sur le speaker local (volume local indépendant), affiche les
  métadonnées, détecte les paquets manquants et la perte de signal.

  Boucles : parallel.waitForAny(netLoop, playLoop, uiLoop).
  - netLoop  : reçoit AUDIO/META, décode -> buffer PCM, gère perte/redécouverte.
  - playLoop : joue le buffer PCM (backpressure speaker).
  - uiLoop   : affichage + clavier (volume local, volume global, status, déconnexion).
]]
local Audio     = require("core.audio")
local Network   = require("core.network")
local Discovery = require("lib.discovery")
local GUI       = require("ui.gui")
local App       = require("ui.app")

local Client = {}

-- Délai de retard (ms) au-delà duquel un chunk est abandonné pour rester synchrone.
local DROP_LATE_MS = 2000

--- Décide quoi faire d'un chunk dont la lecture est prévue à `play_at` (epoch ms).
-- @return "drop" si trop en retard, sinon un nombre de ms à attendre (>= 0).
function Client.schedule(play_at, now)
  if not play_at then return 0 end
  local wait = play_at - now
  if wait > 0 then return wait end
  if wait < -DROP_LATE_MS then return "drop" end
  return 0
end

--- Traite un message reçu (extrait pour être testable). Mute `ctx`.
-- ctx = { net, audio, buffer, view, cfg, lastSeq, curSong, targetId }
function Client.handle(ctx, sender, msg, proto)
  local net, view = ctx.net, ctx.view
  if proto == net.P.AUDIO then
    if msg.type == "audio_chunk" then
      view.signal = "connected"
      if msg.song_id ~= ctx.curSong then
        ctx.curSong = msg.song_id
        ctx.lastSeq = 0
      end
      if msg.seq and ctx.lastSeq > 0 and msg.seq > ctx.lastSeq + 1 then
        view.lost = view.lost + (msg.seq - ctx.lastSeq - 1)
      end
      if msg.seq then ctx.lastSeq = msg.seq end
      local rawDfpwm = Network.decodeChunk(msg.encoding, msg.data)
      ctx.buffer[#ctx.buffer + 1] = { pcm = ctx.audio:decode(rawDfpwm), play_at = msg.play_at }
      os.queueEvent("rsmp_chunk")
    elseif msg.type == "audio_stop" then
      view.state = "stopped"
    end
  elseif proto == net.P.META and msg.type == "meta" then
    view.signal     = "connected" -- la META prouve que la station répond (même en pause)
    view.title      = msg.title or view.title
    view.author     = msg.author or view.author
    view.duration   = msg.duration or 0
    view.position   = msg.position or 0
    view.state      = msg.state or view.state
    view.label      = msg.label or view.label
    view.playlist   = msg.playlist or view.playlist
    view.broadcaster = msg.broadcaster_id or view.broadcaster
    if not ctx.targetId then ctx.targetId = view.broadcaster end
  end
end

function Client.run(cfg, parsed)
  local net = Network.new(cfg)
  local ok, err = net:open()
  if not ok then printError(err); return end

  local audio = Audio.new({ speakers = { peripheral.find("speaker") }, volume = cfg.local_volume })
  if not audio:hasOutput() then
    printError("Aucun speaker detecte (obligatoire en mode client).")
    net:close(); return
  end
  if parsed and parsed.flags.volume then
    audio:setVolume(tonumber(parsed.flags.volume) or cfg.local_volume)
  end

  -- GUI monitor compagnon (auto si présent ; --gui force).
  local guiMon
  do
    local mon, err = GUI.detect(cfg)
    if mon then
      guiMon = mon
    elseif parsed and parsed.flags.gui then
      printError("Option --gui: " .. tostring(err))
      net:close(); return
    end
  end

  local ctx = {
    net = net, audio = audio, cfg = cfg, buffer = {},
    lastSeq = 0, curSong = nil,
    targetId = parsed and tonumber(parsed.flags.id) or nil,
    view = {
      broadcaster = nil, label = nil, title = "---", author = "---",
      duration = 0, position = 0, state = "...", signal = "searching",
      volume = audio.volume, lost = 0,
    },
  }
  local view = ctx.view
  local ctrl = { exit = false }

  -- Découverte initiale : lister les stations et laisser l'utilisateur choisir.
  if not ctx.targetId then
    print("Recherche des stations...")
    local stations = Discovery.listBroadcasters(net, 2)
    if #stations == 0 then
      App.cleanup()
      printError("Aucune station radio trouvee.")
      print("Verifiez qu'un broadcaster est actif sur le reseau (modem/HTTP).")
      net:close(); return
    end
    local chosen = App.pickStation(stations)
    if not chosen then net:close(); return end
    ctx.targetId = chosen.id; view.label = chosen.label
  end
  view.broadcaster = ctx.targetId
  Discovery.join(net, ctx.targetId, cfg.station_label or "client")
  view.signal = "connected"

  local function netLoop()
    while not ctrl.exit do
      -- Timeout > intervalle META (5 s) pour ne pas passer "perdu" pendant une pause.
      local sender, msg, mproto = net:receiveAny(8)
      if sender and type(msg) == "table" then
        Client.handle(ctx, sender, msg, mproto)
      elseif not sender then
        -- Aucun message depuis 8 s : signal perdu. On NE bloque PAS en redécouverte
        -- (ça jetait les chunks audio au retour). META/annonce nous reconnecteront.
        view.signal = "lost"
        if not ctx.targetId then
          local b = Discovery.findBroadcaster(net, 3)
          if b then
            ctx.targetId = b.id; view.broadcaster = b.id; view.label = b.label
            Discovery.join(net, ctx.targetId, cfg.station_label or "client")
            view.signal = "connected"
          end
        end
      end
    end
  end

  local function playLoop()
    while not ctrl.exit do
      if #ctx.buffer > 0 then
        local item = table.remove(ctx.buffer, 1)
        local sched = Client.schedule(item.play_at, os.epoch("utc"))
        if sched == "drop" then
          item = nil -- trop en retard : on saute pour rester synchrone
        elseif type(sched) == "number" and sched > 0 then
          os.sleep(sched / 1000) -- attendre l'instant de lecture commun
        end
        if not ctrl.exit and item then audio:playPCM(item.pcm) end
      else
        os.pullEvent("rsmp_chunk")
        if ctrl.exit then return end
      end
    end
  end

  -- Envoie une commande au broadcaster (avec un id direct comme une URL/ID YouTube).
  local function sendCmd(command, args)
    if ctx.targetId then
      net:sendCmd(ctx.targetId, { type = "cmd", command = command, args = args or {},
        client_id = os.getComputerID() })
    end
  end

  -- Dispatch : clavier/clic (App.run) et tactile (App.monitor).
  local function dispatch(action, args)
    args = args or {}
    if action == "exit" or action == "disconnect" then
      ctrl.exit = true; audio:stop(); os.queueEvent("rsmp_chunk"); return true
    elseif action == "volup" then audio:setVolume(audio.volume + 0.1)
    elseif action == "voldown" then audio:setVolume(audio.volume - 0.1)
    -- Les actions de contenu sont relayées au broadcaster (id passé comme "url").
    elseif (action == "playnow" or action == "playnext") and args.song then
      sendCmd("play", { url = args.song.id })
    elseif action == "enqueue" and args.song then
      sendCmd("queue", { url = args.song.id })
    end
    return false
  end

  ctx.mode = "client"
  ctx.dispatch = dispatch
  ctx.np = function()
    return {
      name = view.title, artist = view.author,
      elapsed = view.position, duration = view.duration,
      state = view.state, volume = audio.volume,
      signal = view.signal, label = view.label,
    }
  end
  ctx.queueList = function()
    local q = {}
    for i, s in ipairs(view.playlist or {}) do q[i] = { name = s.title, artist = "" } end
    return q
  end

  local tasks = { netLoop, playLoop, function() App.run(ctx) end }
  if guiMon then tasks[#tasks + 1] = function() App.monitor(ctx, guiMon) end end
  parallel.waitForAny(table.unpack(tasks))

  audio:stop()
  net:close()
  App.cleanup(guiMon)
  print("Client deconnecte.")
end

return Client

end
preload["ui.widgets"] = function(...)
--[[ CC_RSMP - ui/widgets.lua
  Composants UI réutilisables pour le rendu sur monitor (ou tout objet term-like).
  Le hit-testing est pur (testable hors-jeu) ; le rendu écrit sur la cible fournie.
]]
local Widgets = {}

--- Teste si (x,y) tombe dans un bouton. @return table|nil le bouton touché.
function Widgets.hitTest(buttons, x, y)
  for _, b in ipairs(buttons) do
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
      return b
    end
  end
  return nil
end

--- Dessine du texte à une position.
function Widgets.text(t, x, y, str, fg, bg)
  if bg then t.setBackgroundColor(bg) end
  if fg then t.setTextColor(fg) end
  t.setCursorPos(x, y)
  t.write(str)
end

--- Dessine un bouton rectangulaire avec label centré.
function Widgets.drawButton(t, btn, active)
  t.setBackgroundColor(active and (btn.activeBg or colors.green) or (btn.bg or colors.gray))
  t.setTextColor(btn.fg or colors.white)
  for dy = 0, btn.h - 1 do
    t.setCursorPos(btn.x, btn.y + dy)
    t.write(string.rep(" ", btn.w))
  end
  local lx = btn.x + math.max(0, math.floor((btn.w - #btn.label) / 2))
  local ly = btn.y + math.floor((btn.h - 1) / 2)
  t.setCursorPos(lx, ly)
  t.write(btn.label)
  t.setBackgroundColor(colors.black)
end

--- Dessine une barre horizontale remplie à `frac` (0..1).
function Widgets.hbar(t, x, y, w, frac, fillColor, emptyColor)
  frac = math.max(0, math.min(1, frac or 0))
  local n = math.floor(frac * w + 0.5)
  t.setCursorPos(x, y)
  t.setBackgroundColor(fillColor or colors.lime)
  t.write(string.rep(" ", n))
  t.setBackgroundColor(emptyColor or colors.gray)
  t.write(string.rep(" ", w - n))
  t.setBackgroundColor(colors.black)
end

--- Construit une rangée de boutons répartis sur la largeur `w`.
-- @param items liste de { id, label, bg? }
-- @return table de boutons { id, label, x, y, w, h, bg }
function Widgets.buttonRow(items, w, y, h, gap)
  gap = gap or 1
  local nn = #items
  local bw = math.max(3, math.floor((w - (nn + 1) * gap) / nn))
  local btns, x = {}, gap + 1
  for i, it in ipairs(items) do
    btns[i] = { id = it.id, label = it.label, x = x, y = y, w = bw, h = h, bg = it.bg }
    x = x + bw + gap
  end
  return btns
end

return Widgets

end
preload["ui.gui"] = function(...)
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
  { id = "disconnect", label = "DISC" },
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

end
preload["ui.cli"] = function(...)
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

--- Écran du lecteur interactif (S2).
-- @param view table { song, elapsed, duration, volume, state="playing|paused|stopped" }
-- @param playlist Playlist
function CLI.drawPlayer(view, playlist)
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)

  -- En-tête + modes
  color(colors.yellow); term.write("== CC_Radio - Lecteur local ==")
  local modes = {}
  if playlist.loop ~= "off" then modes[#modes + 1] = "LOOP:" .. playlist.loop end
  if playlist.shuffle then modes[#modes + 1] = "SHUFFLE" end
  if #modes > 0 then color(colors.lime); term.write("  [" .. table.concat(modes, " ") .. "]") end
  color(colors.white); print(""); print("")

  if view.song then
    print(Utils.trim(view.song.name) or "?")
    color(colors.lightGray); print(Utils.trim(view.song.artist) or ""); color(colors.white)
  else
    color(colors.lightGray); print("(rien en lecture)"); color(colors.white)
    print("")
  end
  print("")

  local dur  = view.duration
  local frac = (dur and dur > 0) and (view.elapsed / dur) or 0
  local tline = Utils.formatTime(view.elapsed) .. (dur and (" / " .. Utils.formatTime(dur)) or "")
  local tag = (view.state == "paused") and " [PAUSE]" or ""
  print("[" .. CLI.bar(frac, 22) .. "] " .. tline .. tag)
  print("")
  print("Vol: [" .. CLI.bar((view.volume or 0) / 3, 10, "#") .. "] "
    .. string.format("%.1f", view.volume or 0))
  print("")

  local up = playlist:upcoming(3)
  color(colors.cyan); print("Queue (" .. playlist:size() .. "):"); color(colors.white)
  if #up == 0 then
    color(colors.lightGray); print("  (vide)"); color(colors.white)
  else
    for i, s in ipairs(up) do print(string.format("  %d. %s", i, Utils.trim(s.name) or "?")) end
  end

  local _, h = term.getSize()
  term.setCursorPos(1, h)
  color(colors.gray)
  term.write("[P]ause [S]kip [B]prev [+/-]vol [L]oop [Z]shuf [Q]ueue [A]dd [X]exit")
  color(colors.white)
end

--- Affiche la queue complète (vue plein écran, attend une touche).
function CLI.showQueue(playlist)
  term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
  color(colors.yellow); print("== Queue (" .. playlist:size() .. ") =="); color(colors.white)
  if playlist:size() == 0 then
    color(colors.lightGray); print("(vide)"); color(colors.white)
  else
    for i, s in ipairs(playlist.queue) do
      print(string.format("%2d. %s", i, Utils.trim(s.name) or "?"))
      color(colors.lightGray); print("    " .. (Utils.trim(s.artist) or "")); color(colors.white)
    end
  end
  print("")
  color(colors.gray); print("Appuyez sur une touche..."); color(colors.white)
  os.pullEvent("char")
end

--- Écran du broadcaster (S3).
-- @param state { label, id, song, elapsed, duration, seq, playbackState }
function CLI.drawBroadcaster(state, playlist, audio, localPlay, nClients, encoding)
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)

  color(colors.yellow); term.write("== CC_Radio [BROADCASTER] ")
  if state.playbackState == "playing" then color(colors.red); term.write("* ON AIR")
  else color(colors.gray); term.write("o IDLE") end
  color(colors.white); print(""); print("")

  print('Station: "' .. (state.label or "?") .. '"   ID: ' .. tostring(state.id))
  print("")

  if state.song then
    print(Utils.trim(state.song.name) or "?")
    color(colors.lightGray); print(Utils.trim(state.song.artist) or ""); color(colors.white)
  else
    color(colors.lightGray); print("(rien en lecture)"); color(colors.white); print("")
  end
  print("")

  local dur  = state.duration
  local frac = (dur and dur > 0) and (state.elapsed / dur) or 0
  local tline = Utils.formatTime(state.elapsed) .. (dur and (" / " .. Utils.formatTime(dur)) or "")
  local tag = (state.playbackState == "paused") and " [PAUSE]" or ""
  print("[" .. CLI.bar(frac, 22) .. "] " .. tline .. tag)
  print("")

  print(("Vol: [%s] %.1f   Clients: %d   Local: %s")
    :format(CLI.bar(audio.volume / 3, 8, "#"), audio.volume, nClients or 0, localPlay and "on" or "off"))
  local modes = {}
  if playlist.loop ~= "off" then modes[#modes + 1] = "loop:" .. playlist.loop end
  if playlist.shuffle then modes[#modes + 1] = "shuffle" end
  print("Diffusion: " .. (encoding or "raw") .. (#modes > 0 and ("   [" .. table.concat(modes, " ") .. "]") or ""))
  print("")

  color(colors.cyan); print("Queue (" .. playlist:size() .. "):"); color(colors.white)
  local up = playlist:upcoming(3)
  if #up == 0 then color(colors.lightGray); print("  (vide)"); color(colors.white)
  else for i, s in ipairs(up) do print(string.format("  %d. %s", i, Utils.trim(s.name) or "?")) end end

  local _, h = term.getSize()
  term.setCursorPos(1, h)
  color(colors.gray)
  term.write("[P]ause [S]kip [B]prev [+/-]vol [L]oop [Z]shuf [Q]ueue [A]dd [X]exit")
  color(colors.white)
end

--- Écran du client (S4).
-- @param view { broadcaster, label, title, author, duration, position, state, signal, volume, lost }
function CLI.drawClient(view, audio)
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)

  color(colors.yellow); term.write("== CC_Radio [CLIENT] ")
  local sig = view.signal
  if sig == "connected" then color(colors.lime); term.write("* connecte")
  elseif sig == "lost" then color(colors.red); term.write("! signal perdu")
  else color(colors.gray); term.write("o recherche...") end
  color(colors.white); print(""); print("")

  local station = view.label or "?"
  print("Station: " .. station .. (view.broadcaster and ("  (ID " .. view.broadcaster .. ")") or ""))
  print("")
  print(Utils.trim(view.title) or "---")
  color(colors.lightGray); print(Utils.trim(view.author) or ""); color(colors.white)
  print("")

  local dur  = view.duration or 0
  local frac = (dur > 0) and ((view.position or 0) / dur) or 0
  local tline = Utils.formatTime(view.position or 0) .. (dur > 0 and (" / " .. Utils.formatTime(dur)) or "")
  local tag = (view.state == "paused") and " [PAUSE]" or (view.state == "stopped" and " [STOP]" or "")
  print("[" .. CLI.bar(frac, 22) .. "] " .. tline .. tag)
  print("")

  local vol = (audio and audio.volume) or view.volume or 0
  print("Vol local: [" .. CLI.bar(vol / 3, 10, "#") .. "] " .. string.format("%.1f", vol)
    .. (view.lost and view.lost > 0 and ("   Pertes: " .. view.lost) or ""))

  local _, h = term.getSize()
  term.setCursorPos(1, h)
  color(colors.gray)
  term.write("[+/-] vol local  [G] vol global  [S] status  [X] deconnexion")
  color(colors.white)
end

--- Affiche la queue sans attendre (pour la commande shell `queue --list`).
function CLI.printQueue(playlist)
  if playlist.loop ~= "off" or playlist.shuffle then
    local m = {}
    if playlist.loop ~= "off" then m[#m + 1] = "loop=" .. playlist.loop end
    if playlist.shuffle then m[#m + 1] = "shuffle=on" end
    print("Modes: " .. table.concat(m, " "))
  end
  print("Queue (" .. playlist:size() .. "):")
  if playlist:size() == 0 then
    print("  (vide)")
    return
  end
  for i, s in ipairs(playlist.queue) do
    print(string.format("%2d. %s", i, Utils.trim(s.name) or "?"))
  end
end

return CLI

end
preload["ui.help"] = function(...)
--[[ CC_RSMP - ui/help.lua
  Texte d'aide général et aide contextuelle par commande.
]]
local Help = {}

Help.USAGE = [[
CC_Radio - CC Radio System Music Player

USAGE:
  CC_Radio <commande> [options]

COMMANDES:
  broadcaster        Demarrer une station radio (serveur)
  client             Se connecter a une station (recepteur)
  play <query|url>   Ajouter et jouer une chanson
  status             Afficher l'etat du broadcaster
  stop               Arreter la lecture
  volume <0.0-3.0>   Regler le volume (--local/--global)
  skip               Morceau suivant
  pause / resume     Pause / reprise
  prev               Morceau precedent
  loop [off|one|all] Mode de repetition
  shuffle [on|off]   Lecture aleatoire
  config             Voir/modifier la config (--show/--set/--reset)
  install            Installer / mettre a jour (--update)
  help [commande]    Cette aide, ou l'aide d'une commande

EXEMPLES:
  CC_Radio broadcaster --label "Ma Radio"
  CC_Radio client --id 5
  CC_Radio play --query "lofi hip hop" --local
  CC_Radio volume 1.5 --global
  CC_Radio help broadcaster
]]

Help.COMMANDS = {
  broadcaster = [[
BROADCASTER - Demarrer une station radio

Lance le programme en mode serveur. Telecharge la musique via l'API
Firebase/Cloud Run de terreng et la broadcast aux clients connectes.
Le broadcaster peut fonctionner SANS speaker (--no-speaker).
Un modem (wireless ou wired) est obligatoire.

OPTIONS:
  --label <nom>   Nom de la station (defaut: config.station_label)
  --no-speaker    Broadcaster sans jouer localement
  --gui           Forcer l'interface graphique (monitor requis)
  --local         Jouer localement sans broadcast (standalone)

EXEMPLES:
  CC_Radio broadcaster
  CC_Radio broadcaster --label "Ma Radio Lofi"
  CC_Radio broadcaster --no-speaker --gui
]],

  client = [[
CLIENT - Se connecter a une station radio

Lance le programme en mode recepteur. Recoit le flux audio du
broadcaster et le joue sur le speaker local.
Un speaker ET un modem sont OBLIGATOIRES en mode client.
Sans --id, le programme auto-detecte les stations (discovery).

OPTIONS:
  --id <n>        ID du broadcaster cible (sinon auto-discover)
  --volume <f>    Volume local 0.0-3.0 (defaut: config.local_volume)
  --gui           Forcer l'interface graphique (monitor requis)

EXEMPLES:
  CC_Radio client
  CC_Radio client --id 5
  CC_Radio client --volume 2.0
]],

  play = [[
PLAY - Ajouter et jouer une chanson

Recherche par texte ou URL, puis lecture. En mode broadcaster, diffuse
aux clients ; avec --local, joue uniquement en local (standalone).

OPTIONS:
  --query <texte> Recherche par texte
  --youtube <url> URL YouTube directe (resolution a valider)
  --next          Ajouter en tete de queue
  --local         Lecture locale uniquement

EXEMPLES:
  CC_Radio play --query "lofi hip hop" --local
  CC_Radio play --youtube https://youtu.be/dQw4w9WgXcQ
]],

  config = [[
CONFIG - Configuration persistante (config.json)

OPTIONS:
  --show              Afficher la config (defaut)
  --set <cle> <val>   Modifier un parametre
  --reset             Remettre les valeurs par defaut

EXEMPLES:
  CC_Radio config --show
  CC_Radio config --set chunk_size_kb 8
  CC_Radio config --reset
]],
}

--- Affiche l'aide générale ou celle d'une commande (paginée : scrollable dans le shell).
function Help.show(cmd)
  local text = (cmd and Help.COMMANDS[cmd]) or Help.USAGE
  textutils.pagedPrint(text)
end

return Help

end
preload["ui.app"] = function(...)
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

function App.home(version)
  local btns = {}
  local function draw()
    clear()
    local w = select(1, term.getSize())
    local title = "CC_RADIO" .. (version and (" v" .. version) or "")
    term.setCursorPos(math.max(1, math.floor((w - #title) / 2)), 2)
    setColor(colors.yellow); term.write(title); setColor(colors.white)
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

--- Sélecteur de station (liste des broadcasters trouvés). @return station|nil
function App.pickStation(stations)
  local btns = {}
  local function draw()
    clear()
    local w = term.getSize()
    setColor(colors.yellow); term.setCursorPos(2, 1); term.write("CC_RADIO - Stations disponibles"); setColor(colors.white)
    btns = {}
    local y = 3
    for i, s in ipairs(stations) do
      local label = (" %d. %s"):format(i, s.label or ("Station " .. s.id))
      if s.song_title and s.song_title ~= "" then label = label .. "  (" .. s.song_title .. ")" end
      local b = { id = i, label = label:sub(1, w - 3), x = 2, y = y, w = w - 3, h = 1, bg = colors.blue }
      Widgets.drawButton(term, b, false)
      btns[#btns + 1] = b
      y = y + 2
      if y > select(2, term.getSize()) - 2 then break end
    end
    term.setCursorPos(2, select(2, term.getSize())); setColor(colors.gray)
    term.write("[numero/clic] choisir   [Q] annuler"); setColor(colors.white)
  end
  draw()
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "mouse_click" then
      local b = Widgets.hitTest(btns, ev[3], ev[4])
      if b then App.cleanup(); return stations[b.id] end
    elseif ev[1] == "char" then
      local c = ev[2]:lower()
      if c == "q" then App.cleanup(); return nil end
      local d = tonumber(c)
      if d and stations[d] then App.cleanup(); return stations[d] end
    elseif ev[1] == "term_resize" then
      draw()
    end
  end
end

-- ───────────────────────── Rendu des onglets ─────────────────────────

-- Onglets selon le mode : le client n'a PAS de recherche.
local function tabsFor(ctx)
  if ctx.mode == "client" then
    return { { id = "np", name = "Now Playing" }, { id = "queue", name = "Queue" } }
  end
  return { { id = "np", name = "Now Playing" }, { id = "search", name = "Search" },
    { id = "queue", name = "Queue" } }
end

-- Zones cliquables des onglets pour le mode courant.
local function tabRegions(ctx)
  local regions, x = {}, 1
  for i, t in ipairs(tabsFor(ctx)) do
    local label = " " .. t.name .. " "
    regions[i] = { i = i, x = x, w = #label, label = label }
    x = x + #label + 1
  end
  return regions
end

local function drawTabs(ctx, ui)
  term.setCursorPos(1, 1); term.setBackgroundColor(colors.gray); term.clearLine()
  for _, r in ipairs(tabRegions(ctx)) do
    term.setCursorPos(r.x, 1)
    if r.i == ui.tab then
      term.setBackgroundColor(colors.white); setColor(colors.black)
    else
      term.setBackgroundColor(colors.gray); setColor(colors.white)
    end
    term.write(r.label)
  end
  -- Nom de la station / station connectée, aligné à droite, à côté de "CC_Radio".
  local label = ctx.np().label
  if label and label ~= "" then
    local w = term.getSize()
    local txt = "CC_Radio: " .. label
    if #txt > w - 2 then txt = label end
    local x = math.max(1, w - #txt)
    term.setCursorPos(x, 1)
    term.setBackgroundColor(colors.gray); setColor(colors.yellow)
    term.write(txt:sub(1, w))
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
    term.write("   [" .. (s.signal or "?") .. "]")
  end

  -- Boutons de contrôle (bas)
  local items
  if ctx.mode == "client" then
    items = { { id = "voldown", label = "VOL-" }, { id = "volup", label = "VOL+" },
      { id = "exit", label = "QUITTER" } }
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
  local tabs = tabsFor(ctx)
  if ui.tab > #tabs then ui.tab = 1 end
  drawTabs(ctx, ui)
  local id = tabs[ui.tab].id
  if id == "np" then drawNowPlaying(ctx, ui)
  elseif id == "search" then drawSearch(ctx, ui)
  else drawQueue(ctx, ui) end
  local _, h = term.getSize()
  term.setCursorPos(1, h); setColor(colors.gray)
  local hint = (ctx.mode == "client") and " [onglets: chiffres]  [X] quitter"
    or " [chiffres] onglets  [/] recherche  [X] quitter"
  term.write(hint); setColor(colors.white)
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

-- Cherche l'index d'un onglet par id. @return number|nil
local function tabIndex(ctx, id)
  for i, t in ipairs(tabsFor(ctx)) do if t.id == id then return i end end
  return nil
end

-- @return exit:boolean
local function onChar(ctx, ui, c)
  c = c:lower()
  local tabs = tabsFor(ctx)
  local digit = tonumber(c)
  if digit and tabs[digit] then
    ui.tab, ui.scroll, ui.selected = digit, 0, nil
  elseif c == "/" then
    local si = tabIndex(ctx, "search")
    if si then ui.tab = si; runSearch(ctx, ui) end
  elseif c == "x" then
    return ctx.dispatch("exit")
  elseif tabs[ui.tab].id == "np" then
    local map = { p = "playpause", s = "skip", b = "prev", ["+"] = "volup",
      ["="] = "volup", ["-"] = "voldown", l = "loop", z = "shuffle" }
    if map[c] then return ctx.dispatch(map[c]) end
  end
  return false
end

local function onScroll(ctx, ui, dir)
  local id = tabsFor(ctx)[ui.tab].id
  if id == "search" or id == "queue" then ui.scroll = math.max(0, ui.scroll + dir) end
end

-- @return exit:boolean
local function onClick(ctx, ui, x, y)
  if y == 1 then -- barre d'onglets
    for _, r in ipairs(tabRegions(ctx)) do
      if x >= r.x and x < r.x + r.w then ui.tab, ui.scroll, ui.selected = r.i, 0, nil; return false end
    end
    return false
  end
  local id = tabsFor(ctx)[ui.tab].id
  if id == "np" and ui.npButtons then
    local b = Widgets.hitTest(ui.npButtons, x, y)
    if b then return ctx.dispatch(b.id) end
  elseif id == "search" then
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
  elseif id == "queue" then
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
      onScroll(ctx, ui, ev[2]); render(ctx, ui)
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
  onChar = onChar, render = render, tabsFor = tabsFor }

return App

end
for k, v in pairs(preload) do package.preload[k] = v end
-- ===================== point d'entree =====================
--[[ CC_RSMP - CC_Radio.lua  (point d'entree)
  CC Radio System Music Player.

  Source audio : terreng/computercraft-streaming-music (MIT).
  Voir CREDITS.md.

  Sprint 0 (v0.1.0) : fondations. Routage des commandes, config, aide,
  verification des prerequis. Les modes audio/reseau/GUI arrivent aux
  sprints suivants (voir docs/ROADMAP.md).
]]
local VERSION = "1.6.0"

-- Resolution des modules relatifs au programme (pattern valide en CraftOS-PC).
local selfDir = fs.getDir(shell.getRunningProgram())
package.path = ("/%s/?.lua;/%s/?/init.lua;"):format(selfDir, selfDir) .. package.path

local Utils      = require("lib.utils")
local Config     = require("lib.config")
local Logger     = require("lib.logger")
local Prereq      = require("core.prereq")
local Playlist    = require("core.playlist")
local Player      = require("core.player")
local Broadcaster = require("core.broadcaster")
local Client      = require("core.client")
local App         = require("ui.app")
local Help        = require("ui.help")

local CONTROL_CMDS = { "status", "stop", "skip", "pause", "resume", "prev" }

local function printPrereq(r)
  for _, e in ipairs(r.errors) do printError("[X] " .. e) end
  for _, w in ipairs(r.warnings) do
    if term.isColor() then term.setTextColor(colors.yellow) end
    print("[!] " .. w)
    if term.isColor() then term.setTextColor(colors.white) end
  end
end

local function notImplemented(sprint, what)
  printError(("'%s' arrive au Sprint %s - pas encore implemente."):format(what, sprint))
end

local function cmdConfig(cfg, parsed)
  if parsed.flags.reset then
    Config.reset()
    print("Configuration reinitialisee (valeurs par defaut).")
  elseif parsed.flags.set then
    local key = parsed.flags.set
    local val = parsed.positional[2]
    if type(key) ~= "string" or val == nil then
      printError("Usage: CC_Radio config --set <cle> <valeur>")
      return
    end
    if Config.DEFAULTS[key] == nil then
      printError("Cle de config inconnue: " .. key)
      return
    end
    cfg[key] = Utils.coerce(val)
    Config.save(cfg)
    print(("%s = %s"):format(key, tostring(cfg[key])))
  else
    print(textutils.serialise(cfg))
  end
end

-- Vérifie les prérequis d'un mode et les affiche. @return boolean ok
local function checkMode(cfg, mode)
  local r = Prereq.check(mode)
  print(("CC_Radio v%s - %s..."):format(VERSION, mode))
  printPrereq(r)
  return r.ok
end

-- Crée une file VIDE pour la session (préférences loop/shuffle issues de la config).
-- La file n'est plus persistée : chaque session démarre propre.
local function newPlaylist(cfg)
  return Playlist.new({
    loop       = cfg.loop,
    shuffle    = cfg.shuffle,
    maxQueue   = cfg.max_queue_size,
    maxHistory = cfg.history_size,
  })
end

-- Lecture locale interactive : charge la queue, ajoute la chanson demandée, lance le lecteur.
local function cmdPlayLocal(cfg, parsed)
  local pl = newPlaylist(cfg)

  local query   = parsed and (parsed.flags.query or parsed.positional[2]) or nil
  local youtube = parsed and parsed.flags.youtube or nil
  if query or youtube then
    local song = Player.resolveSong(cfg, query, youtube)
    if song then pl:add(song, true) end -- en tête : joué en premier
  end

  -- La file peut être vide : l'interface (onglet Search) permet d'ajouter des titres.
  Player.runLocal(cfg, pl)
end

-- Démarre le mode broadcaster (serveur radio).
local function cmdBroadcaster(cfg, parsed)
  if parsed.flags["local"] then
    cmdPlayLocal(cfg, parsed) -- broadcaster --local = lecture solo
    return
  end
  if not checkMode(cfg, "broadcaster") then return end
  Broadcaster.run(cfg, parsed)
end

local function cmdPlay(cfg, parsed)
  if parsed.flags["local"] then
    cmdPlayLocal(cfg, parsed)
  else
    -- raccourci : lance le broadcaster en y ajoutant la chanson demandée.
    cmdBroadcaster(cfg, parsed)
  end
end

-- loop/shuffle : préférences persistées dans la config (la file, elle, est volatile).
local function cmdLoop(cfg, parsed)
  local mode = parsed.positional[2]
  if mode == "off" or mode == "one" or mode == "all" then
    cfg.loop = mode; Config.save(cfg)
    print("Loop: " .. mode)
  else
    print("Loop actuel: " .. cfg.loop .. "   (usage: loop off|one|all)")
  end
end

local function cmdShuffle(cfg, parsed)
  local v = parsed.positional[2]
  if v == "on" or v == "off" then
    cfg.shuffle = (v == "on"); Config.save(cfg)
    print("Shuffle: " .. v)
  else
    print("Shuffle actuel: " .. tostring(cfg.shuffle) .. "   (usage: shuffle on|off)")
  end
end

local function cmdVolume(cfg, parsed)
  local v = tonumber(parsed.positional[2])
  if not v then
    print(("Volume local: %.1f | global: %.1f   (usage: volume 0.0-3.0 [--local|--global])")
      :format(cfg.local_volume, cfg.default_volume))
    return
  end
  v = math.max(0, math.min(3, v))
  if parsed.flags.global then cfg.default_volume = v else cfg.local_volume = v end
  Config.save(cfg)
  print(string.format("Volume %s: %.1f", parsed.flags.global and "global" or "local", v))
end

local BUNDLE_URL = "https://raw.githubusercontent.com/VIL-CIEL/CC_Radio_System_Music_Player/main/dist/CC_Radio.lua"

-- Met à jour le programme : retélécharge le fichier unique par-dessus lui-même.
local function cmdInstall(_cfg, _parsed)
  if not http then printError("HTTP desactive cote serveur."); return end
  print("Mise a jour de CC_Radio...")
  local r = http.get(BUNDLE_URL)
  if not r then printError("Echec du telechargement."); return end
  local data = r.readAll(); r.close()
  local prog = shell.getRunningProgram()
  local f = fs.open(prog, "w"); f.write(data); f.close()
  print("Mis a jour : " .. prog)
  print("(Desinstallation : delete CC_Radio.lua)")
end

-- Commandes de contrôle non actionnables en autonome (clavier en lecture, réseau en S3/S4).
local function cmdRuntimeInfo(command)
  printError("'" .. command .. "' n'agit pas en mode autonome.")
  print(" - en lecture locale : touches du lecteur (P/S/B/...)")
  print(" - a distance : commandes reseau (Sprint 3/4)")
end

local function main(...)
  local argv = { ... }
  local parsed = Utils.parseArgs(argv)
  local command = parsed.positional[1]
  local cfg = Config.load()
  -- Le log n'est écrit (CC_Radio.log) qu'en cas d'erreur réelle (pas à chaque lancement).
  local log = Logger.new({ level = cfg.log_level, toTerm = false })

  -- Exécute fn en capturant les erreurs (sauf interruption Ctrl+T) -> log + message clair.
  local function guard(fn)
    local ok, err = pcall(fn, cfg, parsed)
    if not ok and not tostring(err):find("Terminated") then
      log:error(tostring(command) .. ": " .. tostring(err))
      printError("Erreur: " .. tostring(err))
      printError("Details: " .. log.path)
    end
  end

  if command == nil then
    -- Aucune commande : interface unifiée (accueil -> mode).
    local mode = App.home(VERSION)
    if mode == "broadcaster" then guard(cmdBroadcaster)
    elseif mode == "client" then if checkMode(cfg, "client") then guard(Client.run) end
    elseif mode == "local" then guard(cmdPlayLocal) end
  elseif command == "help" then
    Help.show(parsed.positional[2])
  elseif command == "config" then
    cmdConfig(cfg, parsed)
  elseif command == "broadcaster" then
    guard(cmdBroadcaster)
  elseif command == "client" then
    if checkMode(cfg, "client") then guard(Client.run) end
  elseif command == "local" then
    guard(cmdPlayLocal)
  elseif command == "play" then
    guard(cmdPlay)
  elseif command == "loop" then
    cmdLoop(cfg, parsed)
  elseif command == "shuffle" then
    cmdShuffle(cfg, parsed)
  elseif command == "volume" then
    cmdVolume(cfg, parsed)
  elseif command == "install" then
    cmdInstall(cfg, parsed)
  elseif Utils.contains(CONTROL_CMDS, command) then
    cmdRuntimeInfo(command)
  else
    printError("Commande inconnue: " .. tostring(command))
    Help.show()
  end
end

main(...)
