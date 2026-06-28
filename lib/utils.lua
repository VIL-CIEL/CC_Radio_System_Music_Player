--[[ CC_RSMP - lib/utils.lua
  Fonctions utilitaires partagées : parsing d'arguments, formatage, helpers tables.
]]
local Utils = {}

--- Parse les arguments shell.
-- Convention : "--key value" -> flags.key = value ; "--flag" seul -> flags.flag = true.
-- @param argv table  liste d'arguments (le `...` du programme)
-- @return table { positional = { ... }, flags = { [key] = value|true } }
function Utils.parseArgs(argv)
  local res = { positional = {}, flags = {} }
  local i = 1
  while i <= #argv do
    local a = argv[i]
    if type(a) == "string" and a:sub(1, 2) == "--" then
      local key = a:sub(3)
      local nxt = argv[i + 1]
      if nxt ~= nil and not (type(nxt) == "string" and nxt:sub(1, 2) == "--") then
        res.flags[key] = nxt
        i = i + 2
      else
        res.flags[key] = true
        i = i + 1
      end
    else
      res.positional[#res.positional + 1] = a
      i = i + 1
    end
  end
  return res
end

--- Formate des secondes en "m:ss".
function Utils.formatTime(sec)
  sec = math.max(0, math.floor(tonumber(sec) or 0))
  return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

--- Borne une valeur dans [lo, hi].
function Utils.clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi else return v end
end

--- Vrai si la séquence `t` contient `val`.
function Utils.contains(t, val)
  for _, v in ipairs(t) do
    if v == val then return true end
  end
  return false
end

--- Coerce une chaîne CLI en booléen / nombre / chaîne.
function Utils.coerce(v)
  if v == true or v == false then return v end
  if v == "true" then return true end
  if v == "false" then return false end
  local n = tonumber(v)
  if n ~= nil then return n end
  return v
end

--- Copie superficielle d'une table.
function Utils.shallowCopy(t)
  local r = {}
  for k, v in pairs(t) do r[k] = v end
  return r
end

return Utils
