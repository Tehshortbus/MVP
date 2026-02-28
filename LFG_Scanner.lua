-- MVP - LFG_Scanner.lua
-- Event-driven: hooks entries when search results arrive.
-- OnUpdate only runs briefly after results load, then stops.
local addonName, MVP = ...
MVP.LFG_Scanner = MVP.LFG_Scanner or {}
local Scanner = MVP.LFG_Scanner

Scanner._isHooked      = false
Scanner._hookedEntries = {}

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

local function addPlayerLine(tip, playerKey)
  local agg   = MVP.Data:GetPlayerAgg(playerKey)
  local isFav = MVPConfig and MVPConfig.favorites and MVPConfig.favorites[playerKey]

  if not agg or (agg.total or 0) == 0 then
    tip:AddLine("|cffffffff"..playerKey.."|r  |cff666666no data|r")
    return
  end

  local rep  = agg.rep or ((agg.pos or 0) - (agg.neg or 0))
  local tier = agg.tier or MVP.Data:ReputationTier(rep)
  local fav  = isFav and " |cffFFD100[Fav]|r" or ""

  tip:AddDoubleLine(
    "|cffffffff"..playerKey.."|r"..fav,
    "|cff"..(TIER_HEX[tier] or "9e9e9e")..tier
      ..(rep >= 0 and " +" or " ")..rep
      .."|r  |cff66ff66+"..(agg.pos or 0)
      .."|r|cff888888/|r|cffff6666-"..(agg.neg or 0).."|r",
    1,1,1, 1,1,1)

  local topNK, topNV = MVP.Data:GetTopReason(agg.negReasons)
  if topNK and topNV and topNV > 0 and
     (tier=="Hated" or tier=="Hostile" or tier=="Unfriendly") then
    local lbl = MVP.Data.NEG_REASONS[topNK] or topNK
    tip:AddLine("   |cffff6666! "..lbl.." ("..topNV..")|r")
  end
end

local function showMVPTooltip(playerKey)
  local tip = GetMVPTip()
  tip:ClearLines()
  tip:SetOwner(UIParent, "ANCHOR_NONE")
  tip:AddLine("|cff33ff99MVP|r")
  addPlayerLine(tip, playerKey)
  tip:Show()
  tip:ClearAllPoints()
  if LFGBrowseFrame then
    tip:SetPoint("TOP", LFGBrowseFrame, "BOTTOM", 0, -4)
  else
    tip:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
  end
end

-- ─── Name extraction ─────────────────────────────────────────────────────────

local function extractPlayerName(entry)
  if entry.Name then
    local n = entry.Name
    if type(n) == "table" and n.GetText then
      local t = n:GetText()
      if t and t ~= "" then return t:match("^(%S+)") end
    elseif type(n) == "string" and n ~= "" then
      return n:match("^(%S+)")
    end
  end
  if type(entry.name) == "string" and entry.name ~= "" then
    return entry.name:match("^(%S+)")
  end
  for _, region in ipairs({entry:GetRegions()}) do
    if region:GetObjectType() == "FontString" then
      local text = region:GetText()
      if text and text ~= ""
         and not text:match("^%d")
         and not text:match("^Lv")
         and not text:match("Members")
         and not text:match("Roles")
         and not text:match("activities")
         and not text:match("%(") then
        local word = text:match("^(%S+)")
        if word and #word >= 2 then return word end
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
    local raw = extractPlayerName(self_entry)
    if not raw then return end
    local k = MVP.Util.NormalizePlayerKey(raw)
    if k and k ~= "" and k ~= "Unknown" then
      showMVPTooltip(k)
    end
  end)

  entry:HookScript("OnLeave", function()
    if MVPTip then MVPTip:Hide() end
  end)
end

-- ─── Scan ScrollTarget for unhookedvisible entries ───────────────────────────

