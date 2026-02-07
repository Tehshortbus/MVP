-- MVP - Sync.lua
-- Multi-channel sync: CHANNEL, GUILD, PARTY/RAID, WHISPER addon messages
-- Requires hardware events (keypress/click) to send - players must be active
local addonName, MVP = ...
MVP.Sync = MVP.Sync or {}
local Sync = MVP.Sync

Sync.PREFIX = "MVP"  -- Addon message prefix
Sync.MSG_PREFIX = "!MVP!"  -- Prefix for custom channel messages
Sync.CHANNEL_NAME = "MVPVouchSync"  -- Custom channel
Sync._channelId = nil

Sync.SEND_INTERVAL = 0.35
Sync._lastSendAt = 0

-- Register addon message prefix
local function RegisterPrefix(prefix)
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(prefix)
  elseif RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(prefix)
  end
end

-- Send addon message
local function SendAddon(prefix, msg, chatType, target)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(prefix, msg, chatType, target)
  else
    SendAddonMessage(prefix, msg, chatType, target)
  end
end

-- Chat filter to hide custom channel messages
local function ChatFilter(self, event, msg, sender, ...)
  if msg and msg:sub(1, #Sync.MSG_PREFIX) == Sync.MSG_PREFIX then
    Sync:OnChannelMessage(msg, sender)
    return true  -- Hide from chat
  end
  return false
end

-- Join the sync channel
function Sync:JoinChannel()
  local id = GetChannelName(Sync.CHANNEL_NAME)
  if id and id > 0 then
    Sync._channelId = id
    return id
  end

  local _, name = JoinChannelByName(Sync.CHANNEL_NAME)
  if name then
    Sync._channelId = GetChannelName(Sync.CHANNEL_NAME)
    -- Hide from chat frames
    for i = 1, 10 do
      if _G["ChatFrame"..i] then
        ChatFrame_RemoveChannel(_G["ChatFrame"..i], Sync.CHANNEL_NAME)
      end
    end
  end
  return Sync._channelId
end

function Sync:GetChannelId()
  if Sync._channelId and Sync._channelId > 0 then
    local id = GetChannelName(Sync.CHANNEL_NAME)
    if id and id > 0 then return id end
  end
  return self:JoinChannel()
end

-- Queues
Sync._queue = {}  -- For addon messages (GUILD, PARTY, RAID, WHISPER)
Sync._channelQueue = {}  -- For custom channel (needs hardware event)

Sync._frame = nil
Sync._ready = false
Sync._needsLoginSync = false
Sync._loginSyncSent = false

-- Sync tracking
Sync._syncInProgress = false
Sync._syncVouchesReceived = 0
Sync._syncLastReceiveTime = 0
Sync._syncCompleteTimer = nil
Sync.SYNC_COMPLETE_DELAY = 10

-- Dedup
Sync._recentMessages = {}

-- Queue a message for broadcast
function Sync:QueueMessage(msg)
  if not msg or msg == "" then return end
  self._queue[#self._queue + 1] = msg
  self._channelQueue[#self._channelQueue + 1] = msg
end

-- Broadcast via addon messages (GUILD, PARTY, RAID) - called from OnUpdate
function Sync:BroadcastAddonMessages(msg)
  -- GUILD
  if IsInGuild() then
    SendAddon(Sync.PREFIX, msg, "GUILD")
  end
  -- PARTY
  if IsInGroup() and not IsInRaid() then
    SendAddon(Sync.PREFIX, msg, "PARTY")
  end
  -- RAID
  if IsInRaid() then
    SendAddon(Sync.PREFIX, msg, "RAID")
  end
end

-- Flush channel queue (called on hardware event)
function Sync:FlushChannelQueue()
  if #self._channelQueue == 0 then
    MVP.Util.DebugPrint("FlushChannelQueue: queue empty")
    return 0
  end
  if not self._ready then
    MVP.Util.DebugPrint("FlushChannelQueue: not ready yet")
    return 0
  end

  local channelId = self:GetChannelId()
  if not channelId or channelId == 0 then
    MVP.Util.DebugPrint("FlushChannelQueue: no channel! Trying to join...")
    self:JoinChannel()
    return 0
  end

  MVP.Util.DebugPrint("FlushChannelQueue: sending to channel", channelId)

  local sent = 0
  while #self._channelQueue > 0 do
    local msg = table.remove(self._channelQueue, 1)
    if msg then
      local safeMsg = string.gsub(msg, "|", "~")
      local chatMsg = Sync.MSG_PREFIX .. safeMsg
      SendChatMessage(chatMsg, "CHANNEL", nil, channelId)
      sent = sent + 1
    end
  end
  MVP.Util.DebugPrint("FlushChannelQueue: sent", sent, "messages")
  return sent
end

-- Process channel queue on hardware events
local function ProcessChannelQueue()
  if not Sync._ready then return end

  -- Flush any queued channel messages
  if #Sync._channelQueue > 0 then
    Sync:FlushChannelQueue()
  end
end

function Sync:Init()
  RegisterPrefix(Sync.PREFIX)

  if not self._frame then
    self._frame = CreateFrame("Frame")

    -- OnUpdate for addon message queue
    self._frame:SetScript("OnUpdate", function(_, elapsed)
      Sync:OnUpdate(elapsed)
    end)

    -- Events
    self._frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self._frame:RegisterEvent("CHAT_MSG_ADDON")
    self._frame:SetScript("OnEvent", function(_, event, ...)
      if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(3, function()
          Sync._ready = true
          MVP.Util.DebugPrint("Sync ready")
        end)
      elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        Sync:OnAddonMessage(prefix, msg, channel, sender)
      end
    end)
  end

  -- Chat filter for custom channel
  if not Sync._chatFilterAdded then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", ChatFilter)
    Sync._chatFilterAdded = true
  end

  -- Hardware event hooks
  C_Timer.After(1, function()
    if WorldFrame and not Sync._worldFrameHooked then
      WorldFrame:HookScript("OnMouseDown", ProcessChannelQueue)
      Sync._worldFrameHooked = true
    end
  end)

  if not self._keyFrame then
    self._keyFrame = CreateFrame("Frame", "MVPSyncKeyFrame", UIParent)
    self._keyFrame:SetScript("OnKeyDown", ProcessChannelQueue)
    self._keyFrame:SetPropagateKeyboardInput(true)
  end

  -- Join channel and start sync
  C_Timer.After(5, function()
    Sync:JoinChannel()
    Sync:AutoSyncOnLogin()
  end)
end

-- OnUpdate - process addon message queue
function Sync:OnUpdate(elapsed)
  if #self._queue > 0 and self._ready then
    local now = GetTime()
    if (now - self._lastSendAt) >= Sync.SEND_INTERVAL then
      local msg = table.remove(self._queue, 1)
      if msg then
        self:BroadcastAddonMessages(msg)
        self._lastSendAt = now
      end
    end
  end

  -- Cleanup old dedup entries
  self._recentMessageCleanup = (self._recentMessageCleanup or 0) + elapsed
  if self._recentMessageCleanup > 60 then
    self._recentMessageCleanup = 0
    local cutoff = GetTime() - 60
    for k, v in pairs(self._recentMessages) do
      if v < cutoff then self._recentMessages[k] = nil end
    end
  end
end

-- Auto-sync on login - show popup instead of keypress detection
function Sync:AutoSyncOnLogin()
  MVPDB = MVPDB or {}
  MVPDB.vouches = MVPDB.vouches or {}
  MVPDB.meta = MVPDB.meta or { lastTs = 0 }
  MVPConfig = MVPConfig or {}
  
  -- Check if we've shown the sync popup recently (within 12 hours)
  local now = time()
  local lastPopupTime = MVPConfig.lastSyncPopupTime or 0
  local timeSinceLastPopup = now - lastPopupTime
  local TWELVE_HOURS = 12 * 60 * 60  -- 12 hours in seconds
  
  if timeSinceLastPopup < TWELVE_HOURS then
    local hoursRemaining = math.ceil((TWELVE_HOURS - timeSinceLastPopup) / 3600)
    MVP.Util.DebugPrint(string.format("Skipping sync popup - shown %d hours ago (cooldown: %d hours remaining)", 
      math.floor(timeSinceLastPopup / 3600), hoursRemaining))
    return
  end

  MVP.Util.DebugPrint("Showing sync popup - last shown more than 12 hours ago")

  -- Update the last popup time
  MVPConfig.lastSyncPopupTime = now

  -- Show sync popup after a brief delay
  C_Timer.After(2, function()
    Sync:ShowSyncPopup()
  end)
end

-- Create and show the sync popup
function Sync:ShowSyncPopup()
  if self._syncPopup then
    self._syncPopup:Show()
    return
  end

  -- Create popup frame
  local f = CreateFrame("Frame", "MVPSyncPopup", UIParent, "BackdropTemplate")
  f:SetSize(280, 100)
  f:SetPoint("TOP", UIParent, "TOP", 0, -100)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 }
  })
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetFrameStrata("DIALOG")

  -- Title
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", f, "TOP", 0, -12)
  title:SetText("|cff33ff99MVP|r")

  -- Message
  local msg = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  msg:SetPoint("TOP", title, "BOTTOM", 0, -4)
  msg:SetText("Click to sync your reputation database")

  -- Sync button
  local syncBtn = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
  syncBtn:SetSize(100, 24)
  syncBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
  syncBtn:SetText("Sync Now")
  syncBtn:SetScript("OnClick", function()
    Sync._syncInProgress = true
    Sync._syncVouchesReceived = 0
    Sync._syncLastReceiveTime = GetTime()

    local sinceTs = (MVPDB and MVPDB.meta and MVPDB.meta.lastTs) or 0
    local msg = "REQALL|" .. tostring(sinceTs)

    -- Send via GUILD/PARTY/RAID immediately (no hardware event needed)
    Sync:BroadcastAddonMessages(msg)

    -- Also queue for channel (needs hardware event - button click counts)
    Sync:QueueMessage(msg)
    Sync:FlushChannelQueue()

    Sync:StartSyncCompleteTimer()
    print("|cff33ff99MVP|r Sync requested.")
    f:Hide()
  end)

  -- X button in corner
  local xBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  xBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

  self._syncPopup = f
  f:Show()
