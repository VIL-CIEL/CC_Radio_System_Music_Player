--[[ CC_RSMP - core/downloader.lua
  Recherche et streaming audio via l'API terreng (computercraft-streaming-music).
  Contrat (validé sur l'API en direct) :
    - recherche : GET <api>?v=<ver>&search=<query>  -> JSON (liste de {id,name,artist,type?})
    - download  : GET <api>?v=<ver>&id=<id> (binary) -> flux DFPWM
                  on lit d'abord 4 octets (header) puis des chunks de chunkBytes.
  Le champ `id` correspond à l'identifiant vidéo YouTube.
  Crédit : terreng (MIT) — voir CREDITS.md.
]]
local Downloader = {}

-- http.get avec quelques tentatives (robustesse réseau).
local function httpGet(url, headers, binary, retries)
  retries = retries or 0
  local r, err
  for attempt = 0, retries do
    r, err = http.get(url, headers, binary)
    if r then return r end
    if attempt < retries then os.sleep(1) end
  end
  return nil, (tostring(err) .. " (apres " .. (retries + 1) .. " tentatives)")
end

function Downloader.searchUrl(cfg, query)
  return cfg.api_url .. "?v=" .. textutils.urlEncode(cfg.api_version)
      .. "&search=" .. textutils.urlEncode(query)
end

function Downloader.downloadUrl(cfg, id)
  return cfg.api_url .. "?v=" .. textutils.urlEncode(cfg.api_version)
      .. "&id=" .. textutils.urlEncode(id)
end

--- Recherche synchrone.
-- @return table|nil results, string|nil err
function Downloader.search(cfg, query)
  local r, err = httpGet(Downloader.searchUrl(cfg, query), nil, false, cfg.http_retries)
  if not r then return nil, "Echec de la recherche: " .. tostring(err) end
  local body = r.readAll()
  r.close()
  local ok, parsed = pcall(textutils.unserialiseJSON, body)
  if not ok or type(parsed) ~= "table" then
    return nil, "Reponse de recherche invalide (JSON illisible)"
  end
  return parsed
end

-- ── Flux de téléchargement (lecture par chunks) ──────────────────────────────
local Stream = {}
Stream.__index = Stream
Downloader.Stream = Stream

--- Ouvre un flux binaire pour un id.
-- @return Stream|nil stream, string|nil err
function Downloader.openStream(cfg, id)
  local h, err = httpGet(Downloader.downloadUrl(cfg, id), nil, true, cfg.http_retries) -- binary
  if not h then return nil, "Echec du telechargement: " .. tostring(err) end
  local chunkBytes = (cfg.chunk_size_kb or 16) * 1024
  return setmetatable({
    handle = h,
    chunkBytes = chunkBytes,
    header = h.read(4), -- 4 premiers octets, recollés au 1er chunk (cf. terreng)
    first = true,
  }, Stream)
end

--- Lit le prochain chunk DFPWM brut (string), ou nil en fin de flux.
function Stream:read()
  if not self.handle then return nil end
  local n = self.first and (self.chunkBytes - 4) or self.chunkBytes
  local chunk = self.handle.read(n)
  if not chunk then self:close(); return nil end
  if self.first then
    chunk = (self.header or "") .. chunk
    self.first = false
  end
  return chunk
end

function Stream:close()
  if self.handle then
    self.handle.close()
    self.handle = nil
  end
end

return Downloader
