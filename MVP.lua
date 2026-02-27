-- MVP - MVP.lua (core bootstrap + run state + commands + events)
local addonName, MVP = ...
MVP = MVP or {}

MVP.__partySeen = MVP.__partySeen or {}
MVP.__wasInGroup = MVP.__wasInGroup or false
-- Print addon loaded message
local function MVP_PrintLoaded()
  print("|cff33ff99MVP|r loaded. Type |cff00ff00/mvp|r for options.")
end

-- Slash command: /mvp
SLASH_MVP1 = "/mvp"
SlashCmdList["MVP"] = function(msg)
  MVP:Init()

  msg = tostring(msg or "")
  msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S+)%s*(.-)$")
  cmd = (cmd or ""):lower()

  if cmd == "" or cmd == "help" then
    print("|cff33ff99MVP|r Commands:")
    print("  /mvp start - Snapshot party and start tracking a run")
    print("  /mvp end - End run and open vouch window")
    print("  /mvp db - Open reputation database")
    print("  /mvp status - Show current run status")
    print("  /mvp sync - Request a full sync from nearby MVP users")
    print("  /mvp sources - Show anti-fraud source tracking stats")
    return
  end

  if cmd == "sources" then
    MVP.Data:PrintSourceStats()
    return
  end

  if cmd == "lfgframes" then
    -- Temporary diagnostic: find which LFG scroll frames exist
    local names = {
      "LFGBrowseFrame","LFGBrowseFrameScrollBox","LFGListFrame",
      "LFGListFrameScrollBox","LFGSearchFrame","LFGSearchFrameScrollBox",
      "LFGParentFrame","LFGParentFrameScrollBox",
    }
    for _, n in ipairs(names) do
      local f = _G[n]
      if f then
        local st = f.ScrollTarget and "has ScrollTarget" or "no ScrollTarget"
        print("|cff33ff99MVP|r "..n.." EXISTS "..st)
        -- Dump visible children of ScrollTarget
        if f.ScrollTarget then
          local vis = 0
          for _, c in ipairs({f.ScrollTarget:GetChildren()}) do
            if c:IsVisible() and c:GetHeight() > 10 then vis = vis + 1 end
          end
          print("  visible children: "..vis)
        end
      end
    end
    -- Also check LFGBrowseFrame children for scroll frames
    if LFGBrowseFrame then
      print("LFGBrowseFrame children:")
      for _, c in ipairs({LFGBrowseFrame:GetChildren()}) do
        local name = c:GetName() or "(unnamed)"
        local ot = c:GetObjectType()
        local vis = c:IsVisible() and "visible" or "hidden"
        print("  "..ot.." "..name.." "..vis)
      end
    end
    return
  end

  if cmd == "sync" then
    MVP.Sync:RequestSync(false)  -- no hardware event from slash command
    return
  end

  --[[ /mvp debug - Toggle debug messages (disabled)
  if cmd == "debug" then
    MVPConfig = MVPConfig or {}
    MVPConfig.debug = not MVPConfig.debug
    print("|cff33ff99MVP|r Debug mode: " .. (MVPConfig.debug and "ON" or "OFF"))
    return
  end
  --]]

  if cmd == "db" then
    MVP.UI_DB:Toggle()
    return
  end

  --[[ /mvp test - Test vouch UI with dummy players (disabled)
  if cmd == "test" then
    MVP:TestUI()
    return
  end
  --]]

  if cmd == "end" then
    MVP:EndRun("manual")
    return
  end

  if cmd == "start" then
    MVP:StartRun()
    return
  end

  if cmd == "status" then
    MVP:PrintStatus()
    return
  end

  print("|cff33ff99MVP|r Unknown command. Use /mvp help")
end

_G[addonName] = MVP

-- Event frame for auto-initialization and party tracking
local eventFrame = CreateFrame("Frame")
local hasInitialized = false
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
  if event == "PLAYER_LOGIN" then
    MVP:Init()
    MVP_PrintLoaded()
    hasInitialized = true
  elseif event == "PLAYER_ENTERING_WORLD" then
    if not hasInitialized then
      MVP:Init()
      MVP_PrintLoaded()
      hasInitialized = true
    end
    -- Also tick run state when zoning (instance transitions) - skip raids/BGs
    if MVP._inited and not IsInRaid() then
      MVP.Util.DebugPrint("PLAYER_ENTERING_WORLD - checking run state")
      MVP:TickRunState()
    end
  elseif event == "GROUP_ROSTER_UPDATE" then
    if MVP._inited then
      -- Skip processing in raids/BGs - MVP is for 5-man dungeons only
      if IsInRaid() then return end
      -- Delay slightly so WoW has time to resolve all player names from Unknown
      C_Timer.After(1.5, function()
        if IsInRaid() then return end
        MVP:PrintPartyReputations()
        MVP.Util.DebugPrint("GROUP_ROSTER_UPDATE (delayed) - checking run state")
        MVP:TickRunState()
      end)
    end
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    -- Skip raids/BGs
    if MVP._inited and not IsInRaid() then
      MVP.Util.DebugPrint("ZONE_CHANGED_NEW_AREA - checking run state")
      MVP:TickRunState()
    end
  elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
    -- Skip raids/BGs - dungeon boss detection only
    if MVP._inited and not IsInRaid() then
      MVP:OnCombatLogEvent()
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if MVP._inited then
      MVP:OnCombatEnd()
    end
  end
