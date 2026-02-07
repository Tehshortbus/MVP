-- MVP - Util.lua
local addonName, MVP = ...
MVP.Util = MVP.Util or {}

function MVP.Util.Trim(s)
  if not s then return "" end
  return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

function MVP.Util.Split(s, sep)
  sep = sep or "|"
  local t = {}
  if not s or s == "" then return t end
  -- split without pattern pitfalls
  local start = 1
  local sepLen = #sep
  while true do
    local i = string.find(s, sep, start, true)
    if not i then
      t[#t+1] = string.sub(s, start)
      break
    end
    t[#t+1] = string.sub(s, start, i-1)
    start = i + sepLen
  end
  return t
end

function MVP.Util.FNV1aHex(str)
  -- 32-bit FNV-1a
  local hash = 2166136261
  str = tostring(str or "")
  for i = 1, #str do
    hash = bit.bxor(hash, string.byte(str, i))
    hash = (hash * 16777619) % 4294967296
  end
  return string.format("%08x", hash)
end

function MVP.Util.Now()
  -- epoch seconds
  return time()
end

function MVP.Util.DebugPrint(...)
  if MVPConfig and MVPConfig.debug then
    print("|cff33ff99MVP|r", ...)
  end
end

function MVP.Util.NormalizePlayerKey(name)
  if not name then return nil end
  name = MVP.Util.Trim(name)
  if name == "" then return nil end
  local n = name:match("^(.-)%-")
  if n and n ~= "" then return n end
  return name
end

function MVP.Util.StripRealm(playerKey)
  return MVP.Util.NormalizePlayerKey(playerKey) or ""
end

function MVP.Util.PlayerKeyFromUnit(unit)
  if not unit or not UnitExists(unit) then return nil end
  local name = UnitName(unit)
  return MVP.Util.NormalizePlayerKey(name)
end
