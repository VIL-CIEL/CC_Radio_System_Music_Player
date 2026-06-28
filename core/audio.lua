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
-- Bloque jusqu'à ce que tous les speakers aient accepté le buffer.
function Audio:playPCM(pcm)
  local fns = {}
  for i, spk in ipairs(self.speakers) do
    local name = peripheral.getName(spk)
    fns[i] = function()
      while not spk.playAudio(pcm, self.volume) do
        repeat
          local _, sn = os.pullEvent("speaker_audio_empty")
        until sn == name
      end
    end
  end
  if #fns > 0 then
    parallel.waitForAll(table.unpack(fns))
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

--- Arrête immédiatement tous les speakers (flush des buffers).
function Audio:stop()
  for _, spk in ipairs(self.speakers) do pcall(spk.stop) end
end

--- Convertit un nombre de samples en secondes.
function Audio.samplesToSeconds(n)
  return n / Audio.SAMPLE_RATE
end

return Audio
