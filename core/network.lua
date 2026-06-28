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
