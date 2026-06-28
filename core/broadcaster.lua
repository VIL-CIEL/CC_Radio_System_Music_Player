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
local CLI        = require("ui.cli")
local GUI        = require("ui.gui")
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

  -- GUI monitor (auto si présent ; --gui force, erreur si absent).
  local guiMon, guiButtons
  do
    local mon, w, h = GUI.detect(cfg)
    if mon then
      guiMon = mon
      guiButtons = GUI.buttons("broadcaster", w, h)
    elseif parsed and parsed.flags.gui then
      printError("Option --gui: " .. tostring(w))
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
            net:broadcastAudio(state.seq, song.id, encData, encoding, nil)

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

  local function draw()
    CLI.drawBroadcaster(state, playlist, audio, localPlay, clientCount(), cfg.audio_encoding)
    if guiMon then GUI.drawBroadcaster(guiMon, state, playlist, audio, clientCount(), guiButtons) end
  end

  -- Action unique partagée clavier (uiLoop) et tactile (monitor_touch).
  -- @return boolean exit
  local function doAction(a)
    if a == "exit" then
      ctrl.exit = true; audio:stop(); os.queueEvent("rsmp_resume"); return true
    elseif a == "playpause" then applyCommand(ctrl.paused and "resume" or "pause")
    elseif a == "skip" then applyCommand("skip")
    elseif a == "prev" then applyCommand("prev")
    elseif a == "volup" then audio:setVolume(audio.volume + 0.1)
    elseif a == "voldown" then audio:setVolume(audio.volume - 0.1)
    elseif a == "loop" then playlist:cycleLoop(); playlist:save()
    elseif a == "shuffle" then playlist:toggleShuffle(); playlist:save()
    elseif a == "queue" then CLI.showQueue(playlist)
    elseif a == "add" then
      write("Ajouter (recherche): ")
      local song = Broadcaster.resolveSong(cfg, read())
      if song then playlist:add(song); playlist:save(); os.queueEvent("queue_updated") end
    end
    return false
  end

  local KEYMAP = {
    x = "exit", p = "playpause", s = "skip", b = "prev",
    ["+"] = "volup", ["="] = "volup", ["-"] = "voldown",
    l = "loop", z = "shuffle", q = "queue", a = "add",
  }

  local function uiLoop()
    draw()
    local timer = os.startTimer(0.5)
    while true do
      local ev = { os.pullEvent() }
      if ev[1] == "char" then
        local action = KEYMAP[ev[2]:lower()]
        if action and doAction(action) then return end
        draw()
      elseif ev[1] == "monitor_touch" and guiButtons then
        local id = GUI.handleTouch(guiButtons, ev[3], ev[4])
        if id and doAction(id) then return end
        draw()
      elseif ev[1] == "timer" and ev[2] == timer then
        draw()
        timer = os.startTimer(0.5)
      end
    end
  end

  -- Annonce immédiate puis lancement des boucles.
  net:announce({
    type = "announce", broadcaster_id = state.id, label = state.label,
    state = state.playbackState, song_title = state.song and state.song.name,
  })

  parallel.waitForAny(audioLoop, networkLoop, metaLoop, discoveryLoop, uiLoop)

  net:broadcastStop(state.song and state.song.id)
  audio:stop()
  playlist:save()
  net:close()
  term.setBackgroundColor(colors.black)
  print("")
  print("Broadcaster arrete.")
end

return Broadcaster