end)

MVP.LastBossByInstanceName = {
  -- TBC Dungeons
  ["Hellfire Ramparts"] = "Vazruden the Herald",
  ["The Blood Furnace"] = "Keli'dan the Breaker",
  ["The Shattered Halls"] = "Warchief Kargath Bladefist",
  ["The Slave Pens"] = "Quagmirran",
  ["The Underbog"] = "The Black Stalker",
  ["The Steamvault"] = "Warlord Kalithresh",
  ["Mana-Tombs"] = "Nexus-Prince Shaffar",
  ["Auchenai Crypts"] = "Exarch Maladaar",
  ["Sethekk Halls"] = "Talon King Ikiss",
  ["Shadow Labyrinth"] = "Murmur",
  ["The Mechanar"] = "Pathaleon the Calculator",
  ["The Botanica"] = "Warp Splinter",
  ["The Arcatraz"] = "Harbinger Skyriss",
  ["Magisters' Terrace"] = "Kael'thas Sunstrider",
  ["Old Hillsbrad Foothills"] = "Epoch Hunter",
  ["The Black Morass"] = "Aeonus",
  ["Opening of the Dark Portal"] = "Aeonus",

  -- Classic Dungeons
  ["Ragefire Chasm"] = "Taragaman the Hungerer",
  ["Wailing Caverns"] = "Mutanus the Devourer",
  ["The Deadmines"] = "Edwin VanCleef",
  ["Deadmines"] = "Edwin VanCleef",
  ["Shadowfang Keep"] = "Archmage Arugal",
  ["Blackfathom Deeps"] = "Aku'mai",
  ["The Stockade"] = "Bazil Thredd",
  ["Stormwind Stockade"] = "Bazil Thredd",
  ["Gnomeregan"] = "Mekgineer Thermaplugg",
  ["Razorfen Kraul"] = "Charlga Razorflank",
  ["Razorfen Downs"] = "Amnennar the Coldbringer",
  ["Uldaman"] = "Archaedas",
  ["Zul'Farrak"] = "Chief Ukorz Sandscalp",
  ["Maraudon"] = "Princess Theradras",
  ["Temple of Atal'Hakkar"] = "Shade of Eranikus",
  ["Sunken Temple"] = "Shade of Eranikus",
  ["Blackrock Depths"] = "Emperor Dagran Thaurissan",
  ["Lower Blackrock Spire"] = "Overlord Wyrmthalak",

  -- Scarlet Monastery wings
  ["Scarlet Monastery"] = "High Inquisitor Whitemane",
  ["SM Library"] = "Arcanist Doan",
  ["SM Armory"] = "Herod",
  ["SM Cathedral"] = "High Inquisitor Whitemane",
  ["SM Graveyard"] = "Bloodmage Thalnos",
  ["Scarlet Monastery - Library"] = "Arcanist Doan",
  ["Scarlet Monastery - Armory"] = "Herod",
  ["Scarlet Monastery - Cathedral"] = "High Inquisitor Whitemane",
  ["Scarlet Monastery - Graveyard"] = "Bloodmage Thalnos",

  -- Dire Maul wings
  ["Dire Maul"] = "King Gordok",
  ["Dire Maul East"] = "Alzzin the Wildshaper",
  ["Dire Maul West"] = "Prince Tortheldrin",
  ["Dire Maul North"] = "King Gordok",
  ["Dire Maul - East"] = "Alzzin the Wildshaper",
  ["Dire Maul - West"] = "Prince Tortheldrin",
  ["Dire Maul - North"] = "King Gordok",

  -- Stratholme wings
  ["Stratholme"] = "Baron Rivendare",
  ["Stratholme - Main Gate"] = "Balnazzar",
  ["Stratholme - Service Entrance"] = "Baron Rivendare",
  ["Stratholme Main Gate"] = "Balnazzar",
  ["Stratholme Service Entrance"] = "Baron Rivendare",
  ["Stratholme Living"] = "Balnazzar",
  ["Stratholme Undead"] = "Baron Rivendare",

  -- Scholomance
  ["Scholomance"] = "Darkmaster Gandling",
}

-- Reverse lookup: boss name -> true (for quick checking)
MVP.LastBossNames = {}
for _, bossName in pairs(MVP.LastBossByInstanceName) do
  MVP.LastBossNames[bossName] = true
end

