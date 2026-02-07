-- MVP - LFG_Scanner.lua
-- Scans the LFG Browse frame and adds reputation indicators
local addonName, MVP = ...
MVP.LFG_Scanner = MVP.LFG_Scanner or {}
local Scanner = MVP.LFG_Scanner

-- Indicator pool (reuse frames to prevent memory leaks)
Scanner._indicators = {}
Scanner._indicatorPool = {}
Scanner._isHooked = false
Scanner._updateThrottle = 0
Scanner.UPDATE_INTERVAL = 0.25  -- seconds between scans

-- Create or get a pooled indicator frame
function Scanner:GetIndicator(parent)
  local indicator = table.remove(self._indicatorPool)

  if not indicator then
    indicator = CreateFrame("Frame", nil, parent)
    indicator:SetSize(18, 18)

    -- Background circle
    indicator.bg = indicator:CreateTexture(nil, "BACKGROUND")
    indicator.bg:SetAllPoints()
    indicator.bg:SetTexture("Interface\\COMMON\\Indicator-Gray")

    -- Icon overlay
    indicator.icon = indicator:CreateTexture(nil, "ARTWORK")
    indicator.icon:SetSize(14, 14)
    indicator.icon:SetPoint("CENTER")

    -- Tooltip
    indicator:EnableMouse(true)
    indicator:SetScript("OnEnter", function(self)
      if self.tooltipText then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
        GameTooltip:Show()
      end
    end)
    indicator:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
  end

  indicator:SetParent(parent)
  indicator:Show()
  return indicator
end

-- Return indicator to pool
function Scanner:ReleaseIndicator(indicator)
  indicator:Hide()
  indicator:SetParent(nil)
  indicator.tooltipText = nil
  table.insert(self._indicatorPool, indicator)
end

-- Release all active indicators
function Scanner:ReleaseAllIndicators()
  for _, indicator in pairs(self._indicators) do
    self:ReleaseIndicator(indicator)
  end
  self._indicators = {}
end

-- Get reputation tier color
function Scanner:GetTierColor(tier)
  if tier == "Hated" then return 0.8, 0.2, 0.2  -- Red
  elseif tier == "Hostile" then return 0.9, 0.3, 0.2
  elseif tier == "Unfriendly" then return 0.9, 0.5, 0.2  -- Orange
  elseif tier == "Neutral" then return 0.62, 0.62, 0.62  -- Poor gray (9d9d9d)
  elseif tier == "Friendly" then return 0.2, 0.7, 0.2  -- Green
  elseif tier == "Honored" then return 0.2, 0.8, 0.4  -- Brighter green
  elseif tier == "Revered" then return 0.3, 0.6, 0.9  -- Blue
  elseif tier == "Exalted" then return 1.0, 0.5, 0.0  -- Legendary orange (ff8000)
  end
  return 0.5, 0.5, 0.5
end

-- Check if tier is "bad" (warning-worthy)
function Scanner:IsBadTier(tier)
  return tier == "Hated" or tier == "Hostile" or tier == "Unfriendly"
end

-- Check if tier is "good" (noteworthy)
function Scanner:IsGoodTier(tier)
  return tier == "Revered" or tier == "Exalted"
end

