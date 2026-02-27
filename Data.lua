-- MVP - Data.lua
local addonName, MVP = ...
MVP.Data = MVP.Data or {}
local Data = MVP.Data

-- Reputation tier colors (approximate WoW-style and per reference image)
Data.REP_COLORS = {
  Hated      = { r = 0.70, g = 0.00, b = 0.00 }, -- dark red
  Hostile    = { r = 1.00, g = 0.00, b = 0.00 }, -- red
  Unfriendly = { r = 1.00, g = 0.55, b = 0.00 }, -- orange
  Neutral    = { r = 1.00, g = 0.92, b = 0.00 }, -- yellow
  Friendly   = { r = 0.00, g = 1.00, b = 0.00 }, -- green
  Honored    = { r = 0.45, g = 1.00, b = 0.45 }, -- light green
  Revered    = { r = 0.20, g = 0.95, b = 0.95 }, -- teal
  Exalted    = { r = 0.55, g = 1.00, b = 1.00 }, -- cyan
}

function Data:ReputationColor(tier)
  local c = Data.REP_COLORS[tostring(tier or "Neutral")] or Data.REP_COLORS.Neutral
  return c.r, c.g, c.b
end

function Data:ReputationColorHex(tier)
  local r, g, b = self:ReputationColor(tier)
  return string.format("%02x%02x%02x", math.floor(r*255 + 0.5), math.floor(g*255 + 0.5), math.floor(b*255 + 0.5))
end

Data.NEG_REASONS = {
  ["LOW_PARTICIPATION"] = "Low Participation/Situational Awareness",
  ["UNSKILLED_PLAYER"] = "Unskilled Player",
  ["LEAVER_AFK_DC"] = "Leaver / DC",
  ["TOXIC_COMMUNICATION"] = "Toxic Communication",
  ["GRIEFING_PULLS"] = "Griefing",
  ["NINJA_LOOTER"] = "*** Ninja Looter ***",
}

Data.POS_REASONS = {
  ["FAIR_LOOT"] = "Fair / Respected Loot Rules",
  ["SKILLED_PLAYER"] = "Skilled Player",
  ["POSITIVE_COMM"] = "Good Communication",
  ["CLEAN_PULLS"] = "Clean Pulls / Good Pace",
  ["RELIABLE"] = "Reliable / Stuck With Group",
}

Data.ROLES = { "TANK", "HEALER", "DPS" }
Data.ROLE_LABELS = { TANK="Tank", HEALER="Healer", DPS="DPS" }

-- Helper function to get a readable label for a reason code
function Data:GetReasonLabel(reasonCode, isNegative)
  if not reasonCode then return "Unknown" end
  
  local reasonTable = isNegative and Data.NEG_REASONS or Data.POS_REASONS
  local label = reasonTable[reasonCode]
  
  -- If we have a label, use it
  if label then return label end
  
  -- Otherwise, format the code nicely (convert SNAKE_CASE to Title Case)
  local formatted = reasonCode:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest)
    return first:upper() .. rest:lower()
  end)
  
  return formatted
end

local function ensureTables()
  MVPDB = MVPDB or {}
  MVPDB.vouches = MVPDB.vouches or {}         -- [vouchId] = record
  MVPDB.players = MVPDB.players or {}         -- [playerKey] = aggregates
  MVPDB.meta = MVPDB.meta or { lastTs = 0, submissions = {} }   -- track latest timestamp we've stored
end

function Data:Init()
  ensureTables()
  self:_migrateVouches()
  self:_migrateReasonCodes()
  self:_cleanupOldVouches()
  self:_cleanupUnknownVouches()
end

