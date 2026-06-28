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