MVP.Run = MVP.Run or {
  state = "IDLE", -- IDLE, CANDIDATE, ACTIVE
  instanceKey = nil,
  enteredAt = 0,
  nextPromptAt = 0,
  promptActive = false,
  snapshot = nil,
  participants = nil,
  participantsOrdered = nil,
  initialSet = nil,
  runId = nil,
  instanceName = nil,
  instanceID = nil,
  wasInGroup = false,
}

local function ensureConfig()
  MVPConfig = MVPConfig or { debug = false }
end

-- Save run state to persist through reloads
function MVP:SaveRunState()
  MVPDB = MVPDB or {}
  local R = MVP.Run
  if R.state == "ACTIVE" and R.snapshot then
    MVPDB.activeRun = {
      state = R.state,
      instanceName = R.instanceName,
      instanceID = R.instanceID,
      runId = R.runId,
      snapshot = R.snapshot,
      participants = R.participants,
      participantsOrdered = R.participantsOrdered,
      initialSet = R.initialSet,
    }
  else
    MVPDB.activeRun = nil
  end
end

-- Load run state after reload
function MVP:LoadRunState()
  MVPDB = MVPDB or {}
  if not MVPDB.activeRun then return end

  local saved = MVPDB.activeRun
  if saved.state == "ACTIVE" and saved.snapshot then
    local R = MVP.Run
    R.state = saved.state
    R.instanceName = saved.instanceName
    R.instanceID = saved.instanceID
    R.runId = saved.runId
    R.snapshot = saved.snapshot
    R.participants = saved.participants
    R.participantsOrdered = saved.participantsOrdered
    R.initialSet = saved.initialSet
    R.wasInGroup = IsInGroup() and not IsInRaid()

    local count = R.participantsOrdered and #R.participantsOrdered or 0
    print(("|cff33ff99MVP|r Restored active run: %s (%d players)"):format(R.instanceName or "Unknown", count))
  end
end

-- StaticPopup for snapshot confirmation
StaticPopupDialogs["MVP_SNAPSHOT_CONFIRM"] = {
  text = "Snapshot the party?",
  button1 = "Yes",
  button2 = "No",
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
  OnAccept = function() MVP:ConfirmSnapshot(true) end,
  OnCancel = function() MVP:ConfirmSnapshot(false) end,
}


function MVP:FormatReportForPlayerKey(playerKey)
  local key = MVP.Util.StripRealm(playerKey or "")
  if key == "" then return nil end

  local agg = MVP.Data:GetPlayerAgg(key)
  if not agg then
    return string.format("MVP: %s has no reports in the database.", key)
  end

  local rep = (agg.rep or ((agg.pos or 0) - (agg.neg or 0)))
  local tier = (agg.tier or MVP.Data:ReputationTier(rep))

  local msg = string.format("MVP: %s - %s (%d)", key, tier, rep)
  if rep < 0 then
    local topNegK, topNegV = MVP.Data:GetTopReason(agg.negReasons)
    if topNegK and topNegV and topNegV > 0 then
      local lbl = MVP.Data.NEG_REASONS[topNegK] or MVP.Data:GetReasonLabel(topNegK, true)
      msg = msg .. string.format(" - Top Downvote Comment: %s (%d)", lbl, topNegV)
    end
  end
  return msg
end

function MVP:PrintPlayerReport(playerKey)
  local msg = MVP:FormatReportForPlayerKey(playerKey)
  if msg then
    print("|cff33ff99MVP|r " .. msg)
  end
end


function MVP:Init()
  ensureConfig()
  if MVP._inited then return end
  MVP._inited = true

  MVP.Data:Init()
  MVP.Sync:Init()
  MVP.Tooltip:Init()
  MVP.UI_Vouch:Init()
  MVP.UI_DB:Init()
  MVP.LFG_Scanner:DelayedInit()
  MVP:InitMinimapButton()

  -- Restore run state from saved variables
  MVP:LoadRunState()
end

