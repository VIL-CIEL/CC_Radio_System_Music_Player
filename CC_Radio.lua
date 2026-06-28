--[[ CC_RSMP - CC_Radio.lua  (point d'entree)
  CC Radio System Music Player.

  Source audio : terreng/computercraft-streaming-music (MIT).
  Voir CREDITS.md.

  Sprint 0 (v0.1.0) : fondations. Routage des commandes, config, aide,
  verification des prerequis. Les modes audio/reseau/GUI arrivent aux
  sprints suivants (voir docs/ROADMAP.md).
]]
local VERSION = "0.1.0"

-- Resolution des modules relatifs au programme (pattern valide en CraftOS-PC).
local selfDir = fs.getDir(shell.getRunningProgram())
package.path = ("/%s/?.lua;/%s/?/init.lua;"):format(selfDir, selfDir) .. package.path

local Utils      = require("lib.utils")
local Config     = require("lib.config")
local Logger     = require("lib.logger")
local Prereq     = require("core.prereq")
local Downloader = require("core.downloader")
local Audio      = require("core.audio")
local CLI        = require("ui.cli")
local Help       = require("ui.help")

local CONTROL_CMDS = { "queue", "status", "stop", "volume", "skip", "pause", "resume", "prev", "loop", "shuffle" }

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

local function cmdMode(cfg, command)
  local r = Prereq.check(command)
  print(("CC_Radio v%s - verification (%s)..."):format(VERSION, command))
  printPrereq(r)
  if not r.ok then return end
  print("Prerequis OK.")
  if command == "broadcaster" then
    notImplemented("3", "broadcaster")
  elseif command == "client" then
    notImplemented("4", "client")
  else -- local
    notImplemented("1", "local")
  end
end

-- Résout la chanson à jouer : URL/id YouTube direct, ou recherche + sélection.
local function resolveSong(cfg, parsed)
  if parsed.flags.youtube then
    local id = Utils.extractYtId(parsed.flags.youtube)
    if not id then
      printError("URL/ID YouTube invalide: " .. tostring(parsed.flags.youtube))
      return nil
    end
    return { id = id, name = "(YouTube " .. id .. ")", artist = "" }
  end
  local query = parsed.flags.query or parsed.positional[2]
  if not query then
    printError('Usage: CC_Radio play --query "..." --local   (ou --youtube <url>)')
    return nil
  end
  print("Recherche: " .. query .. " ...")
  local results, err = Downloader.search(cfg, query)
  if not results then printError(err); return nil end
  return CLI.pickResult(results)
end

-- Lecture locale (standalone) : recherche -> stream -> playback + contrôle volume/stop.
local function cmdPlayLocal(cfg, parsed)
  local audio = Audio.new({
    speakers = { peripheral.find("speaker") },
    volume   = cfg.local_volume,
  })
  if not audio:hasOutput() then
    printError("Aucun speaker detecte : lecture locale impossible.")
    return
  end

  local song = resolveSong(cfg, parsed)
  if not song then return end

  local stream, err = Downloader.openStream(cfg, song.id)
  if not stream then printError(err); return end

  local state = {
    song     = song,
    elapsed  = 0,
    duration = CLI.parseDuration(song.artist),
    volume   = audio.volume,
  }
  CLI.drawNowPlaying(state)

  parallel.waitForAny(
    function() -- boucle audio
      audio:streamPlay(stream, function(samples)
        state.elapsed = Audio.samplesToSeconds(samples)
        state.volume  = audio.volume
        CLI.drawNowPlaying(state)
      end)
    end,
    function() -- contrôles minimaux (S1) : volume + stop
      while true do
        local _, key = os.pullEvent("key")
        if key == keys.q then
          return
        elseif key == keys.up then
          audio:setVolume(audio.volume + 0.1)
          state.volume = audio.volume; CLI.drawNowPlaying(state)
        elseif key == keys.down then
          audio:setVolume(audio.volume - 0.1)
          state.volume = audio.volume; CLI.drawNowPlaying(state)
        end
      end
    end
  )

  audio:stop()
  stream:close()
  print("")
  print("Lecture terminee.")
end

local function cmdPlay(cfg, parsed)
  if parsed.flags["local"] then
    cmdPlayLocal(cfg, parsed)
  else
    notImplemented("3", "play (broadcaster) - utilisez --local pour la lecture solo")
  end
end

local function main(...)
  local argv = { ... }
  local parsed = Utils.parseArgs(argv)
  local command = parsed.positional[1] or "help"
  local cfg = Config.load()
  local _log = Logger.new({ level = cfg.log_level })

  if command == "help" then
    Help.show(parsed.positional[2])
  elseif command == "config" then
    cmdConfig(cfg, parsed)
  elseif command == "broadcaster" or command == "client" or command == "local" then
    cmdMode(cfg, command)
  elseif command == "play" then
    cmdPlay(cfg, parsed)
  elseif command == "install" then
    notImplemented("6", "install")
  elseif Utils.contains(CONTROL_CMDS, command) then
    notImplemented("2/3", command)
  else
    printError("Commande inconnue: " .. tostring(command))
    Help.show()
  end
end

main(...)
