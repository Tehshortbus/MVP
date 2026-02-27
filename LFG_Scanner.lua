-- MVP - LFG_Scanner.lua
-- Uses LFGBrowseFrameScrollBox.ScrollTarget children (confirmed working v0.2.8 path).
-- Tooltip anchors to the RIGHT of GameTooltip, not overlapping it.
-- Scan loop only re-hooks when child count changes (performance).
local addonName, MVP = ...
MVP.LFG_Scanner = MVP.LFG_Scanner or {}
local Scanner = MVP.LFG_Scanner

Scanner._isHooked       = false
Scanner._updateThrottle = 0
Scanner.UPDATE_INTERVAL = 0.5
Scanner._hookedEntries  = {}
Scanner._nameCache      = {}
Scanner._lastChildCount = -1

-- ─── MVP Tooltip ──────────────────────────────────────────────────────────────

local MVPTip = nil
local function GetMVPTip()
  if MVPTip then return MVPTip end
  MVPTip = CreateFrame("GameTooltip", "MVP_LFGTooltip", UIParent, "GameTooltipTemplate")
  MVPTip:SetFrameStrata("TOOLTIP")
  MVPTip:SetClampedToScreen(true)
  return MVPTip
end

local TIER_HEX = {
  Hated="cc3333", Hostile="e64d33", Unfriendly="e67f33", Neutral="9e9e9e",
  Friendly="33b233", Honored="33cc66", Revered="4d99e6", Exalted="ff8000",
}

local function addPlayerLine(tip, playerKey, isLeader)
  local agg   = MVP.Data:GetPlayerAgg(playerKey)
  local isFav = MVPConfig and MVPConfig.favorites and MVPConfig.favorites[playerKey]
  local star  = isLeader and "|cffFFD100*|r " or "  "

  if not agg or (agg.total or 0) == 0 then
    tip:AddLine(star.."|cffffffff"..playerKey.."|r  |cff666666no data|r")
    return
  end

  local rep  = agg.rep or ((agg.pos or 0) - (agg.neg or 0))
  local tier = agg.tier or MVP.Data:ReputationTier(rep)
  local sign = rep >= 0 and "+" or ""
  local fav  = isFav and " |cffFFD100[Fav]|r" or ""

  tip:AddDoubleLine(
    star.."|cffffffff"..playerKey.."|r"..fav,
    "|cff"..(TIER_HEX[tier] or "9e9e9e")..tier.." "..sign..rep..
    "|r  |cff66ff66+"..(agg.pos or 0)..
    "|r|cff888888/|r|cffff6666-"..(agg.neg or 0).."|r",
    1,1,1, 1,1,1)

  local topNK, topNV = MVP.Data:GetTopReason(agg.negReasons)
  if topNK and topNV and topNV > 0 and
     (tier=="Hated" or tier=="Hostile" or tier=="Unfriendly") then
    local lbl = MVP.Data.NEG_REASONS[topNK] or MVP.Data:GetReasonLabel(topNK, true)
    tip:AddLine("   |cffff6666! "..lbl.." ("..topNV..")|r")
  end
end

local function positionMVPTip()
  local tip = GetMVPTip()
  tip:ClearAllPoints()
  -- Anchor centered just below the bottom of the LFG frame
  if LFGBrowseFrame then
    tip:SetPoint("TOP", LFGBrowseFrame, "BOTTOM", 0, -4)
    return
  end
  tip:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
end

local function showMVPTooltip(entry, playerKey)
  local tip = GetMVPTip()
  tip:ClearLines()
  tip:SetOwner(UIParent, "ANCHOR_NONE")
  tip:AddLine("|cff33ff99MVP|r")
  addPlayerLine(tip, playerKey, false)
  tip:Show()
  positionMVPTip()
end

-- ─── Name extraction (v0.2.8 approach) ───────────────────────────────────────