-- Minimap Button
function MVP:InitMinimapButton()
  if MVP._minimapButton then return end

  -- Load saved position or default
  MVPConfig = MVPConfig or {}
  MVPConfig.minimapPos = MVPConfig.minimapPos or 225

  local btn = CreateFrame("Button", "MVP_MinimapButton", Minimap)
  btn:SetSize(31, 31)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:SetHighlightTexture(136477) -- "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"

  -- Border overlay (must be first, positioned at TOPLEFT)
  local overlay = btn:CreateTexture(nil, "OVERLAY")
  overlay:SetSize(53, 53)
  overlay:SetTexture(136430) -- "Interface\\Minimap\\MiniMap-TrackingBorder"
  overlay:SetPoint("TOPLEFT")

  -- Background (dark circle behind icon)
  local background = btn:CreateTexture(nil, "BACKGROUND")
  background:SetSize(20, 20)
  background:SetTexture(136467) -- "Interface\\Minimap\\UI-Minimap-Background"
  background:SetPoint("TOPLEFT", 7, -5)

  -- Icon texture
  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetSize(17, 17)
  icon:SetTexture("Interface\\AddOns\\MVP\\MVP_Icon")
  icon:SetPoint("TOPLEFT", 7, -6)
  btn.icon = icon

  -- Position update function
  local function UpdatePosition()
    local angle = math.rad(MVPConfig.minimapPos or 225)
    local x = math.cos(angle) * 78
    local y = math.sin(angle) * 78
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
  end

  -- Dragging
  btn:SetMovable(true)
  btn:EnableMouse(true)
  btn:RegisterForDrag("LeftButton")
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  btn:SetScript("OnDragStart", function(self)
    self.dragging = true
  end)

  btn:SetScript("OnDragStop", function(self)
    self.dragging = false
  end)

  btn:SetScript("OnUpdate", function(self)
    if not self.dragging then return end
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    local angle = math.atan2(cy - my, cx - mx)
    MVPConfig.minimapPos = math.deg(angle)
    UpdatePosition()
  end)

  -- Click handlers
  btn:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
      MVP.UI_DB:Toggle()
    elseif button == "RightButton" then
      -- Right click opens vouch window if run is active, otherwise shows menu
      local R = MVP.Run
      if R and R.state == "ACTIVE" then
        MVP:OpenVouchWindow("manual")
        MVP:ResetRun()
      else
        print("|cff33ff99MVP|r Left-click: Open database | Right-click: End run (if active)")
      end
    end
  end)

  -- Tooltip
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff33ff99MVP|r Dungeon Vouches")
    GameTooltip:AddLine("Left-click: Open database", 1, 1, 1)
    GameTooltip:AddLine("Right-click: End run", 1, 1, 1)
    GameTooltip:AddLine("Drag: Move button", 0.7, 0.7, 0.7)
    local R = MVP.Run
    if R and R.state == "ACTIVE" then
      local count = R.participantsOrdered and #R.participantsOrdered or 0
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(("Active run: %s (%d players)"):format(R.instanceName or "Unknown", count), 0, 1, 0)
    end
    GameTooltip:Show()
  end)

  btn:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
  end)

  UpdatePosition()
  btn:Show()
  MVP._minimapButton = btn
  MVP.Util.DebugPrint("Minimap button created")
end




function MVP:ClassColorHex(classFile)
  if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
    local c = RAID_CLASS_COLORS[classFile]
    return string.format("%02x%02x%02x", math.floor(c.r*255+0.5), math.floor(c.g*255+0.5), math.floor(c.b*255+0.5))
  end
  return "ffffff"
end

function MVP:_GetUnitByPlayerKey(playerKey)
  playerKey = MVP.Util.NormalizePlayerKey(playerKey)
  if not playerKey then return nil end
  if UnitExists("player") and MVP.Util.PlayerKeyFromUnit("player") == playerKey then return "player" end
  for i=1,4 do
    local u = "party"..i
    if UnitExists(u) and MVP.Util.PlayerKeyFromUnit(u) == playerKey then return u end
  end
  return nil
end

-- Update class info for players in DB who are missing it
function MVP:UpdateMissingClassInfo()
  if not MVPDB or not MVPDB.players then return end

  local updated = false

  local function checkUnit(unit)
    if not UnitExists(unit) then return end
    local k = MVP.Util.PlayerKeyFromUnit(unit)
    if not k then return end

    local agg = MVPDB.players[k]
    if agg and not agg.classFile then
      local _, classFile = UnitClass(unit)
      if classFile then
        agg.classFile = classFile
        updated = true
        MVP.Util.DebugPrint("Updated class for", k, ":", classFile)
      end
    end
  end

  -- Always check player (even when solo)
  checkUnit("player")

  -- Check group members if in a group
  if IsInGroup() then
    for i = 1, 4 do checkUnit("party"..i) end
    for i = 1, 40 do checkUnit("raid"..i) end
  end

  -- Refresh UI if any classes were updated
  if updated and MVP.UI_DB and MVP.UI_DB.RefreshIfOpen then
    MVP.UI_DB:RefreshIfOpen()
  end
end

