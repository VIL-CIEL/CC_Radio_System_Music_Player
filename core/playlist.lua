--[[ CC_RSMP - core/playlist.lua
  Gestion de la file de lecture : queue, historique, shuffle, loop (off/one/all).
  Logique pure (aucune E/S audio/réseau) -> entièrement testable hors-jeu.
  Persistance dans queue.dat (textutils.serialize).
]]
local Playlist = {}
Playlist.__index = Playlist
Playlist.PATH = "queue.dat"

--- @param opts table { loop, shuffle, maxQueue, maxHistory }
function Playlist.new(opts)
  opts = opts or {}
  return setmetatable({
    queue      = {},                       -- chansons à venir [{id,name,artist,...}]
    history    = {},                       -- jouées, plus récente en tête
    current    = nil,                      -- chanson en cours
    loop       = opts.loop or "off",       -- "off" | "one" | "all"
    shuffle    = opts.shuffle or false,
    maxQueue   = opts.maxQueue or 50,
    maxHistory = opts.maxHistory or 10,
  }, Playlist)
end

--- Ajoute une chanson (en fin, ou en tête si atFront).
-- @return boolean ok, string|nil err
function Playlist:add(song, atFront)
  if #self.queue >= self.maxQueue then return false, "Queue pleine (" .. self.maxQueue .. ")" end
  if atFront then
    table.insert(self.queue, 1, song)
  else
    self.queue[#self.queue + 1] = song
  end
  return true
end

function Playlist:clear()
  self.queue = {}
end

function Playlist:size()
  return #self.queue
end

--- Renvoie jusqu'à n chansons à venir (sans les retirer).
function Playlist:upcoming(n)
  local out = {}
  for i = 1, math.min(n or 3, #self.queue) do out[i] = self.queue[i] end
  return out
end

function Playlist:_pushHistory(song)
  if not song then return end
  table.insert(self.history, 1, song)
  while #self.history > self.maxHistory do table.remove(self.history) end
end

--- Avance vers la chanson suivante en respectant loop/shuffle.
-- Met à jour current et history. @return table|nil song
function Playlist:advance()
  local prev = self.current

  if self.loop == "one" and prev then
    return prev -- rejoue la même; current/history inchangés
  end

  if prev then self:_pushHistory(prev) end

  local nextSong
  if #self.queue > 0 then
    if self.shuffle then
      nextSong = table.remove(self.queue, math.random(1, #self.queue))
    else
      nextSong = table.remove(self.queue, 1)
    end
  elseif self.loop == "all" and #self.history > 0 then
    -- Reconstruire la queue depuis l'historique, dans l'ordre de lecture d'origine.
    local restored = {}
    for i = #self.history, 1, -1 do restored[#restored + 1] = self.history[i] end
    self.queue = restored
    self.history = {}
    if self.shuffle then
      nextSong = table.remove(self.queue, math.random(1, #self.queue))
    else
      nextSong = table.remove(self.queue, 1)
    end
  end

  self.current = nextSong
  return nextSong
end

--- Revient à la chanson précédente (depuis l'historique).
-- @return table|nil song
function Playlist:goPrev()
  if #self.history == 0 then return nil end
  local prevSong = table.remove(self.history, 1)
  if self.current then table.insert(self.queue, 1, self.current) end
  self.current = prevSong
  return prevSong
end

--- Fait défiler le mode loop : off -> all -> one -> off.
function Playlist:cycleLoop()
  self.loop = ({ off = "all", all = "one", one = "off" })[self.loop] or "off"
  return self.loop
end

function Playlist:toggleShuffle()
  self.shuffle = not self.shuffle
  return self.shuffle
end

-- ── Persistance ──────────────────────────────────────────────────────────────

function Playlist:save(path)
  path = path or Playlist.PATH
  local f = fs.open(path, "w")
  if not f then return false end
  f.write(textutils.serialize({ queue = self.queue, loop = self.loop, shuffle = self.shuffle }))
  f.close()
  return true
end

--- Charge la queue persistée (queue/loop/shuffle). L'historique et current ne sont pas persistés.
function Playlist.load(path, opts)
  path = path or Playlist.PATH
  local pl = Playlist.new(opts)
  if fs.exists(path) then
    local f = fs.open(path, "r")
    if f then
      local raw = f.readAll()
      f.close()
      local ok, data = pcall(textutils.unserialize, raw)
      if ok and type(data) == "table" then
        pl.queue   = data.queue or {}
        pl.loop    = data.loop or pl.loop
        pl.shuffle = data.shuffle and true or false
      end
    end
  end
  return pl
end

return Playlist