function Scanner:ScanScrollTarget(scrollTarget)
  if not scrollTarget then return 0 end
  local count = 0
  for _, child in ipairs({scrollTarget:GetChildren()}) do
    if child:IsVisible() and child:GetHeight() > 10 then
      if not self._hookedEntries[child] then
        self:HookEntry(child)
        count = count + 1
      end
    end
  end
  return count
end

-- Scan the primary scroll box (Group Browser)
function Scanner:ScanPrimary()
  local sb = LFGBrowseFrameScrollBox
  if sb and sb.ScrollTarget then
    return self:ScanScrollTarget(sb.ScrollTarget)
  end
  return 0
end

-- ─── OnUpdate: runs briefly after results load, stops when done ──────────────

local SCAN_INTERVAL = 0.25
local MAX_SCAN_TIME = 3.0   -- stop scanning after 3s of no new entries

function Scanner:OnUpdate(elapsed)
  self._updateThrottle = (self._updateThrottle or 0) + elapsed
  if self._updateThrottle < SCAN_INTERVAL then return end
  self._updateThrottle = 0

  if not LFGBrowseFrame or not LFGBrowseFrame:IsVisible() then
    self._frame:Hide()
    return
  end

  local newlyHooked = self:ScanPrimary()

  if newlyHooked > 0 then
    -- Found new entries; reset the idle timer
    self._scanIdleTime = 0
  else
    -- No new entries this tick; count idle time
    self._scanIdleTime = (self._scanIdleTime or 0) + SCAN_INTERVAL
    if self._scanIdleTime >= MAX_SCAN_TIME then
      -- Been idle for 3s with no new entries - stop polling
      self._frame:Hide()
    end
  end
end

-- Wake the scanner back up (scroll, refresh, re-open)
function Scanner:WakeUp()
  self._scanIdleTime = 0
  self._updateThrottle = 0
  if self._frame then self._frame:Show() end
end

-- ─── Init ─────────────────────────────────────────────────────────────────────

function Scanner:Init()
  if self._isHooked then return end
  if not LFGBrowseFrame then return false end

  self._updateThrottle = 0
  self._scanIdleTime   = 0

  self._frame = CreateFrame("Frame")
  self._frame:Hide()
  self._frame:SetScript("OnUpdate", function(_, elapsed)
    Scanner:OnUpdate(elapsed)
  end)

  -- Wake on LFG open
  LFGBrowseFrame:HookScript("OnShow", function()
    -- Don't wipe hooks on show - entries persist across open/close
    Scanner:WakeUp()
  end)

  -- Stop tooltip on LFG close; keep hooks (entries are reused)
  LFGBrowseFrame:HookScript("OnHide", function()
    Scanner._frame:Hide()
    if MVPTip then MVPTip:Hide() end
  end)

  -- Wake on scroll (new entries become visible)
  -- Modern scroll bars use RegisterCallback, not HookScript
  local sb = _G["LFGBrowseFrameScrollBar"]
  if sb and sb.RegisterCallback then
    sb:RegisterCallback("OnScroll", function() Scanner:WakeUp() end, Scanner)
  end
  -- Also hook the scroll box itself
  local scrollBox = _G["LFGBrowseFrameScrollBox"]
  if scrollBox and scrollBox.RegisterCallback then
    pcall(function()
      scrollBox:RegisterCallback("OnScroll", function() Scanner:WakeUp() end, Scanner)
    end)
  end

  -- Wake on search results arriving
  local evtFrame = CreateFrame("Frame")
  evtFrame:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
  evtFrame:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
  evtFrame:SetScript("OnEvent", function()
    -- Short delay so Blizzard populates the frame first
    C_Timer.After(0.15, function() Scanner:WakeUp() end)
  end)

  -- If already open
  if LFGBrowseFrame:IsVisible() then
    self:WakeUp()
  end

  self._isHooked = true
  return true
end

function Scanner:DelayedInit()
  if self._isHooked then return end
  if self:Init() then return end
  if C_Timer and C_Timer.After then
    C_Timer.After(2, function() Scanner:DelayedInit() end)
  end
end