-- Cleanup: Remove any vouches recorded for "Unknown" players (caused by too-fast roster lookup)
function Data:_cleanupUnknownVouches()
  if not MVPDB or not MVPDB.vouches then return end
  local deleted = 0
  for id, rec in pairs(MVPDB.vouches) do
    if rec then
      local targetIsUnknown = (rec.target == "Unknown" or rec.target == "" or rec.target == nil)
      local raterIsUnknown  = (rec.rater  == "Unknown" or rec.rater  == "" or rec.rater  == nil)
      if targetIsUnknown or raterIsUnknown then
        MVPDB.vouches[id] = nil
        deleted = deleted + 1
      end
    end
  end
  -- Rebuild player aggregates if we removed anything
  if deleted > 0 then
    MVP.Util.DebugPrint(("Removed %d vouch(es) for Unknown players"):format(deleted))
    self:_rebuildAgg()
  end
end

-- Cleanup: Delete vouches older than 100 days (except ninja looter)
function Data:_cleanupOldVouches()
  if not MVPDB or not MVPDB.vouches then return end

  local now = MVP.Util.Now()
  local cutoffAge = 100 * 86400  -- 100 days in seconds
  local deleted = 0
  local kept = 0

  for id, rec in pairs(MVPDB.vouches) do
    if rec and rec.ts then
      local age = now - rec.ts
      if age >= cutoffAge then
        -- Only keep ninja looter vouches past 100 days
        if rec.reason == "NINJA_LOOTER" then
          kept = kept + 1
        else
          MVPDB.vouches[id] = nil
          deleted = deleted + 1
        end
      end
    end
  end

  if deleted > 0 or kept > 0 then
    MVP.Util.DebugPrint(string.format("Decay cleanup: deleted %d old vouches, kept %d ninja looter marks", deleted, kept))
    self:_rebuildAgg()
  end
end

-- Migration: mark old vouches (without isLocal or sources) as legacy trusted
function Data:_migrateVouches()
  if not MVPDB or not MVPDB.vouches then return end

  local migrated = 0
  for id, rec in pairs(MVPDB.vouches) do
    -- If vouch has no isLocal flag and no sources, it's from before source tracking
    if rec and not rec.isLocal and (not rec.sources or next(rec.sources) == nil) and not rec.legacy then
      rec.legacy = true
      migrated = migrated + 1
    end
  end

  if migrated > 0 then
    MVP.Util.DebugPrint(string.format("Migrated %d legacy vouches to trusted status", migrated))
    self:_rebuildAgg()
  end
end

-- Migration: fix old reason codes to match current reason keys
function Data:_migrateReasonCodes()
  if not MVPDB or not MVPDB.vouches then return end

  -- Mapping of old reason codes to new ones
  local reasonMigrations = {
    -- Old negative reasons that need updating
    ["AFK_LOW_PARTICIPATION"] = "LOW_PARTICIPATION",
    ["WOW_PAWTICIPATION"] = "LOW_PARTICIPATION",  -- Typo from old version
    ["MULTIPLE_AFKS"] = "UNSKILLED_PLAYER",
    ["GWIEFING_PUWWS"] = "GRIEFING_PULLS",  -- Typo from old version
    
    -- Old positive reasons that need updating
    ["HIGH_PARTICIPATION"] = "SKILLED_PLAYER",
    ["WEWIABWE"] = "RELIABLE",  -- Typo from old version
  }

  local migrated = 0
  for id, rec in pairs(MVPDB.vouches) do
    if rec and rec.reason then
      local newReason = reasonMigrations[rec.reason]
      if newReason then
        rec.reason = newReason
        migrated = migrated + 1
      end
    end
  end

  if migrated > 0 then
    MVP.Util.DebugPrint(string.format("Migrated %d vouch reason codes to current version", migrated))
    self:_rebuildAgg()
  end
end

function Data:MakeVouchId(rec)
  -- Stable per (rater,target,run). This prevents spam/duplicates for the same run.
  local base = table.concat({ rec.rater or "", rec.target or "", rec.runId or "" }, "|")
  return MVP.Util.FNV1aHex(base)
end


function Data:_notifyChanged()
  -- placeholder hook (UI refresh is done by callers). Kept for future.
end

function Data:_countSources(rec)
  -- Count how many independent sources confirmed this vouch
  if not rec.sources then return 0 end
  local count = 0
  for _ in pairs(rec.sources) do
    count = count + 1
  end
  return count
