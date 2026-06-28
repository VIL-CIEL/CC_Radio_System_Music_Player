--[[ CC_RSMP - lib/discovery.lua
  Découverte de station : écoute les annonces DISCO du broadcaster, et envoi du join.
]]
local Discovery = {}

--- Attend une annonce DISCO et renvoie les infos du broadcaster.
-- Envoie d'abord une requête "who" : les stations répondent aussitôt (même sans musique).
-- @return table|nil { id, label, song_title }
function Discovery.findBroadcaster(net, timeout)
  net:announce({ type = "who" })
  local sender, msg, mproto = net:receiveAny(timeout or 10)
  while sender do
    if mproto == net.P.DISCO and type(msg) == "table" and msg.type == "announce" then
      return { id = msg.broadcaster_id or sender, label = msg.label, song_title = msg.song_title }
    end
    sender, msg, mproto = net:receiveAny(timeout or 10)
  end
  return nil
end

--- Liste toutes les stations actives (annonces uniques) sur une fenêtre de temps.
-- Envoie "who" pour que les stations se signalent immédiatement.
-- @return table liste de { id, label, song_title }
function Discovery.listBroadcasters(net, seconds)
  net:announce({ type = "who" })
  local seen, list = {}, {}
  local deadline = os.epoch("utc") + (seconds or 2) * 1000
  while true do
    local left = (deadline - os.epoch("utc")) / 1000
    if left <= 0 then break end
    local sender, msg, mproto = net:receiveAny(left)
    if not sender then break end
    if mproto == net.P.DISCO and type(msg) == "table" and msg.type == "announce" then
      local id = msg.broadcaster_id or sender
      if not seen[id] then
        seen[id] = true
        list[#list + 1] = { id = id, label = msg.label or ("Station " .. id), song_title = msg.song_title }
      end
    end
  end
  return list
end

--- Envoie un message DISCO:join au broadcaster (ou en broadcast si id absent).
function Discovery.join(net, broadcasterId, label)
  net:join(broadcasterId, {
    type = "join",
    client_id = os.getComputerID(),
    label = label,
  })
end

return Discovery
