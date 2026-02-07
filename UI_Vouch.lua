-- MVP - UI_Vouch.lua (Compact redesign)
local addonName, MVP = ...
MVP.UI_Vouch = MVP.UI_Vouch or {}
local UI = MVP.UI_Vouch

-- Role icons - use hi-res UI-LFG-ICON-ROLES texture with Blizzard's GetTexCoordsForRole
local ROLE_TEX_HIRES = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"
local ROLE_INFO = {
  TANK = {
    color = {0.2, 0.4, 0.8},
    name = "Tank",
    letter = "T",
    blizzRole = "TANK"
  },
  HEALER = {
    color = {0.2, 0.8, 0.3},
    name = "Healer",
    letter = "H",
    blizzRole = "HEALER"
  },
  DPS = {
    color = {0.8, 0.2, 0.2},
    name = "DPS",
    letter = "D",
    blizzRole = "DAMAGER"
  },
}

local function nextDDName(prefix)
  MVP._ddCounter = (MVP._ddCounter or 0) + 1
  return (prefix or "MVP_DD") .. tostring(MVP._ddCounter)
end

local function createDropdown(parent, width, namePrefix)
  local dd = CreateFrame("Frame", nextDDName(namePrefix), parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(dd, width or 90)
  UIDropDownMenu_JustifyText(dd, "LEFT")
  return dd
end

function UI:DetectRoleForPlayerKey(playerKey)
  if not UnitGroupRolesAssigned then return nil end

  local function roleFromUnit(unit)
    if not UnitExists(unit) then return nil end
    local k = MVP.Util.PlayerKeyFromUnit(unit)
    if not k or k ~= playerKey then return nil end
    local r = UnitGroupRolesAssigned(unit)
    if r == "TANK" then return "TANK" end
    if r == "HEALER" then return "HEALER" end
    if r == "DAMAGER" or r == "DPS" then return "DPS" end
    return nil
  end

  local r = roleFromUnit("player")
  if r then return r end
  for i = 1, 4 do
    r = roleFromUnit("party"..i)
    if r then return r end
  end
  return nil
end

function UI:Init()
  if self.frame then return end

  local f = CreateFrame("Frame", "MVP_VouchFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(620, 220)
  f:SetResizable(false)
  f:SetClampedToScreen(true)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.title:SetPoint("TOP", f, "TOP", 0, -4)
  f.title:SetJustifyH("CENTER")
  f.title:SetText("MVP - Vouches")

  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.sub:SetPoint("TOPLEFT", 14, -28)
  f.sub:SetText("")

  -- Validation message (right side of header, same row as Run:)
  f.validation = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.validation:SetPoint("TOPRIGHT", -14, -28)
  f.validation:SetJustifyH("RIGHT")
  f.validation:SetText("")
  f.validation:SetTextColor(1, 0.3, 0.3)

  -- Content area for player cards
  f.content = CreateFrame("Frame", nil, f)
  f.content:SetPoint("TOPLEFT", 10, -46)
  f.content:SetPoint("BOTTOMRIGHT", -10, 46)
  f.rows = {}

  -- Buttons
  f.submit = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
  f.submit:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -10, 12)
  f.submit:SetSize(100, 24)
  f.submit:SetText("Submit")
  f.submit:SetScript("OnClick", function() UI:OnSubmit() end)

  f.cancel = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
  f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", 10, 12)
  f.cancel:SetSize(100, 24)
  f.cancel:SetText("Cancel")
  f.cancel:SetScript("OnClick", function() f:Hide() end)

  self.frame = f
end

function UI:_hideAllRows()
  local f = self.frame
  for _, row in ipairs(f.rows or {}) do
    row:Hide()
  end
end

-- Create a role button with WoW LFG role icon (hi-res version)
local function createRoleButton(parent, role, x, y, onClick)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(32, 32)
  btn:SetPoint("TOPLEFT", x, y)

  local info = ROLE_INFO[role]

  -- Background
  btn.bg = btn:CreateTexture(nil, "BACKGROUND")
  btn.bg:SetAllPoints()
  btn.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

  -- Role icon - use hi-res texture with Blizzard's GetTexCoordsForRole
  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetSize(28, 28)
  btn.icon:SetPoint("CENTER")
  btn.icon:SetTexture(ROLE_TEX_HIRES)
  if GetTexCoordsForRole then
    btn.icon:SetTexCoord(GetTexCoordsForRole(info.blizzRole))
  end

  -- Fallback letter in case icon doesn't show correctly
  btn.letter = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  btn.letter:SetPoint("CENTER")
  btn.letter:SetText(info.letter)
  btn.letter:SetTextColor(info.color[1], info.color[2], info.color[3])
  btn.letter:Hide()  -- Hidden by default, shown if icon fails

  -- Desaturated when not selected
  btn.icon:SetDesaturated(true)
  btn.icon:SetAlpha(0.6)

  -- Checkmark overlay when selected
  btn.check = btn:CreateTexture(nil, "OVERLAY")
  btn.check:SetSize(14, 14)
  btn.check:SetPoint("BOTTOMRIGHT", 2, -2)
  btn.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
  btn.check:Hide()

  -- Hover highlight
  btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

  -- Tooltip
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(info.name)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  btn.role = role
  btn:SetScript("OnClick", onClick)

  return btn
end

-- Create vote button (up or down arrow) using chat frame scroll arrows
local function createVoteButton(parent, isUp, x, y, onClick)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(28, 28)
  btn:SetPoint("TOPLEFT", x, y)

  -- Arrow texture (chat frame scroll buttons)
  local texBase = isUp and "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp" or "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown"

  btn:SetNormalTexture(texBase .. "-Up")
  btn:SetPushedTexture(texBase .. "-Down")
  btn:SetHighlightTexture(texBase .. "-Highlight", "ADD")

  -- Selected state - use the arrow texture itself tinted green/red so color matches arrow shape
  btn.selected = btn:CreateTexture(nil, "ARTWORK", nil, 1)
  btn.selected:SetAllPoints()
  btn.selected:SetTexture(texBase .. "-Up")
  btn.selected:SetVertexColor(isUp and 0.2 or 1, isUp and 1 or 0.2, 0.2, 1)
  btn.selected:SetBlendMode("ADD")
  btn.selected:Hide()

  btn:SetScript("OnClick", onClick)

  return btn
end

function UI:_createRow(parent, x, y, participant, index)
  -- Consistent padding between elements
  local PAD = 4
  local NAME_H = 20   -- checkbox/name row height
  local STATUS_H = 14 -- status text height (left early/joined late)
  local ROLE_H = 32   -- role button height
  local VOTE_H = 28   -- vote button height

  -- Calculate Y positions with symmetrical padding
  local nameY = -PAD                                    -- -4
  local statusY = nameY - NAME_H                        -- -24 (status right below name)
  local roleY = statusY - STATUS_H - PAD                -- -42
  local voteY = roleY - ROLE_H - PAD                    -- -78
  local ddY = voteY - VOTE_H - PAD                      -- -110

  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(116, 148)  -- taller to fit status line
  row:SetPoint("TOPLEFT", x, y)

  -- Card background
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(0.08, 0.08, 0.08, 0.9)

  row.playerKey = participant.key
  row.data = { include = true, role = (participant.defaultRole or "DPS"), vouch = "POS", reason = nil }

  -- Include checkbox (left side of name)
  row.includeCB = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  row.includeCB:SetSize(20, 20)
  row.includeCB:SetPoint("TOPLEFT", row, "TOPLEFT", 2, nameY)
  row.includeCB:SetChecked(true)
  row.includeCB:SetScript("OnClick", function()
    row.data.include = row.includeCB:GetChecked() and true or false
    UI:UpdateRowAppearance(row)
    UI:Validate()
  end)

  -- Player name (to the right of checkbox) - smaller font to fit
  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.name:SetPoint("LEFT", row.includeCB, "RIGHT", -2, 0)
  row.name:SetPoint("RIGHT", row, "RIGHT", -2, 0)
  row.name:SetJustifyH("CENTER")
  local displayName = participant.key
  local n = displayName:match("^(.-)%-")
  if n and n ~= "" then displayName = n end
  row.name:SetText(displayName)

  if participant.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[participant.classFile] then
    local c = RAID_CLASS_COLORS[participant.classFile]
    row.name:SetTextColor(c.r, c.g, c.b)
  else
    row.name:SetTextColor(1, 1, 1)
  end

  -- Status label below name for leavers/joiners
  row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.status:SetPoint("TOP", row.name, "BOTTOM", 0, -1)
  row.status:SetPoint("LEFT", row, "LEFT", 2, 0)
  row.status:SetPoint("RIGHT", row, "RIGHT", -2, 0)
  row.status:SetJustifyH("CENTER")
  if participant.left then
    row.status:SetText("(left early)")
    row.status:SetTextColor(0.5, 0.5, 0.5)
  elseif participant.initial == false then
    row.status:SetText("(joined late)")
    row.status:SetTextColor(0.5, 1, 0.5)
  else
    row.status:SetText("")
  end

  -- Role buttons (Tank, Healer, DPS)
  row.roleButtons = {}
  for i, role in ipairs({"TANK", "HEALER", "DPS"}) do
    local roleBtn = createRoleButton(row, role, 8 + (i-1) * 34, roleY, function()
      row.data.role = role
      UI:UpdateRoleSelection(row)
      UI:Validate()
    end)
    row.roleButtons[role] = roleBtn
  end

  -- Best-effort role prefill
  local detected = UI:DetectRoleForPlayerKey(row.playerKey)
  if detected then
    row.data.role = detected
  end

  -- Vote buttons (Up and Down)
  row.upBtn = createVoteButton(row, true, 30, voteY, function()
    row.data.vouch = "POS"
    row.data.reason = nil
    UI:UpdateVoteSelection(row)
    UI:Validate()
  end)

  row.downBtn = createVoteButton(row, false, 60, voteY, function()
    row.data.vouch = "NEG"
    UI:UpdateVoteSelection(row)
    UI:Validate()
  end)

  -- Reason dropdown - anchor to BOTTOM of row
  row.reasonDD = createDropdown(row, 90, "MVP_VouchReasonDD")
  row.reasonDD:SetPoint("BOTTOM", row, "BOTTOM", 0, -6)
  row.reasonDD:SetScale(0.8)
  UIDropDownMenu_SetText(row.reasonDD, "(optional)")

  -- Store reference for refreshing
  row.reasonDD.row = row

  -- Initialize visual states
  UI:UpdateRoleSelection(row)
  UI:UpdateVoteSelection(row)
  UI:UpdateRowAppearance(row)

  return row
end

-- Update an existing row with new participant data
function UI:_updateRow(row, x, y, participant)
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", x, y)

  row.playerKey = participant.key
  row.data = { include = true, role = (participant.defaultRole or "DPS"), vouch = "POS", reason = nil }

  -- Update player name
  local displayName = participant.key
  local n = displayName:match("^(.-)%-")
  if n and n ~= "" then displayName = n end
  row.name:SetText(displayName)

  if participant.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[participant.classFile] then
    local c = RAID_CLASS_COLORS[participant.classFile]
    row.name:SetTextColor(c.r, c.g, c.b)
  else
    row.name:SetTextColor(1, 1, 1)
  end

  -- Update status
  if participant.left then
    row.status:SetText("(left early)")
    row.status:SetTextColor(0.5, 0.5, 0.5)
  elseif participant.initial == false then
    row.status:SetText("(joined late)")
    row.status:SetTextColor(0.5, 1, 0.5)
  else
    row.status:SetText("")
  end

  -- Reset checkbox
  row.includeCB:SetChecked(true)

  -- Best-effort role prefill
  local detected = UI:DetectRoleForPlayerKey(row.playerKey)
  if detected then
    row.data.role = detected
  end

  -- Reset and update visual states
  UI:UpdateRoleSelection(row)
  UI:UpdateVoteSelection(row)
  UI:UpdateRowAppearance(row)

  row:Show()
end

function UI:UpdateRoleSelection(row)
  for role, btn in pairs(row.roleButtons) do
    local info = ROLE_INFO[role]
    if role == row.data.role then
      btn.icon:SetDesaturated(false)
      btn.icon:SetAlpha(1)
      btn.check:Show()
      btn.bg:SetColorTexture(info.color[1] * 0.5, info.color[2] * 0.5, info.color[3] * 0.5, 0.9)
      if btn.letter then btn.letter:SetTextColor(1, 1, 1) end
    else
      btn.icon:SetDesaturated(true)
      btn.icon:SetAlpha(0.6)
      btn.check:Hide()
      btn.bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
      if btn.letter then btn.letter:SetTextColor(info.color[1], info.color[2], info.color[3]) end
    end
  end
end

function UI:RefreshReasonDropdown(row)
  local isUp = (row.data.vouch == "POS")
  local reasons = isUp and MVP.Data.POS_REASONS or MVP.Data.NEG_REASONS

  UIDropDownMenu_Initialize(row.reasonDD, function(dd, level)
    -- Add "None" option
    local noneInfo = UIDropDownMenu_CreateInfo()
    noneInfo.text = isUp and "(optional)" or "Select reason..."
    noneInfo.value = ""
    noneInfo.func = function()
      row.data.reason = nil
      UIDropDownMenu_SetSelectedValue(dd, "")
      UIDropDownMenu_SetText(dd, isUp and "(optional)" or "Select...")
      UI:Validate()
    end
    UIDropDownMenu_AddButton(noneInfo)

    -- Add reasons
    for key, label in pairs(reasons) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = label
      info.value = key
      info.func = function()
        row.data.reason = key
        UIDropDownMenu_SetSelectedValue(dd, key)
        local shortLabel = #label > 12 and label:sub(1, 10) .. ".." or label
        UIDropDownMenu_SetText(dd, shortLabel)
        UI:Validate()
      end
      UIDropDownMenu_AddButton(info)
    end
  end)

  -- Reset selection when vote type changes
  row.data.reason = nil
  UIDropDownMenu_SetText(row.reasonDD, isUp and "(optional)" or "Select...")
end

function UI:UpdateVoteSelection(row)
  local isUp = (row.data.vouch == "POS")

  if isUp then
    row.upBtn.selected:Show()
    row.downBtn.selected:Hide()
  else
    row.upBtn.selected:Hide()
    row.downBtn.selected:Show()
  end

  -- Refresh reason dropdown with appropriate reasons
  UI:RefreshReasonDropdown(row)
end

function UI:UpdateRowAppearance(row)
  local alpha = row.data.include and 1 or 0.35
  local bgAlpha = row.data.include and 0.9 or 0.4

  row.bg:SetColorTexture(0.08, 0.08, 0.08, bgAlpha)
  row.name:SetAlpha(alpha)
  row.includeCB:SetAlpha(1) -- Always keep checkbox visible
  for _, btn in pairs(row.roleButtons) do btn:SetAlpha(alpha) end
  row.upBtn:SetAlpha(alpha)
  row.downBtn:SetAlpha(alpha)
  row.reasonDD:SetAlpha(alpha)
end

function UI:Open(run)
  run = run or {}
  run.participants = run.participants or {}
  if #run.participants == 0 then
    print("|cff33ff99MVP|r Vouch window opened with 0 participants.")
  end

  self:Init()
  local f = self.frame
  self.run = run

  f.title:SetText(("MVP - %s"):format(run.instanceName or "Dungeon"))
  f.sub:SetText(("Run: %s"):format(run.runId and run.runId:sub(1, 12) or "?"))

  -- Hide all existing rows first
  self:_hideAllRows()

  local participants = run.participants or {}
  local cols = 5
  local colW = 120
  local rowH = 152

  -- Adjust window width based on participant count
  local actualCols = math.min(#participants, cols)
  local windowWidth = math.max(actualCols * colW + 20, 300)
  local rowsNeeded = math.max(math.ceil(#participants / cols), 1)
  local windowHeight = rowsNeeded * rowH + 90

  f:SetSize(windowWidth, windowHeight)
  f.content:SetSize(actualCols * colW, rowsNeeded * rowH)

  -- Frame pooling: reuse existing rows, create new only if needed
  f.rows = f.rows or {}
  for i, p in ipairs(participants) do
    local col = (i-1) % cols
    local r = math.floor((i-1) / cols)
    local x = col * colW
    local y = -(r * rowH)
    local row = f.rows[i]
    if row then
      -- Reuse existing row - just update its data
      self:_updateRow(row, x, y, p)
    else
      -- Create new row only if we don't have enough
      row = self:_createRow(f.content, x, y, p, i)
      f.rows[i] = row
    end
  end
  -- Any excess rows beyond participants count stay hidden (already hidden by _hideAllRows)

  f.validation:SetText("")
  f.submit:Enable()
  f:Show()

  self:Validate()
end

function UI:Validate()
  local f = self.frame
  local rater = MVP.Util.PlayerKeyFromUnit("player") or ""
  if not f or not f:IsShown() then return end

  local vouched = 0
  local tanks, heals, dps = 0, 0, 0
  local missingNegReason = nil

  for _, row in ipairs(f.rows) do
    local v = row.data.vouch
    if v and row.data.include then
      -- no self-vouch (except /mvp test)
      if (not (self.run and self.run.isTest)) and row.playerKey == rater then
        -- skip
      else
        vouched = vouched + 1

        if row.data.role == "TANK" then tanks = tanks + 1 end
        if row.data.role == "HEALER" then heals = heals + 1 end
        if row.data.role == "DPS" then dps = dps + 1 end

        if v == "NEG" and (not row.data.reason or row.data.reason == "") then
          missingNegReason = row.playerKey
        end
      end
    end
  end

  local problems = {}

  if vouched < 1 then
    problems[#problems+1] = "Select at least 1 player"
  end
  -- Role counts shown as info only (no limit since leavers/joiners can exceed 1/1/3)
  if missingNegReason then
    problems[#problems+1] = "Downvote needs reason"
  end

  if #problems > 0 then
    f.validation:SetText(table.concat(problems, " | "))
    f.validation:SetTextColor(1, 0.3, 0.3) -- red for errors
    f.submit:Disable()
    return false
  else
    -- Show role counts as info when valid (color coded: blue tank, green healer, red dps)
    local roleText = string.format(
      "Roles: |cff3366ccT=%d|r |cff33cc4dH=%d|r |cffcc3333D=%d|r",
      tanks, heals, dps
    )
    f.validation:SetText(roleText)
    f.validation:SetTextColor(1, 1, 1) -- white base (colors in string)
    f.submit:Enable()
    return true
  end
end

function UI:OnSubmit()
  if not self:Validate() then return end
  local run = self.run
  if not run or not run.runId then return end

  local rater = MVP.Util.PlayerKeyFromUnit("player")
  if not rater then return end

  MVPDB = MVPDB or {}
  MVPDB.meta = MVPDB.meta or { lastTs = 0, submissions = {} }
  MVPDB.meta.submissions = MVPDB.meta.submissions or {}
  local subKey = (run.runId or "") .. "|" .. (rater or "")
  if MVPDB.meta.submissions[subKey] then
    print("|cff33ff99MVP|r You already submitted vouches for this run.")
    return
  end

  if self.frame and self.frame.submit then self.frame.submit:Disable() end

  local created = 0
  for _, row in ipairs(self.frame.rows) do
    local v = row.data.vouch
    if v and row.data.include then
      if (not (run and run.isTest)) and row.playerKey == rater then
        -- skip self
      else
        local sign = (v == "NEG") and -1 or 1
        -- Get classFile from participant data
        local classFile = nil
        for _, p in ipairs(run.participants or {}) do
          if p.key == row.playerKey then
            classFile = p.classFile
            break
          end
        end
        local rec = {
          ts = MVP.Util.Now(),
          rater = rater,
          target = row.playerKey,
          targetClass = classFile,
          role = row.data.role,
          sign = sign,
          reason = row.data.reason,
          runId = run.runId,
          test = run.isTest and true or nil,
          ver = 1,
        }
        rec.id = MVP.Data:MakeVouchId(rec)
        local isNew = MVP.Data:ApplyVouch(rec, true)  -- isLocal = true for vouches we create
        if isNew then
          created = created + 1
          MVP.Sync:BroadcastVouch(rec)
        end
      end
    end
  end

  MVPDB.meta.submissions[subKey] = MVP.Util.Now()

  if created > 0 then
    print(("|cff33ff99MVP|r Submitted %d vouch(es)."):format(created))
    -- IMMEDIATELY flush ALL channel messages while still in hardware event context (button click)
    -- This must happen during the OnClick handler, NOT via timer
    MVP.Util.DebugPrint("Submit button clicked - flushing channel queue now (hardware event)")
    if MVP.Sync and MVP.Sync.FlushAllChannelMessages then
      local sent = MVP.Sync:FlushAllChannelMessages()
      MVP.Util.DebugPrint("FlushAllChannelMessages returned:", sent, "messages sent")
    else
      MVP.Util.DebugPrint("ERROR: FlushAllChannelMessages not found!")
    end
  else
    print("|cff33ff99MVP|r No new vouches submitted (duplicates ignored).")
  end

  if MVP.UI_DB and MVP.UI_DB.RefreshIfOpen then
    MVP.UI_DB:RefreshIfOpen()
  end

  self.frame:Hide()
end