end

-- Calculate decay weight for a vouch based on age
-- 1% per day decay, floor at 10% for ninja looter, 0% for everything else at 100+ days
function Data:_getDecayWeight(rec)
  if not rec or not rec.ts then return 1.0 end

  local now = MVP.Util.Now()
  local ageInSeconds = now - (rec.ts or now)
  local ageInDays = ageInSeconds / 86400  -- 86400 seconds per day

  -- 1% decay per day
  local weight = 1.0 - (ageInDays * 0.01)

  -- At 100+ days: ninja looter gets 10% floor, everything else goes to 0
  if ageInDays >= 100 then
    if rec.reason == "NINJA_LOOTER" then
      return 0.10  -- Ninja looters never escape
    else
      return 0  -- Everything else stops counting
    end
  end

  -- Before 100 days, minimum is based on current decay
  return math.max(0, weight)
end

function Data:_isVouchTrusted(rec)
  -- A vouch is trusted if:
  -- 1. It was created locally (we trust our own vouches)
  -- 2. OR it's a legacy vouch (existed before source tracking was added)
  -- 3. OR it has 1+ independent sources (lowered from 2 for testing)
  if rec.isLocal then return true end
  if rec.legacy then return true end
  return self:_countSources(rec) >= 1
end

function Data:_rebuildAgg()
  -- Recompute aggregates from MVPDB.vouches (used on updates/wipes/imports).
  ensureTables()
  MVPDB.players = {}

  local totalVouches, trustedVouches, untrustedVouches = 0, 0, 0

  for _, rec in pairs(MVPDB.vouches) do
    if rec then
      if rec.target then rec.target = MVP.Util.NormalizePlayerKey(rec.target) end
      if rec.rater then rec.rater = MVP.Util.NormalizePlayerKey(rec.rater) end
    end
    -- ApplyVouch expects normalized/validated data; do minimal guard here.
    if rec and rec.target and rec.target ~= "" and rec.role and (rec.role=="TANK" or rec.role=="HEALER" or rec.role=="DPS") then
      totalVouches = totalVouches + 1

      -- Always preserve class info even for untrusted vouches
      local agg = self:_ensurePlayerAgg(rec.target)
      if rec.targetClass and rec.targetClass ~= "" then
        agg.classFile = rec.targetClass
      end

      -- ANTI-FRAUD: Only count vouches that are trusted (local or 2+ sources)
      if not self:_isVouchTrusted(rec) then
        -- Skip untrusted vouches in aggregates (but we already stored class above)
        untrustedVouches = untrustedVouches + 1
      else
        -- Get decay weight based on vouch age
        local weight = self:_getDecayWeight(rec)

        -- Skip vouches that have fully decayed (weight = 0)
        if weight > 0 then
          trustedVouches = trustedVouches + 1
          agg.total = (agg.total or 0) + weight
          if rec.sign and rec.sign < 0 then
            agg.neg = (agg.neg or 0) + weight
            self:_incReasonWeighted(agg.negReasons, rec.reason, weight)
          else
            agg.pos = (agg.pos or 0) + weight
            self:_incReasonWeighted(agg.posReasons, rec.reason, weight)
          end
          agg.lastSeen = math.max(agg.lastSeen or 0, rec.ts or 0)

          local roleAgg = agg.roles[rec.role]
          if roleAgg then
            roleAgg.total = (roleAgg.total or 0) + weight
            if rec.sign and rec.sign < 0 then
              roleAgg.neg = (roleAgg.neg or 0) + weight
              self:_incReasonWeighted(roleAgg.negReasons, rec.reason, weight)
            else
              roleAgg.pos = (roleAgg.pos or 0) + weight
              self:_incReasonWeighted(roleAgg.posReasons, rec.reason, weight)
            end
          end
        end
      end
    end
  end

  -- Debug output for source tracking
  if untrustedVouches > 0 then
    MVP.Util.DebugPrint(string.format("Source tracking: %d total, %d trusted, %d pending verification", totalVouches, trustedVouches, untrustedVouches))
  end

  -- compute net reputation + tier (round to 1 decimal for display)
  for _, agg in pairs(MVPDB.players) do
    agg.pos = math.floor((agg.pos or 0) * 10 + 0.5) / 10
    agg.neg = math.floor((agg.neg or 0) * 10 + 0.5) / 10
    agg.total = math.floor((agg.total or 0) * 10 + 0.5) / 10
    agg.rep = agg.pos - agg.neg
    if Data.ReputationTier then
      agg.tier = Data:ReputationTier(agg.rep)
    end
    -- Round role aggregates too
    for _, roleAgg in pairs(agg.roles or {}) do
      roleAgg.pos = math.floor((roleAgg.pos or 0) * 10 + 0.5) / 10
      roleAgg.neg = math.floor((roleAgg.neg or 0) * 10 + 0.5) / 10
      roleAgg.total = math.floor((roleAgg.total or 0) * 10 + 0.5) / 10
    end
  end