-- Scan a single LFG entry and add indicator if needed
function Scanner:ScanEntry(entry, entryKey)
  -- Try to find the player name from the entry
  -- The entry structure may vary, so we try multiple approaches
  local playerName = nil

  -- Look for Name fontstring or similar
  if entry.Name then
    if type(entry.Name) == "table" and entry.Name.GetText then
      playerName = entry.Name:GetText()
    elseif type(entry.Name) == "string" then
      playerName = entry.Name
    end
  end

  -- Try other common patterns
  if not playerName and entry.name then
    playerName = entry.name
  end

  -- Try to find any fontstring that might have the name
  if not playerName then
    for _, child in pairs({entry:GetRegions()}) do
      if child:GetObjectType() == "FontString" then
        local text = child:GetText()
        if text and text ~= "" and not text:match("^%d") and not text:match("^Lv") and not text:match("Members") then
          playerName = text
          break
        end
      end
    end
  end

  if not playerName or playerName == "" then
    return
  end

  -- Strip level and other suffixes (e.g., "Simpin Lvl 60" -> "Simpin")
  playerName = playerName:match("^(%S+)") or playerName

  -- Normalize the name
  local playerKey = MVP.Util.NormalizePlayerKey(playerName)
  if not playerKey then return end

  -- Check MVPDB for this player
  local agg = MVP.Data:GetPlayerAgg(playerKey)
  local isFavorite = MVPConfig and MVPConfig.favorites and MVPConfig.favorites[playerKey]

  -- No data - show unknown indicator
  if not agg or (not agg.total or agg.total == 0) then
    local indicator = self._indicators[entryKey]
    if not indicator then
      indicator = self:GetIndicator(entry)
      self._indicators[entryKey] = indicator
    end

    indicator:ClearAllPoints()
    indicator:SetPoint("RIGHT", entry, "RIGHT", -5, 0)
    indicator:SetParent(entry)
    indicator:SetFrameLevel(entry:GetFrameLevel() + 10)

    -- Gray background for unknown
    indicator.bg:SetVertexColor(0.4, 0.4, 0.4, 0.7)

    -- Question mark icon (yellow tinted)
    indicator.icon:SetTexture("Interface\\GossipFrame\\IncompleteQuestIcon")
    indicator.icon:SetTexCoord(0, 1, 0, 1)
    indicator.icon:SetVertexColor(1.0, 0.82, 0)  -- Gold/yellow tint
    indicator.icon:Show()

    indicator.tooltipText = string.format("|cff33ff99MVP|r |cffffffff%s|r\n|cff888888No reputation data|r", playerKey)
    indicator:Show()
    return
  end

  local tier = agg.tier or MVP.Data:ReputationTier(agg.rep or 0)

  -- Determine if we should show an indicator
  local showIndicator = false
  local indicatorColor = {0.5, 0.5, 0.5}
  local tooltipText = ""

  -- Build nicely formatted tooltip
  local function buildTooltip(playerKey, agg, tier, isFav)
    local r, g, b = self:GetTierColor(tier)
    local tierHex = string.format("%02x%02x%02x", r*255, g*255, b*255)
    local lines = {}

    -- Header: MVP + Player name
    lines[#lines+1] = string.format("|cff33ff99MVP|r |cffffffff%s|r", playerKey)

    -- Favorite badge if applicable
    if isFav then
      lines[#lines+1] = "|cffFFD100Favorite|r"
    end

    -- Reputation line: Tier (score)
    local repSign = (agg.rep or 0) >= 0 and "+" or ""
    lines[#lines+1] = string.format("|cff%s%s|r |cff888888(%s%d)|r", tierHex, tier, repSign, agg.rep or 0)

    -- Vote counts
    lines[#lines+1] = string.format("|cff66ff66+%d|r |cff888888/|r |cffff6666-%d|r", agg.pos or 0, agg.neg or 0)

    -- Top reason if bad rep
    if self:IsBadTier(tier) then
      local topNK, topNV = MVP.Data:TopReason(agg.negReasons)
      if topNK then
        local reasonText = MVP.Data.NEG_REASONS[topNK] or topNK
        lines[#lines+1] = string.format("|cffff6666Warning:|r %s", reasonText)
      end
    end

    return table.concat(lines, "\n")
  end

  if self:IsBadTier(tier) then
    showIndicator = true
    indicatorColor = {self:GetTierColor(tier)}
    tooltipText = buildTooltip(playerKey, agg, tier, isFavorite)
  elseif isFavorite then
    showIndicator = true
    indicatorColor = {1, 0.82, 0}  -- Gold for favorites
    tooltipText = buildTooltip(playerKey, agg, tier, true)
  elseif self:IsGoodTier(tier) then
    showIndicator = true
    indicatorColor = {self:GetTierColor(tier)}
    tooltipText = buildTooltip(playerKey, agg, tier, isFavorite)
  elseif agg.total and agg.total > 0 then
    -- Has some rep data, show neutral indicator (for testing)
    showIndicator = true
    indicatorColor = {self:GetTierColor(tier)}
    tooltipText = buildTooltip(playerKey, agg, tier, isFavorite)
  end

  if showIndicator then
    -- Get or create indicator
    local indicator = self._indicators[entryKey]
    if not indicator then
      indicator = self:GetIndicator(entry)
      self._indicators[entryKey] = indicator
    end

    -- Position it on the right side of the entry
    indicator:ClearAllPoints()
    indicator:SetPoint("RIGHT", entry, "RIGHT", -5, 0)
    indicator:SetParent(entry)
    indicator:SetFrameLevel(entry:GetFrameLevel() + 10)

    -- Set color
    indicator.bg:SetVertexColor(indicatorColor[1], indicatorColor[2], indicatorColor[3], 0.9)

    -- Set icon based on type
    if isFavorite then
      indicator.icon:SetTexture("Interface\\COMMON\\ReputationStar")
      indicator.icon:SetTexCoord(0, 0.5, 0, 0.5)
      indicator.icon:SetVertexColor(1, 0.82, 0)  -- Gold tint
      indicator.icon:Show()
    elseif self:IsBadTier(tier) then
      indicator.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
      indicator.icon:SetTexCoord(0, 1, 0, 1)
      indicator.icon:SetVertexColor(1, 1, 1)
      indicator.icon:Show()
    elseif self:IsGoodTier(tier) then
      indicator.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
      indicator.icon:SetTexCoord(0, 1, 0, 1)
      indicator.icon:SetVertexColor(1, 1, 1)
      indicator.icon:Show()
    else
      indicator.icon:Hide()
    end

    indicator.tooltipText = tooltipText
    indicator:Show()
  else
    -- No indicator needed, release if exists
    if self._indicators[entryKey] then
      self:ReleaseIndicator(self._indicators[entryKey])
      self._indicators[entryKey] = nil
    end
  end
end

-- Scan all visible LFG entries
function Scanner:ScanLFGFrame()
  if not LFGBrowseFrame or not LFGBrowseFrame:IsVisible() then
    return
  end

  -- Find the ScrollBox
  local scrollBox = LFGBrowseFrameScrollBox
  if not scrollBox then
    MVP.Util.DebugPrint("LFG Scanner: ScrollBox not found")
    return
  end

  -- Track which entries we've seen this scan
  local seenEntries = {}

  -- Get the scroll target which contains the entries
  local scrollTarget = scrollBox.ScrollTarget
  if scrollTarget then
    -- Iterate through children of ScrollTarget
    for _, child in pairs({scrollTarget:GetChildren()}) do
      if child:IsVisible() and child:GetHeight() > 10 then
        local entryKey = tostring(child)
        seenEntries[entryKey] = true
        self:ScanEntry(child, entryKey)
      end
    end
  end

  -- Release indicators for entries no longer visible
  for entryKey, indicator in pairs(self._indicators) do
    if not seenEntries[entryKey] then
      self:ReleaseIndicator(indicator)
      self._indicators[entryKey] = nil
    end
  end
end

-- OnUpdate handler (throttled)
function Scanner:OnUpdate(elapsed)
  self._updateThrottle = (self._updateThrottle or 0) + elapsed
  if self._updateThrottle < self.UPDATE_INTERVAL then
    return
  end
  self._updateThrottle = 0

  if LFGBrowseFrame and LFGBrowseFrame:IsVisible() then
    self:ScanLFGFrame()
  end
end

-- Initialize the scanner
function Scanner:Init()
  if self._isHooked then return end

  -- Wait for LFGBrowseFrame to exist
  if not LFGBrowseFrame then
    MVP.Util.DebugPrint("LFG Scanner: LFGBrowseFrame not found, deferring init")
    return false
  end

  -- Create update frame
  self._frame = CreateFrame("Frame")
  self._frame:Hide()
  self._frame:SetScript("OnUpdate", function(_, elapsed)
    Scanner:OnUpdate(elapsed)
  end)

  -- Hook OnShow/OnHide
  LFGBrowseFrame:HookScript("OnShow", function()
    MVP.Util.DebugPrint("LFG Scanner: Frame shown, starting scan")
    Scanner._frame:Show()
    Scanner:ScanLFGFrame()
  end)

  LFGBrowseFrame:HookScript("OnHide", function()
    MVP.Util.DebugPrint("LFG Scanner: Frame hidden, stopping scan")
    Scanner._frame:Hide()
    Scanner:ReleaseAllIndicators()
  end)

  -- If frame is already visible, start scanning
  if LFGBrowseFrame:IsVisible() then
    self._frame:Show()
    self:ScanLFGFrame()
  end

  self._isHooked = true
  MVP.Util.DebugPrint("LFG Scanner: Initialized")
  return true
end

-- Delayed init (LFG frame might not exist immediately on login)
function Scanner:DelayedInit()
  if self._isHooked then return end

  if self:Init() then
    return
  end

  -- Try again later
  if C_Timer and C_Timer.After then
    C_Timer.After(2, function()
      Scanner:DelayedInit()
    end)
  end
end
