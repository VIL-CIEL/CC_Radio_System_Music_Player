--[[ CC_RSMP - core/player.lua
  Lecteur local interactif : joue une Playlist sur les speakers locaux et gère les
  contrôles clavier (pause/skip/prev/volume/loop/shuffle/queue/add/exit).

  Architecture : parallel.waitForAny(audioLoop, inputLoop).
  - audioLoop  : enchaîne les chansons, lit/décode/joue les chunks, vérifie les flags
                 de contrôle entre deux chunks.
  - inputLoop  : capture le clavier, met à jour les flags, et utilise audio:stop()
                 pour rendre skip/pause réactifs (libère la backpressure du speaker).
]]
local Downloader = require("core.downloader")
local Audio      = require("core.audio")
local CLI        = require("ui.cli")

local Player = {}

-- Résout une chanson via recherche interactive ou id/URL YouTube direct.
local function resolveSong(cfg, query, youtube)
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
  return CLI.pickResult(results)
end
Player.resolveSong = resolveSong

--- Joue une playlist en local de façon interactive.
function Player.runLocal(cfg, playlist)
  local audio = Audio.new({ speakers = { peripheral.find("speaker") }, volume = cfg.local_volume })
  if not audio:hasOutput() then
    printError("Aucun speaker detecte : lecture locale impossible.")
    return
  end
  math.randomseed(os.epoch("utc"))

  local ctrl = { exit = false, paused = false, skip = false, prevReq = false }
  local view = { song = nil, elapsed = 0, duration = nil, volume = audio.volume,
                 paused = false, state = "stopped" }

  local function draw()
    view.volume = audio.volume
    CLI.drawPlayer(view, playlist)
  end

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
        view.song, view.state = nil, "stopped"
        draw()
        os.pullEvent() -- réveillé par "queue_updated", une touche, etc.
      else
        view.song     = song
        view.duration = CLI.parseDuration(song.artist)
        view.elapsed  = 0
        view.state    = "playing"
        draw()

        local stream, err = Downloader.openStream(cfg, song.id)
        if not stream then
          printError(err)
        else
          ctrl.skip = false
          local samples = 0
          while not ctrl.exit and not ctrl.skip do
            while ctrl.paused and not ctrl.exit and not ctrl.skip do
              view.state = "paused"; draw()
              os.pullEvent("rsmp_resume")
            end
            if ctrl.exit or ctrl.skip then break end
            view.state = "playing"

            local chunk = stream:read()
            if not chunk then break end -- fin du morceau
            local pcm = audio:decode(chunk)
            samples = samples + #pcm
            audio:playPCM(pcm)
            view.elapsed = Audio.samplesToSeconds(samples)
            draw()
          end
          stream:close()
        end
      end
    end
  end

  local function inputLoop()
    draw()
    while true do
      local _, ch = os.pullEvent("char")
      ch = ch:lower()
      if ch == "x" then
        ctrl.exit = true
        audio:stop()
        os.queueEvent("rsmp_resume")
        return
      elseif ch == "p" then
        ctrl.paused = not ctrl.paused
        if ctrl.paused then audio:stop() else os.queueEvent("rsmp_resume") end
        draw()
      elseif ch == "s" then
        ctrl.skip = true; audio:stop(); os.queueEvent("rsmp_resume")
      elseif ch == "b" then
        ctrl.prevReq = true; ctrl.skip = true; audio:stop(); os.queueEvent("rsmp_resume")
      elseif ch == "+" or ch == "=" then
        audio:setVolume(audio.volume + 0.1); draw()
      elseif ch == "-" then
        audio:setVolume(audio.volume - 0.1); draw()
      elseif ch == "l" then
        playlist:cycleLoop(); playlist:save(); draw()
      elseif ch == "z" then
        playlist:toggleShuffle(); playlist:save(); draw()
      elseif ch == "q" then
        CLI.showQueue(playlist); draw()
      elseif ch == "a" then
        local song = resolveSong(cfg, (function()
          write("Ajouter (recherche): "); return read()
        end)())
        if song then
          local ok, e = playlist:add(song)
          if ok then playlist:save(); os.queueEvent("queue_updated") else printError(e) end
        end
        draw()
      end
    end
  end

  parallel.waitForAny(audioLoop, inputLoop)

  audio:stop()
  playlist:save()
  term.setBackgroundColor(colors.black)
  print("")
  print("Lecture terminee.")
end

return Player
