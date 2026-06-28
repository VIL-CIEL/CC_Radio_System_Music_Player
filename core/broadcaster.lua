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

  local playlist = Playlist.load(Playlist.PATH, {
    loop = cfg.loop, shuffle = cfg.shuffle,
    maxQueue = cfg.max_queue_size, maxHistory = cfg.history_size,
  })

  local state = {
    label = (parsed and parsed.flags.label) or cfg.station_label,
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
    for i, s in ipairs(playlist:upcoming(3)) do up[i] = { id = s.id, title = s.name } end
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
        playlist.loop = args.mode; playlist:save()
      end
    elseif command == "shuffle" then
      playlist.shuffle = args.enabled and true or false; playlist:save()
    elseif command == "play" or command == "queue" then
      local song = Broadcaster.resolveSong(cfg, args.query, args.url)
      if song then
        playlist:add(song, command == "play")
        playlist:save()
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
    elseif action == "loop" then playlist:cycleLoop(); playlist:save()
    elseif action == "shuffle" then playlist:toggleShuffle(); playlist:save()
    elseif action == "status" then applyCommand("status")
    elseif action == "playnow" and args.song then
      playlist:add(args.song, true); playlist:save(); applyCommand("skip"); os.queueEvent("queue_updated")
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
  playlist:save()
  net:close()
  App.cleanup(guiMon)
  print("Broadcaster arrete.")
end

return Broadcaster
