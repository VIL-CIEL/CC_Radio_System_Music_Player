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

  -- Découverte initiale.
  print("Recherche d'une station...")
  if not ctx.targetId then
    local b = Discovery.findBroadcaster(net, 10)
    if b then ctx.targetId = b.id; view.label = b.label end
  end
  view.broadcaster = ctx.targetId
  if ctx.targetId then
    Discovery.join(net, ctx.targetId, cfg.station_label or "client")
    view.signal = "connected"
  else
    print("Aucune station trouvee. En attente d'annonce...")
  end

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
    elseif action == "global" then sendCmd("volume", { level = audio.volume })
    elseif action == "status" then sendCmd("status")
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