function MVP:PrintPartyReputations()
  if not IsInGroup() or IsInRaid() then return end

  -- Update any missing class info for party members in our DB
  MVP:UpdateMissingClassInfo()

  MVP.State = MVP.State or {}
  local prev = MVP.State.partySet or {}

  local cur = {}
  local ordered = {}

  local function addUnit(u)
    if UnitExists(u) then
      local k = MVP.Util.PlayerKeyFromUnit(u)
      if k and not cur[k] then
        cur[k] = true
        ordered[#ordered+1] = k
      end
    end
  end

  addUnit("player")
  for i = 1, 4 do addUnit("party"..i) end

  table.sort(ordered)

  -- Determine whether to print full roster or just newcomers
  local newcomers = {}
  for _, k in ipairs(ordered) do
    if not prev[k] then
      newcomers[#newcomers+1] = k
    end
  end

  -- Update stored set
  MVP.State.partySet = cur

  if #newcomers == 0 then return end

  -- If we previously had no party members recorded, print full roster header once
  local prevCount = 0
  for _ in pairs(prev) do prevCount = prevCount + 1 end

  if prevCount == 0 then
    print("|cff33ff99MVP|r Party reputation:")
    newcomers = ordered -- treat as full print on first capture
  else
    -- Print only the newcomers
    local playedWarning = false
    for _, k in ipairs(newcomers) do
      local agg = MVP.Data:GetPlayerAgg(k)
      local rep = 0
      local tier = "Neutral"
      local topNegK, topNegV = nil, 0
      if agg then
        rep = (agg.rep or ((agg.pos or 0) - (agg.neg or 0)))
        tier = (agg.tier or MVP.Data:ReputationTier(rep))
        if rep < 0 then
          topNegK, topNegV = MVP.Data:GetTopReason(agg.negReasons)
        end
      end
      local hex = MVP.Data:ReputationColorHex(tier)
      local unit = MVP:_GetUnitByPlayerKey(k)
      local _, classFile = unit and UnitClass(unit) or nil
      local nameHex = MVP:ClassColorHex(classFile)
      local line = string.format("|cff33ff99MVP|r |cff%s%s|r - |cff%s%s (%d)|r", nameHex, k, hex, tier, rep)
      if rep < 0 and topNegK and topNegV and topNegV > 0 then
        local negLbl = MVP.Data.NEG_REASONS[topNegK] or MVP.Data:GetReasonLabel(topNegK, true)
        line = line .. string.format("  |cff%sTop -: %s (%d)|r", hex, negLbl, topNegV)
      end
      print(line)
      -- Play warning sound for bad reputation players (Unfriendly or worse)
      if not playedWarning and (tier == "Hated" or tier == "Hostile" or tier == "Unfriendly") then
        PlaySound(SOUNDKIT.ALARM_CLOCK_WARNING_3)
        playedWarning = true  -- Only play once even if multiple bad players join
      end
    end
    return
  end

  -- Full roster print (first time)
  local playedWarning = false
  for _, k in ipairs(newcomers) do
    local agg = MVP.Data:GetPlayerAgg(k)
    local rep = 0
    local tier = "Neutral"
    local topNegK, topNegV = nil, 0
    if agg then
      rep = (agg.rep or ((agg.pos or 0) - (agg.neg or 0)))
      tier = (agg.tier or MVP.Data:ReputationTier(rep))
      if rep < 0 then
        topNegK, topNegV = MVP.Data:GetTopReason(agg.negReasons)
      end
    end
    local hex = MVP.Data:ReputationColorHex(tier)
    local unit = MVP:_GetUnitByPlayerKey(k)
    local _, classFile = unit and UnitClass(unit) or nil
    local nameHex = MVP:ClassColorHex(classFile)
    local line = string.format("  |cff%s%s|r - |cff%s%s (%d)|r", nameHex, k, hex, tier, rep)
    if rep < 0 and topNegK and topNegV and topNegV > 0 then
      local negLbl = MVP.Data.NEG_REASONS[topNegK] or MVP.Data:GetReasonLabel(topNegK, true)
      line = line .. string.format("  |cff%sTop -: %s (%d)|r", hex, negLbl, topNegV)
    end
    print(line)
    -- Play warning sound for bad reputation players (Unfriendly or worse)
    if not playedWarning and (tier == "Hated" or tier == "Hostile" or tier == "Unfriendly") then
      PlaySound(SOUNDKIT.ALARM_CLOCK_WARNING_3)
      playedWarning = true  -- Only play once even if multiple bad players join
    end
  end
end


function MVP:ResetRun()
  local R = MVP.Run
  
  -- Save the completed instance ID to prevent re-starting in the same instance
  R.completedInstanceID = R.instanceID
  
  R.state = "IDLE"
  R.instanceKey = nil
  R.instanceName = nil
  R.instanceID = nil
  R.runId = nil
  R.snapshot = nil
  R.participants = nil
  R.participantsOrdered = nil
  R.initialSet = nil
  R.promptActive = false
  R.enteredAt = 0
  R.nextPromptAt = 0

  -- Clear saved state
  MVP:SaveRunState()
end


function MVP:_GetClassForPlayerKey(playerKey)
  playerKey = MVP.Util.NormalizePlayerKey(playerKey)
  if not playerKey then return nil end
  if UnitExists("player") and MVP.Util.PlayerKeyFromUnit("player") == playerKey then
    local _, classFile = UnitClass("player")
    return classFile
  end
  for i=1,4 do
    local u = "party"..i
    if UnitExists(u) and MVP.Util.PlayerKeyFromUnit(u) == playerKey then
      local _, classFile = UnitClass(u)
      return classFile
    end
  end
  return nil
end

function MVP:GetPartyKeys()
  local keys = {}
  local function add(unit)
    local k = MVP.Util.PlayerKeyFromUnit(unit)
    if k then keys[#keys+1] = k end
  end
  add("player")
  for i = 1, 4 do add("party"..i) end
  return keys
end

function MVP:IsInPartyInstance()
  local inInstance, instanceType = IsInInstance()
  return inInstance and instanceType == "party"
end

function MVP:GetGroupCount()
  if GetNumGroupMembers then
    local n = GetNumGroupMembers()
    if n and n > 0 then return n end
  end
  local c = 1
  for i=1,4 do if UnitExists("party"..i) then c = c + 1 end end
  return c
end

function MVP:OnCombatLogEvent()
  local R = MVP.Run
  -- Only check if we have an active run
  if R.state ~= "ACTIVE" then return end

  local timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
        destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()

  -- Only care about UNIT_DIED events
  if subevent ~= "UNIT_DIED" then return end

  -- Check if the dead unit is a known last boss
  if not destName then return end
  if not MVP.LastBossNames[destName] then return end

  -- Verify we're in a matching instance
  local instanceName = GetInstanceInfo()
  local expectedBoss = MVP.LastBossByInstanceName[instanceName]

  -- If the boss that died matches the expected last boss for this instance (or any known boss)
  if expectedBoss and destName == expectedBoss then
    MVP.Util.DebugPrint("Last boss killed: " .. destName)
    MVP:TriggerEndOfRun(destName)
  elseif MVP.LastBossNames[destName] then
    -- Boss died but might be in a different-named instance (handle wing variants)
    MVP.Util.DebugPrint("Known last boss killed: " .. destName .. " (instance: " .. (instanceName or "unknown") .. ")")
    MVP:TriggerEndOfRun(destName)
  end
end

function MVP:TriggerEndOfRun(bossName)
  local R = MVP.Run
  if R.state ~= "ACTIVE" then return end

  -- Mark that we're waiting to show the vouch window
  R.pendingEndReason = "Boss killed: " .. (bossName or "Unknown")

  print("|cff33ff99MVP|r Final boss defeated! Vouch window will open when combat ends...")

  -- Check if we're in combat
  if UnitAffectingCombat("player") then
    -- Wait for combat to end
    MVP.Util.DebugPrint("In combat - waiting for PLAYER_REGEN_ENABLED")
    R.waitingForCombatEnd = true
  else
    -- Not in combat, show after 10 second delay for loot
    C_Timer.After(10, function()
      if R.state == "ACTIVE" and R.pendingEndReason then
        MVP:OpenVouchWindow(R.pendingEndReason)
        MVP:ResetRun()
      end
    end)
  end
end

function MVP:OnCombatEnd()
  local R = MVP.Run
  if not R.waitingForCombatEnd then return end
  if R.state ~= "ACTIVE" then return end

  R.waitingForCombatEnd = false
  MVP.Util.DebugPrint("Combat ended - showing vouch window after delay")

  -- 10 second delay for loot
  C_Timer.After(10, function()
    if R.state == "ACTIVE" and R.pendingEndReason then
      MVP:OpenVouchWindow(R.pendingEndReason)
      MVP:ResetRun()
    end
  end)
end

function MVP:TickRunState()
  local R = MVP.Run
  local now = GetTime()

  local inPartyInstance = MVP:IsInPartyInstance()
  local inGroup = IsInGroup() and not IsInRaid()
  local groupCount = MVP:GetGroupCount()
  local curInstanceName, _, _, _, _, _, _, curInstanceID = GetInstanceInfo()
  curInstanceName = curInstanceName or "Dungeon"

  MVP.Util.DebugPrint(("TickRunState: state=%s inPartyInstance=%s inGroup=%s count=%d"):format(
    R.state, tostring(inPartyInstance), tostring(inGroup), groupCount))

  -- End-of-run trigger: party disbanded while active
  if R.wasInGroup and (not inGroup) and R.state == "ACTIVE" then
    MVP:OpenVouchWindow("Party disbanded")
    MVP:ResetRun()
  end
  R.wasInGroup = inGroup

  if not inPartyInstance or not inGroup then
    -- Leaving instance/group resets candidate state (but keeps ACTIVE snapshot if you want; MVP reset to IDLE)
    if R.state == "CANDIDATE" then
      MVP.Util.DebugPrint("Not in party instance or group - resetting to IDLE")
      R.state = "IDLE"
      R.instanceKey = nil
      R.promptActive = false
      R.enteredAt = 0
      R.nextPromptAt = 0
    end
    -- Clear completedInstanceID flag when leaving instance
    R.completedInstanceID = nil
    return
  end

  -- If active, just expand participants
  if R.state == "ACTIVE" and R.snapshot then
    -- End run if instance ID changes (reset + multiple runs)
    if R.instanceID and curInstanceID and R.instanceID ~= curInstanceID then
      MVP:OpenVouchWindow("Instance changed")
      MVP:ResetRun()
      return
    end

    MVP:ExpandParticipants()
    return
  end

  -- Start candidate tracking
  if R.state == "IDLE" then
    local name, _, _, _, _, _, _, iid = GetInstanceInfo()
    name = name or "Dungeon"
    
    -- Prevent starting a new run if we just completed one in this same instance
    if R.completedInstanceID and iid and R.completedInstanceID == iid then
      MVP.Util.DebugPrint("Already completed a run in this instance - waiting to leave before starting new run")
      return
    end
    
    R.instanceName = name
    R.instanceID = iid
    R.instanceKey = name
    R.enteredAt = now
    R.state = "CANDIDATE"
    MVP.Util.DebugPrint("Entered dungeon - state now CANDIDATE")
    print("|cff33ff99MVP|r Entered " .. name .. " - waiting for full party...")
  end

  if R.state == "CANDIDATE" then
    if groupCount == 5 then
      -- Auto-start when all 5 players are in the dungeon
      print("|cff33ff99MVP|r Full party detected - starting run...")
      MVP:SnapshotParty()
    else
      MVP.Util.DebugPrint(("Waiting for 5 players (have %d)"):format(groupCount))
    end
  end
end

function MVP:ConfirmSnapshot(yes)
  local R = MVP.Run
  R.promptActive = false
  if not yes then
    R.nextPromptAt = GetTime() + 120
    return
  end

  if not MVP:IsInPartyInstance() then
    print("|cff33ff99MVP|r Snapshot aborted (not in a dungeon instance).")
    R.state = "IDLE"
    return
  end
  if not IsInGroup() or IsInRaid() then
    print("|cff33ff99MVP|r Snapshot aborted (not in a 5-man party).")
    R.state = "IDLE"
    return
  end
  if MVP:GetGroupCount() ~= 5 then
    print("|cff33ff99MVP|r Snapshot aborted (party is not 5 players).")
    R.nextPromptAt = GetTime() + 120
    return
  end

  MVP:SnapshotParty()
end

function MVP:SnapshotParty()
  local R = MVP.Run
  local instanceName, _, _, _, _, _, _, iid = GetInstanceInfo()
  instanceName = instanceName or (R.instanceName or "Dungeon")
  R.instanceID = iid
  local ts = MVP.Util.Now()
  local bucket = math.floor(ts / 60)

  local keys = MVP:GetPartyKeys()
  table.sort(keys)

  local runBase = instanceName .. "|" .. tostring(bucket) .. "|" .. table.concat(keys, ",")
  local runId = MVP.Util.FNV1aHex(runBase)

  R.runId = runId
  R.instanceName = instanceName
  R.snapshot = { ts = ts, instanceName = instanceName, runId = runId, initial = keys }

  R.participants = {}
  R.participantsOrdered = {}
  R.initialSet = {}

  for _, k in ipairs(keys) do
    R.participants[k] = { key = k, classFile = MVP:_GetClassForPlayerKey(k), firstSeen = ts, lastSeen = ts, initial = true }
    R.participantsOrdered[#R.participantsOrdered+1] = { key = k, initial = true }
    R.initialSet[k] = true
  end

  R.state = "ACTIVE"
  print(("|cff33ff99MVP|r Party snapshot saved for %s. RunID=%s"):format(instanceName, runId))

  -- Save to persist through reloads
  MVP:SaveRunState()
end

function MVP:ExpandParticipants()
  local R = MVP.Run
  if R.state ~= "ACTIVE" or not R.participants then return end
  if not IsInGroup() or IsInRaid() then return end

  local ts = MVP.Util.Now()
  local current = MVP:GetPartyKeys()

  -- Build set of current players for quick lookup
  local currentSet = {}
  for _, k in ipairs(current) do
    currentSet[k] = true
  end

  -- Add new players
  for _, k in ipairs(current) do
    if not R.participants[k] then
      R.participants[k] = { key = k, classFile = MVP:_GetClassForPlayerKey(k), firstSeen = ts, lastSeen = ts, initial = false, left = false }
      R.participantsOrdered[#R.participantsOrdered+1] = { key = k, initial = false }
      print(("|cff33ff99MVP|r New player joined run: %s (now %d participants)"):format(k, #R.participantsOrdered))
      -- Save updated state
      MVP:SaveRunState()
    else
      R.participants[k].lastSeen = ts
      -- Mark as returned if they came back
      if R.participants[k].left then
        R.participants[k].left = false
        print(("|cff33ff99MVP|r Player returned: %s"):format(k))
        MVP:SaveRunState()
      end
    end
  end

  -- Mark players who left
  local anyLeft = false
  for _, p in ipairs(R.participantsOrdered) do
    local k = p.key
    if R.participants[k] and not currentSet[k] and not R.participants[k].left then
      R.participants[k].left = true
      print(("|cff33ff99MVP|r Player left run: %s (still trackable for vouching)"):format(k))
      anyLeft = true
      MVP:SaveRunState()
    end
  end
  if anyLeft then
    print("|cff33ff99MVP|r If the run is ending early, |cff00ff00/mvp end|r will trigger vouching.")
  end
end

function MVP:BuildRunForUI()
  local R = MVP.Run
  if R.state ~= "ACTIVE" or not R.snapshot then return nil end
  
  -- Get current player key to exclude from vouch list
  local myKey = MVP.Util.PlayerKeyFromUnit("player")
  
  local list = {}
  for _, p in ipairs(R.participantsOrdered or {}) do
    -- Skip the current player - can't vouch for yourself
    if p.key ~= myKey then
      local pData = R.participants and R.participants[p.key]
      local cls = pData and pData.classFile or nil
      local left = pData and pData.left or false
      list[#list+1] = { key = p.key, initial = p.initial, classFile = cls, left = left }
    end
  end
  -- Return format matching TestUI() so UI_Vouch:Open works identically
  return {
    instanceName = R.instanceName,
    runId = R.runId,
    participants = list,  -- UI_Vouch expects "participants" not "participantsOrdered"
  }
end


function MVP:OpenVouchWindow(reason)
  local run = MVP:BuildRunForUI()
  if not run then
    print("|cff33ff99MVP|r No active run.")
    return
  end
  run.endReason = reason or "Ended"
  MVP.UI_Vouch:Open(run)
end

function MVP:EndRun(reason)
  local R = MVP.Run
  if not R or R.state ~= "ACTIVE" or not R.snapshot then
    print("|cff33ff99MVP|r No active run.")
    return
  end
  MVP:OpenVouchWindow(reason or "manual")
  MVP:ResetRun()
end

function MVP:StartRun()
  local R = MVP.Run

  -- Check if already active
  if R.state == "ACTIVE" and R.snapshot then
    print("|cff33ff99MVP|r Run already active. Use /mvp end to finish it first.")
    return
  end

  -- Must be in a group
  if not IsInGroup() or IsInRaid() then
    print("|cff33ff99MVP|r You must be in a party (not raid) to start a run.")
    return
  end

  -- Get instance info (works even outside instances for world groups)
  local instanceName, _, _, _, _, _, _, instanceID = GetInstanceInfo()
  local inInstance, instanceType = IsInInstance()

  if inInstance and instanceType == "party" then
    -- In a dungeon - use instance name
    instanceName = instanceName or "Dungeon"
  else
    -- Not in dungeon - use generic name
    instanceName = "Party Run"
  end

  -- Reset and set up
  MVP:ResetRun()
  R.instanceName = instanceName
  R.instanceID = instanceID

  -- Snapshot immediately
  MVP:SnapshotParty()

  local count = R.participantsOrdered and #R.participantsOrdered or 0
  print(("|cff33ff99MVP|r Run started with %d players. Use /mvp end when done."):format(count))
end




function MVP:PrintStatus()
  local R = MVP.Run
  local inInstance, instanceType = IsInInstance()
  local inGroup = IsInGroup() and not IsInRaid()
  local groupCount = MVP:GetGroupCount()
  local curInstanceName, _, _, _, _, _, _, curInstanceID = GetInstanceInfo()
  curInstanceName = curInstanceName or "Dungeon"

  local snap = (R.snapshot and "YES" or "NO")
  local pcount = (R.participantsOrdered and #R.participantsOrdered) or 0

  print("|cff33ff99MVP|r Status")
  print(("  State: %s"):format(R.state or "nil"))
  print(("  In group: %s  (count=%d)"):format(inGroup and "YES" or "NO", groupCount))
  print(("  In instance: %s  (type=%s)"):format(inInstance and "YES" or "NO", tostring(instanceType)))
  print(("  InstanceName: %s"):format(tostring(R.instanceName)))
  print(("  Snapshot: %s"):format(snap))
  print(("  RunID: %s"):format(tostring(R.runId)))
  print(("  Participants tracked: %d"):format(pcount))
  if R.state == "CANDIDATE" then
    print(("  Next snapshot prompt in: %.0fs"):format(math.max(0, (R.nextPromptAt or 0) - GetTime())))
  end
end



function MVP:TestUI()
  MVP:Init()

  local run = {
    isTest = true,
    runId = "TEST-" .. tostring(time()),
    instanceName = "Test Dungeon",
    participants = {},
  }

  local function add(name, classFile, role, initial, left)
    table.insert(run.participants, {
      key = MVP.Util.NormalizePlayerKey(name),
      classFile = classFile,
      defaultRole = role,
      initial = (initial ~= false),  -- default true
      left = left or false,
    })
  end

  local me = MVP.Util.PlayerKeyFromUnit("player") or "Tester"
  local _, myClass = UnitClass("player")
  add(me, myClass, "TANK")                           -- You (original)
  add("DummyHealer", "PRIEST", "HEALER")             -- Original healer
  add("DummyMage", "MAGE", "DPS")                    -- Original DPS
  add("RageQuitter", "ROGUE", "DPS", true, true)     -- Original but LEFT mid-run
  add("LateJoiner", "WARLOCK", "DPS", false, false)  -- Joined mid-run (replacement)
  add("AnotherLeaver", "HUNTER", "DPS", true, true)  -- Original but LEFT mid-run

  MVP.UI_Vouch:Open(run)
end
