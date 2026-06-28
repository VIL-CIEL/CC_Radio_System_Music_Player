--[[ CC_RSMP - lib/base64.lua
  Encodage/décodage base64 (arithmétique, sans dépendre des opérateurs bit Lua 5.3).
  Sert à transmettre les chunks DFPWM binaires via rednet : la sérialisation d'une
  string binaire gonfle ~3.2x (échappements), alors que sa version base64 ~1.34x.
  Mesuré : encode/décode ~6 ms pour 16 KiB (négligeable vs ~2.7 s d'audio/chunk).
]]
local Base64 = {}

local CH = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENC, DEC = {}, {}
for i = 0, 63 do
  local c = CH:sub(i + 1, i + 1)
  ENC[i] = c
  DEC[c:byte()] = i
end

function Base64.encode(data)
  local t, n, i = {}, #data, 1
  while i <= n do
    local b1 = data:byte(i)
    local b2 = data:byte(i + 1)
    local b3 = data:byte(i + 2)
    t[#t + 1] = ENC[math.floor(b1 / 4)]
    t[#t + 1] = ENC[(b1 % 4) * 16 + math.floor((b2 or 0) / 16)]
    if b2 then
      t[#t + 1] = ENC[(b2 % 16) * 4 + math.floor((b3 or 0) / 64)]
      t[#t + 1] = b3 and ENC[b3 % 64] or "="
    else
      t[#t + 1] = "=="
    end
    i = i + 3
  end
  return table.concat(t)
end

function Base64.decode(s)
  local t, i, n = {}, 1, #s
  while i <= n do
    local a = DEC[s:byte(i)]
    local b = DEC[s:byte(i + 1)]
    local cb = s:byte(i + 2)
    local db = s:byte(i + 3)
    local c = (cb and cb ~= 61) and DEC[cb] or nil
    local d = (db and db ~= 61) and DEC[db] or nil
    if a and b then
      t[#t + 1] = string.char(a * 4 + math.floor(b / 16))
      if c then t[#t + 1] = string.char((b % 16) * 16 + math.floor(c / 4)) end
      if c and d then t[#t + 1] = string.char((c % 4) * 64 + d) end
    end
    i = i + 4
  end
  return table.concat(t)
end

return Base64
