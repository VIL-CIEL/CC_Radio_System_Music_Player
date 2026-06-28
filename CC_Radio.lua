--[[ CC_RSMP - CC_Radio.lua  (point d'entree)
  CC Radio System Music Player.

  Source audio : terreng/computercraft-streaming-music (MIT).
  Voir CREDITS.md.

  Sprint 0 (v0.1.0) : fondations. Routage des commandes, config, aide,
  verification des prerequis. Les modes audio/reseau/GUI arrivent aux
  sprints suivants (voir docs/ROADMAP.md).
]]
local VERSION = "1.5.1"

-- Resolution des modules relatifs au programme (pattern valide en CraftOS-PC).
local selfDir = fs.getDir(shell.getRunningProgram())
package.path = ("/%s/?.lua;/%s/?/init.lua;"):format(selfDir, selfDir) .. package.path

local Utils      = require("lib.utils")
local Config     = require("lib.config")
local Logger     = require("lib.logger")
local Prereq     = require("core.prereq")
local Downloader  = require("core.downloader")
local Playlist    = require("core.playlist")
local Player      = require("core.player")
local Broadcaster = require("core.broadcaster")
local Client      = require("core.client")
local App         = require("ui.app")
local CLI         = require("ui.cli")
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

-- Charge la playlist persistée avec les paramètres issus de la config.
local function loadPlaylist(cfg)
  return Playlist.load(Playlist.PATH, {
    loop       = cfg.loop,
    shuffle    = cfg.shuffle,
    maxQueue   = cfg.max_queue_size,
    maxHistory = cfg.history_size,
  })
end

-- Lecture locale interactive : charge la queue, ajoute la chanson demandée, lance le lecteur.
local function cmdPlayLocal(cfg, parsed)
  local pl = loadPlaylist(cfg)

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

-- Résout une chanson pour `queue --add` (recherche interactive ou id/URL YouTube).
local function resolveForQueue(cfg, parsed)
  if parsed.flags.youtube then
    local id = Utils.extractYtId(parsed.flags.youtube)
    if not id then printError("URL/ID YouTube invalide."); return nil end
    return { id = id, name = "(YouTube " .. id .. ")", artist = "" }
  end
  local query = (type(parsed.flags.add) == "string" and parsed.flags.add) or parsed.flags.query
  if not query then
    printError('Usage: CC_Radio queue --add "..."  (ou --add --youtube <url>)')
    return nil
  end
  print("Recherche: " .. query .. " ...")
  local results, err = Downloader.search(cfg, query)
  if not results then printError(err); return nil end
  return CLI.pickResult(results)
end

local function cmdQueue(cfg, parsed)
  local pl = loadPlaylist(cfg)
  if parsed.flags.clear then
    pl:clear(); pl:save(); print("Queue videe.")
  elseif parsed.flags.add then
    local song = resolveForQueue(cfg, parsed)
    if song then
      local ok, e = pl:add(song)
      if ok then pl:save(); print("Ajoute: " .. (Utils.trim(song.name) or song.id))
      else printError(e) end
    end
  else
    CLI.printQueue(pl)
  end
end

local function cmdLoop(cfg, parsed)
  local mode = parsed.positional[2]
  if mode == "off" or mode == "one" or mode == "all" then
    cfg.loop = mode; Config.save(cfg)
    local pl = loadPlaylist(cfg); pl.loop = mode; pl:save()
    print("Loop: " .. mode)
  else
    print("Loop actuel: " .. cfg.loop .. "   (usage: loop off|one|all)")
  end
end

local function cmdShuffle(cfg, parsed)
  local v = parsed.positional[2]
  if v == "on" or v == "off" then
    local b = (v == "on"); cfg.shuffle = b; Config.save(cfg)
    local pl = loadPlaylist(cfg); pl.shuffle = b; pl:save()
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
  elseif command == "queue" then
    cmdQueue(cfg, parsed)
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