end

function Sync:OnVouchReceived()
  if not self._syncInProgress then return end
  self._syncVouchesReceived = self._syncVouchesReceived + 1
  self._syncLastReceiveTime = GetTime()
  self:StartSyncCompleteTimer()
end

function Sync:StartSyncCompleteTimer()
  if self._syncCompleteTimer then
    self._syncCompleteTimer:Cancel()
  end
  self._syncCompleteTimer = C_Timer.NewTimer(self.SYNC_COMPLETE_DELAY, function()
    Sync:OnSyncComplete()
  end)
end

function Sync:OnSyncComplete()
  if not self._syncInProgress then return end
  self._syncInProgress = false
  local received = self._syncVouchesReceived or 0

  if self._syncCompleteTimer then
    self._syncCompleteTimer:Cancel()
    self._syncCompleteTimer = nil
  end

  if received > 0 then
    print("|cff33ff99MVP|r Sync complete. " .. received .. " vouches received.")
  else
    print("|cff33ff99MVP|r Sync complete. Database is up to date.")
  end

  if MVP.UI_DB and MVP.UI_DB.RefreshIfOpen then
    MVP.UI_DB:RefreshIfOpen()
  end
end

-- Process incoming sync message
function Sync:ProcessSyncMessage(msg, sender)
  local parts = MVP.Util.Split(msg, "|")
  local kind = parts[1]

  if kind == "V" then
    local vouchId = parts[2]
    if vouchId and self._recentMessages[vouchId] then return end
    if vouchId then self._recentMessages[vouchId] = GetTime() end

    local isNew = MVP.Data:ImportVouch(parts, sender)
    if isNew then
      self:OnVouchReceived()
      MVP.Util.DebugPrint("Imported vouch for", parts[5], "from", sender)
    end

  elseif kind == "REQALL" then
    local reqKey = "REQ:" .. (sender or "") .. ":" .. (parts[2] or "")
    if self._recentMessages[reqKey] then return end
    self._recentMessages[reqKey] = GetTime()

    MVP.Util.DebugPrint("Sync request from", sender)
    self:HandleReqAll(sender, parts[2])
  end
