--[[ CC_RSMP - core/player.lua
  Lecteur local (mode standalone). Le moteur (boucle audio + dispatch) est piloté par
  l'interface unifiée (ui/app.lua) sur le terminal, et par le compagnon monitor.
]]
local Downloader = require("core.downloader")
local Audio      = require("core.audio")
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
    elseif action == "loop" then playlist:cycleLoop(); playlist:save()
    elseif action == "shuffle" then playlist:toggleShuffle(); playlist:save()
    elseif action == "playnow" and args.song then
      playlist:add(args.song, true); playlist:save()
      ctrl.skip = true; audio:stop(); os.queueEvent("rsmp_resume"); os.queueEvent("queue_updated")
    elseif action == "playnext" and args.song then
      playlist:add(args.song, true); playlist:save(); os.queueEvent("queue_updated")
    elseif action == "enqueue" and args.song then
      playlist:add(args.song); playlist:save(); os.queueEvent("queue_updated")
    elseif action == "remove" and args.index then
      table.remove(playlist.queue, args.index); playlist:save()
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

  audio:stop(); playlist:save()
  App.cleanup(guiMon)
  print("Lecture terminee.")
end

return Player
