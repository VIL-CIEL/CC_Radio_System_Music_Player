--[[ CC_RSMP - lib/discovery.lua
  Découverte de station : écoute les annonces DISCO du broadcaster, et envoi du join.
]]
local Discovery = {}

--- Attend une annonce DISCO et renvoie les infos du broadcaster.
-- @return table|nil { id, label, song_title }
function Discovery.findBroadcaster(net, timeout)
  local sender, msg, mproto = net:receiveAny(timeout or 10)
  while sender do
    if mproto == net.P.DISCO and type(msg) == "table" and msg.type == "announce" then
      return { id = msg.broadcaster_id or sender, label = msg.label, song_title = msg.song_title }
    end
    sender, msg, mproto = net:receiveAny(timeout or 10)
  end
  return nil
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