end

-- Broadcast a vouch
function Sync:BroadcastVouch(rec)
  local msg = table.concat({
    "V", rec.id or "", tostring(rec.ts or 0), rec.rater or "",
    rec.target or "", rec.targetClass or "", rec.role or "",
    tostring(rec.sign or 0), rec.reason or "", rec.runId or ""
  }, "|")
  self:QueueMessage(msg)
end

-- Request sync
function Sync:RequestSyncAll(sinceTs)
  local msg = "REQALL|" .. tostring(sinceTs or 0)
  self:QueueMessage(msg)
end

-- Handle sync request - respond via WHISPER directly to requester (works AFK!)
function Sync:HandleReqAll(sender, sinceTs)
  sinceTs = tonumber(sinceTs or "0") or 0
  if not MVPDB or not MVPDB.vouches then return end

  local myName = UnitName("player")
  local senderName = sender and sender:match("^(.-)%-") or sender
  if senderName == myName then return end

  -- Random delay to spread responses
  local delay = math.random() * 3

  C_Timer.After(delay, function()
    local ids = {}
    for id, rec in pairs(MVPDB.vouches) do
      if (rec.ts or 0) > sinceTs then
        ids[#ids + 1] = id
      end
    end

    table.sort(ids, function(a, b)
      return (MVPDB.vouches[a].ts or 0) > (MVPDB.vouches[b].ts or 0)
    end)

    local maxToSend = math.min(#ids, 100)
    MVP.Util.DebugPrint("Responding to REQALL from", sender, "with", maxToSend, "vouches via WHISPER")

    -- Send via WHISPER directly to requester - no hardware event needed!
    for i = 1, maxToSend do
      local rec = MVPDB.vouches[ids[i]]
      if rec then
        local msg = table.concat({
          "V", rec.id or "", tostring(rec.ts or 0), rec.rater or "",
          rec.target or "", rec.targetClass or "", rec.role or "",
          tostring(rec.sign or 0), rec.reason or "", rec.runId or ""
        }, "|")
        SendAddon(Sync.PREFIX, msg, "WHISPER", sender)
      end
    end
  end)
end

-- Get realm
Sync._myRealm = nil
function Sync:GetMyRealm()
  if not self._myRealm then
    self._myRealm = GetNormalizedRealmName() or GetRealmName():gsub("%s+", "")
  end
  return self._myRealm
end

function Sync:IsSameRealm(sender)
  if not sender then return false end
  local _, senderRealm = sender:match("^(.-)%-(.+)$")
  if not senderRealm then return true end
  return senderRealm == self:GetMyRealm()
end

-- Handle addon messages (GUILD, PARTY, RAID, WHISPER)
function Sync:OnAddonMessage(prefix, msg, channel, sender)
  if prefix ~= Sync.PREFIX then return end
  if not msg or msg == "" then return end

  local myName = UnitName("player")
  local senderName = sender and sender:match("^(.-)%-") or sender
  if senderName == myName then return end
  if not self:IsSameRealm(sender) then return end

  self:ProcessSyncMessage(msg, sender)
end

-- Handle custom channel messages
function Sync:OnChannelMessage(msg, sender)
  local data = msg:sub(#Sync.MSG_PREFIX + 1)
  if not data or data == "" then return end

  local myName = UnitName("player")
  local senderName = sender and sender:match("^(.-)%-") or sender
  if senderName == myName then return end
  if not self:IsSameRealm(sender) then return end

  data = string.gsub(data, "~", "|")
  self:ProcessSyncMessage(data, sender)
end

-- Alias for UI_DB sync button
function Sync:FlushAllChannelMessages()
  return self:FlushChannelQueue()
end

-- Debug status
function Sync:GetStatus()
  return {
    mode = "MULTI-CHANNEL (CHANNEL + GUILD + PARTY/RAID)",
    queueLength = #self._queue,
    channelQueueLength = #self._channelQueue,
    ready = Sync._ready,
    channelId = Sync._channelId or "NOT JOINED",
    inGuild = IsInGuild(),
    inParty = IsInGroup() and not IsInRaid(),
    inRaid = IsInRaid(),
  }
end