local function extractPlayerName(entry)
  if entry.Name then
    if type(entry.Name) == "table" and entry.Name.GetText then
      local t = entry.Name:GetText()
      if t and t ~= "" then return t:match("^(%S+)") end
    elseif type(entry.Name) == "string" and entry.Name ~= "" then
      return entry.Name:match("^(%S+)")
    end
  end
  if entry.name and type(entry.name) == "string" and entry.name ~= "" then
    return entry.name:match("^(%S+)")
  end
  for _, child in pairs({entry:GetRegions()}) do
    if child:GetObjectType() == "FontString" then
      local text = child:GetText()
      if text and text ~= ""
         and not text:match("^%d")
         and not text:match("^Lv")
         and not text:match("Members")
         and not text:match("Roles")
         and not text:match("%(") then
        return text:match("^(%S+)")
      end
    end
  end
  return nil
end

-- ─── Hook a single entry ─────────────────────────────────────────────────────

function Scanner:HookEntry(entry)
  if self._hookedEntries[entry] then return end
  self._hookedEntries[entry] = true

  entry:HookScript("OnEnter", function(self_entry)
    -- Always re-extract: scroll reuses frames with new player data
    local raw = extractPlayerName(self_entry)
    local playerKey = nil
    if raw then
      local k = MVP.Util.NormalizePlayerKey(raw)
      if k and k ~= "" and k ~= "Unknown" then
        playerKey = k
      end
    end
    if playerKey then showMVPTooltip(self_entry, playerKey) end
  end)

  entry:HookScript("OnLeave", function()
    if MVPTip then MVPTip:Hide() end
  end)
end

-- ─── Scan loop ────────────────────────────────────────────────────────────────

function Scanner:ScanLFGFrame()
  if not LFGBrowseFrame or not LFGBrowseFrame:IsVisible() then return end

  local scrollBox = LFGBrowseFrameScrollBox
  if not scrollBox or not scrollBox.ScrollTarget then return end

  local children = { scrollBox.ScrollTarget:GetChildren() }

  -- Cheap change hash: count of visible children + identity of first visible one
  -- This catches both list length changes AND scroll position changes
  local visCount = 0
  local firstId  = 0
  for _, child in ipairs(children) do
    if child:IsVisible() and child:GetHeight() > 10 then
      visCount = visCount + 1
      if firstId == 0 then firstId = child:GetBottom() or 0 end
    end
  end
  local hash = visCount * 100000 + math.floor(firstId)

  if hash == self._lastChildCount then return end
  self._lastChildCount = hash

  for _, child in ipairs(children) do
    if child:IsVisible() and child:GetHeight() > 10 then
      self:HookEntry(child)
    end
  end
end

-- ─── OnUpdate (throttled) ────────────────────────────────────────────────────

function Scanner:OnUpdate(elapsed)
  self._updateThrottle = (self._updateThrottle or 0) + elapsed
  if self._updateThrottle < self.UPDATE_INTERVAL then return end
  self._updateThrottle = 0
  self:ScanLFGFrame()
end

-- ─── Init ─────────────────────────────────────────────────────────────────────

function Scanner:Init()
  if self._isHooked then return end
  if not LFGBrowseFrame then
    MVP.Util.DebugPrint("LFG Scanner: LFGBrowseFrame not found, deferring init")
    return false
  end

  self._frame = CreateFrame("Frame")
  self._frame:Hide()
  self._frame:SetScript("OnUpdate", function(_, elapsed)
    Scanner:OnUpdate(elapsed)
  end)

  LFGBrowseFrame:HookScript("OnShow", function()
    Scanner._lastChildCount = -1   -- force rescan on next tick
    Scanner._frame:Show()
    Scanner:ScanLFGFrame()
  end)

  LFGBrowseFrame:HookScript("OnHide", function()
    Scanner._frame:Hide()
    if MVPTip then MVPTip:Hide() end
    wipe(Scanner._nameCache)
    wipe(Scanner._hookedEntries)
    Scanner._lastChildCount = -1
  end)

  if LFGBrowseFrame:IsVisible() then
    self._frame:Show()
    self:ScanLFGFrame()
  end

  self._isHooked = true
  MVP.Util.DebugPrint("LFG Scanner: Initialized")
  return true
end

function Scanner:DelayedInit()
  if self._isHooked then return end
  if self:Init() then return end
  if C_Timer and C_Timer.After then
    C_Timer.After(2, function() Scanner:DelayedInit() end)
  end
end
