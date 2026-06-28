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
local CLI       = require("ui.cli")

local Client = {}

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
      ctx.buffer[#ctx.buffer + 1] = ctx.audio:decode(rawDfpwm)
      os.queueEvent("rsmp_chunk")
    elseif msg.type == "audio_stop" then
      view.state = "stopped"
    end
  elseif proto == net.P.META and msg.type == "meta" then
    view.title      = msg.title or view.title
    view.author     = msg.author or view.author
    view.duration   = msg.duration or 0
    view.position   = msg.position or 0
    view.state      = msg.state or view.state
    view.label      = msg.label or view.label
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
      local sender, msg, mproto = net:receiveAny(5)
      if not sender then
        view.signal = "lost"
        local b = Discovery.findBroadcaster(net, 5)
        if b then
          ctx.targetId = b.id; view.broadcaster = b.id; view.label = b.label
          Discovery.join(net, ctx.targetId, cfg.station_label or "client")
          view.signal = "connected"
        end
      elseif type(msg) == "table" then
        Client.handle(ctx, sender, msg, mproto)
      end
    end
  end

  local function playLoop()
    while not ctrl.exit do
      if #ctx.buffer > 0 then
        audio:playPCM(table.remove(ctx.buffer, 1))
      else
        os.pullEvent("rsmp_chunk")
        if ctrl.exit then return end
      end
    end
  end

  local function uiLoop()
    CLI.drawClient(view, audio)
    local timer = os.startTimer(0.5)
    while true do
      local ev = { os.pullEvent() }
      if ev[1] == "char" then
        local ch = ev[2]:lower()
        if ch == "x" then
          ctrl.exit = true; audio:stop(); os.queueEvent("rsmp_chunk"); return
        elseif ch == "+" or ch == "=" then
          view.volume = audio:setVolume(audio.volume + 0.1)
        elseif ch == "-" then
          view.volume = audio:setVolume(audio.volume - 0.1)
        elseif ch == "g" and ctx.targetId then
          net:sendCmd(ctx.targetId, { type = "cmd", command = "volume",
            args = { level = audio.volume }, client_id = os.getComputerID() })
        elseif ch == "s" and ctx.targetId then
          net:sendCmd(ctx.targetId, { type = "cmd", command = "status",
            args = {}, client_id = os.getComputerID() })
        end
        CLI.drawClient(view, audio)
      elseif ev[1] == "timer" and ev[2] == timer then
        view.volume = audio.volume
        CLI.drawClient(view, audio)
        timer = os.startTimer(0.5)
      end
    end
  end

  parallel.waitForAny(netLoop, playLoop, uiLoop)

  audio:stop()
  net:close()
  term.setBackgroundColor(colors.black)
  print("")
  print("Client deconnecte.")
end

return Client