end

function Data:_ensurePlayerAgg(playerKey)
  local p = MVPDB.players[playerKey]
  if not p then
    p = {
      total = 0,
      pos = 0,
      neg = 0,
      roles = {
        TANK = { total = 0, pos = 0, neg = 0, negReasons = {}, posReasons = {} },
        HEALER = { total = 0, pos = 0, neg = 0, negReasons = {}, posReasons = {} },
        DPS = { total = 0, pos = 0, neg = 0, negReasons = {}, posReasons = {} },
      },
      negReasons = {},
      posReasons = {},
      lastSeen = 0,
    }
    MVPDB.players[playerKey] = p
  end
  return p
end

function Data:_incReason(map, key)
  if not key or key == "" then return end
  map[key] = (map[key] or 0) + 1
end

function Data:_incReasonWeighted(map, key, weight)
  if not key or key == "" then return end
  map[key] = (map[key] or 0) + weight
end

function Data:ApplyVouch(rec, isLocal)
  ensureTables()
  if not rec or not rec.id then return false end

  -- ANTI-FRAUD: Reject self-vouches (people can't vouch for themselves)
  local raterNorm = MVP.Util.NormalizePlayerKey(rec.rater)
  local targetNorm = MVP.Util.NormalizePlayerKey(rec.target)
  if raterNorm and targetNorm and raterNorm == targetNorm then
    MVP.Util.DebugPrint("Rejected self-vouch from", rec.rater)
    return false
  end

  local existing = MVPDB.vouches[rec.id]
  if existing then
    -- Merge sources from incoming vouch into existing
    -- SCALE: Cap at 10 sources - once trusted, we don't need more confirmations
    if rec.sources then
      existing.sources = existing.sources or {}
      local sourceCount = 0
      for _ in pairs(existing.sources) do sourceCount = sourceCount + 1 end
      if sourceCount < 10 then
        for src, _ in pairs(rec.sources) do
          if sourceCount >= 10 then break end
          if not existing.sources[src] then
            existing.sources[src] = true
            sourceCount = sourceCount + 1
          end
        end
      end
    end
    -- Update-in-place if anything changed; prevents duplicate spam while allowing correction.
    local changed = false
    for _, k in ipairs({ "ts","role","sign","reason","runId" }) do
      if existing[k] ~= rec[k] then changed = true break end
    end
    if not changed then
      -- Even if content didn't change, sources might have - rebuild to update trust
      self:_rebuildAgg()
      return false
    end
    -- Preserve sources and isLocal flags
    rec.sources = existing.sources
    rec.isLocal = existing.isLocal or rec.isLocal
    MVPDB.vouches[rec.id] = rec
    MVPDB.meta.lastTs = math.max(MVPDB.meta.lastTs or 0, rec.ts or 0)
    self:_rebuildAgg()
    return false
  end

  -- Mark as local if created by this player
  if isLocal then
    rec.isLocal = true
  end
  -- Initialize sources table
  rec.sources = rec.sources or {}

  MVPDB.vouches[rec.id] = rec
  MVPDB.meta.lastTs = math.max(MVPDB.meta.lastTs or 0, rec.ts or 0)

  -- Update target aggregates
  local agg = self:_ensurePlayerAgg(rec.target)
  agg.total = (agg.total or 0) + 1
  if rec.sign and rec.sign < 0 then
    agg.neg = (agg.neg or 0) + 1
    self:_incReason(agg.negReasons, rec.reason)
  else
    agg.pos = (agg.pos or 0) + 1
    self:_incReason(agg.posReasons, rec.reason)
  end
  agg.lastSeen = math.max(agg.lastSeen or 0, rec.ts or 0)

  -- Store class if provided
  if rec.targetClass and rec.targetClass ~= "" then
    agg.classFile = rec.targetClass
  end

  local roleAgg = agg.roles[rec.role]
  if roleAgg then
    roleAgg.total = (roleAgg.total or 0) + 1
    if rec.sign and rec.sign < 0 then
      roleAgg.neg = (roleAgg.neg or 0) + 1
      self:_incReason(roleAgg.negReasons, rec.reason)
    else
      roleAgg.pos = (roleAgg.pos or 0) + 1
      self:_incReason(roleAgg.posReasons, rec.reason)
    end
  end

  -- Keep derived reputation fields current
  agg.rep = (agg.pos or 0) - (agg.neg or 0)
  agg.tier = self:ReputationTier(agg.rep)

  return true
end

-- Import from a sync message parts:
-- Old format (v1): V|id|ts|rater|target|role|sign|reason|runId (9 parts)
-- New format (v2): V|id|ts|rater|target|targetClass|role|sign|reason|runId (10 parts)
function Data:ImportVouch(parts, sender)
  if #parts < 9 then return false end

  -- Normalize sender name (strip realm)
  local senderNorm = MVP.Util.NormalizePlayerKey(sender)

  local rec
  if #parts >= 10 then
    -- New format with targetClass
    rec = {
      id = parts[2],
      ts = tonumber(parts[3] or "0") or 0,
      rater = parts[4],
      target = parts[5],
      targetClass = parts[6] ~= "" and parts[6] or nil,
      role = parts[7],
      sign = tonumber(parts[8] or "0") or 0,
      reason = parts[9],
      runId = parts[10],
      src = sender,
      ver = 2,
    }
  else
    -- Old format without targetClass (backwards compatibility)
    rec = {
      id = parts[2],
      ts = tonumber(parts[3] or "0") or 0,
      rater = parts[4],
      target = parts[5],
      role = parts[6],
      sign = tonumber(parts[7] or "0") or 0,
      reason = parts[8],
      runId = parts[9],
      src = sender,
      ver = 1,
    }
  end

  -- Basic validation
  if not rec.id or rec.id == "" then return false end
  if not rec.target or rec.target == "" then return false end
  if rec.sign < 0 and (not rec.reason or rec.reason == "") then
    return false
  end
  if rec.role ~= "TANK" and rec.role ~= "HEALER" and rec.role ~= "DPS" then
    return false
  end

  -- ANTI-FRAUD: Track source of this vouch
  -- Each sender who sends us the same vouch ID is an independent source
  -- (capped at 10 sources per vouch to prevent memory bloat at scale)
  rec.sources = { [senderNorm] = true }

  local isNew = self:ApplyVouch(rec, false)

  if MVP.UI_DB and MVP.UI_DB.RefreshIfOpen then
    MVP.UI_DB:RefreshIfOpen()
  end

  return isNew
end

function Data:GetPlayerAgg(playerKey)
  playerKey = MVP.Util.NormalizePlayerKey(playerKey)
  if not MVPDB or not MVPDB.players then return nil end
  if not MVPDB.players[playerKey] and MVPDB.vouches and next(MVPDB.vouches) then
    -- if DB was upgraded and players table is stale, rebuild aggregates
    self:_rebuildAgg()
  end
  return MVPDB.players[playerKey]
end

function Data:SearchPlayers(query, roleFilter)
  ensureTables()
  query = MVP.Util.Trim(query or ""):lower()
  roleFilter = roleFilter or "ALL"
  local results = {}

  for k, agg in pairs(MVPDB.players) do
    if query == "" or k:lower():find(query, 1, true) then
      if roleFilter == "ALL" then
        results[#results+1] = { key = k, agg = agg }
      else
        local ra = agg.roles and agg.roles[roleFilter]
        if ra and (ra.total or 0) > 0 then
          results[#results+1] = { key = k, agg = agg }
        end
      end
    end
  end

  table.sort(results, function(a, b)
    local an = a and a.agg and (a.agg.neg or 0) or 0
    local bn = b and b.agg and (b.agg.neg or 0) or 0
    return an > bn
  end)
  return results
end

function Data:TopReason(map)
  if not map then return nil, 0 end
  local bestK, bestV = nil, 0
  for k, v in pairs(map) do
    if v > bestV then
      bestK, bestV = k, v
    end
  end
  return bestK, bestV
end

function MVP.Data:Wipe()
  MVPDB = { vouches = {}, players = {}, meta = { lastTs = 0, submissions = {} } }
  ensureTables()
  self:_rebuildAgg()
  self:_notifyChanged()
end



-- Reputation tier mapping based on net reputation score (pos - neg)
function MVP.Data:ReputationTier(rep)
  rep = tonumber(rep or 0) or 0
  if rep <= -80 then return "Hated" end
  if rep <= -60 then return "Hostile" end
  if rep <= -20 then return "Unfriendly" end
  if rep < 20 then return "Neutral" end
  if rep < 60 then return "Friendly" end
  if rep < 80 then return "Honored" end
  if rep < 100 then return "Revered" end
  return "Exalted"
end

function Data:ReputationTier(rep)
  rep = tonumber(rep or 0) or 0
  if rep <= -80 then return "Hated" end
  if rep <= -60 then return "Hostile" end
  if rep <= -20 then return "Unfriendly" end
  if rep < 20 then return "Neutral" end
  if rep < 60 then return "Friendly" end
  if rep < 80 then return "Honored" end
  if rep < 100 then return "Revered" end
  return "Exalted"
end

function Data:GetTopReason(reasonMap)
  if not reasonMap then return nil, 0 end
  local bestK, bestV = nil, 0
  for k, v in pairs(reasonMap) do
    if v and v > bestV then
      bestK, bestV = k, v
    end
  end
  return bestK, bestV
end

-- Get statistics about source tracking for anti-fraud
function Data:GetSourceTrackingStats()
  ensureTables()
  local stats = {
    total = 0,
    trusted = 0,
    untrusted = 0,
    local_vouches = 0,
    legacy_vouches = 0,
    multi_source = 0,
    single_source = 0,
    no_source = 0,
  }

  for _, rec in pairs(MVPDB.vouches) do
    if rec and rec.target and rec.target ~= "" then
      stats.total = stats.total + 1
      if self:_isVouchTrusted(rec) then
        stats.trusted = stats.trusted + 1
        if rec.isLocal then
          stats.local_vouches = stats.local_vouches + 1
        elseif rec.legacy then
          stats.legacy_vouches = stats.legacy_vouches + 1
        else
          stats.multi_source = stats.multi_source + 1
        end
      else
        stats.untrusted = stats.untrusted + 1
        local srcCount = self:_countSources(rec)
        if srcCount == 0 then
          stats.no_source = stats.no_source + 1
        else
          stats.single_source = stats.single_source + 1
        end
      end
    end
  end

  return stats
end

-- Print source tracking stats to chat
function Data:PrintSourceStats()
  local s = self:GetSourceTrackingStats()
  print("|cff33ff99MVP|r Source Tracking Statistics:")
  print(string.format("  Total vouches: %d", s.total))
  print(string.format("  Trusted: %d (local: %d, legacy: %d, multi-source: %d)", s.trusted, s.local_vouches, s.legacy_vouches, s.multi_source))
  print(string.format("  Pending verification: %d (single: %d, none: %d)", s.untrusted, s.single_source, s.no_source))
end
