--[[ CC_RSMP - lib/logger.lua
  Logger à niveaux : écrit dans un fichier et, en option, sur le terminal.
  Usage : local log = Logger.new({ level = "info" }) ; log:info("message")
]]
local Logger = {}
Logger.__index = Logger

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }
local COLORS = {
  debug = colors.gray,
  info  = colors.white,
  warn  = colors.yellow,
  error = colors.red,
}

--- Crée un logger.
-- @param opts table { path = "CC_Radio.log", level = "info", toTerm = true }
function Logger.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Logger)
  self.path   = opts.path or "CC_Radio.log"
  self.level  = LEVELS[opts.level or "info"] or LEVELS.info
  self.toTerm = opts.toTerm ~= false -- défaut : true
  return self
end

function Logger:setLevel(level)
  self.level = LEVELS[level] or self.level
end

function Logger:_write(level, msg)
  if (LEVELS[level] or LEVELS.info) < self.level then return end
  local stamp = textutils.formatTime(os.time(), true)
  local line  = string.format("[%s] [%s] %s", stamp, level:upper(), tostring(msg))

  local f = fs.open(self.path, "a")
  if f then f.writeLine(line); f.close() end

  if self.toTerm then
    if term.isColor() then
      local prev = term.getTextColor()
      term.setTextColor(COLORS[level] or colors.white)
      print(line)
      term.setTextColor(prev)
    else
      print(line)
    end
  end
end

function Logger:debug(m) self:_write("debug", m) end
function Logger:info(m)  self:_write("info",  m) end
function Logger:warn(m)  self:_write("warn",  m) end
function Logger:error(m) self:_write("error", m) end

return Logger
