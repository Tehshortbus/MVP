-- MVP - UI_DB.lua (clean rebuild)
local addonName, MVP = ...
MVP.UI_DB = MVP.UI_DB or {}
local UI = MVP.UI_DB

local ROLE_FILTERS = {
  { value = "ALL",    label = "All Roles" },
  { value = "TANK",   label = "Tank"      },
  { value = "HEALER", label = "Healer"    },
  { value = "DPS",    label = "DPS"       },
}

-- Sortable columns: { id, label, xPos, width, justify }
local COLUMNS = {
  { id = "name",    label = "Player",       xPos =  16, width = 270, justify = "LEFT"   },
  { id = "pos",     label = "Pos",          xPos = 300, width =  50, justify = "CENTER" },
  { id = "neg",     label = "Neg",          xPos = 360, width =  50, justify = "CENTER" },
  { id = "rep",     label = "Reputation",   xPos = 420, width = 150, justify = "LEFT"   },
  { id = "toppos",  label = "Top Upvote",   xPos = 580, width = 210, justify = "LEFT"   },
  { id = "topneg",  label = "Top Downvote", xPos = 800, width = 180, justify = "LEFT"   },
}

-- Default sort: highest neg first (original behaviour)
UI.sortCol = UI.sortCol or "neg"
UI.sortDir = UI.sortDir or "desc"

-- Helper to check if a player is favorited
local function isFavorite(playerKey)
  MVPConfig = MVPConfig or {}
  MVPConfig.favorites = MVPConfig.favorites or {}
  return MVPConfig.favorites[playerKey] == true
end

-- Helper to toggle favorite status
local function toggleFavorite(playerKey)
  MVPConfig = MVPConfig or {}
  MVPConfig.favorites = MVPConfig.favorites or {}
  if MVPConfig.favorites[playerKey] then
    MVPConfig.favorites[playerKey] = nil
  else
    MVPConfig.favorites[playerKey] = true
  end
end

local REP_FILTERS = {
  { value = "ALL", label = "All Reps" },
  { value = "Hated", label = "Hated" },
  { value = "Hostile", label = "Hostile" },
  { value = "Unfriendly", label = "Unfriendly" },
  { value = "Neutral", label = "Neutral" },
  { value = "Friendly", label = "Friendly" },
  { value = "Honored", label = "Honored" },
  { value = "Revered", label = "Revered" },
  { value = "Exalted", label = "Exalted" },
}

local function nextDDName(prefix)
  MVP._ddCounter = (MVP._ddCounter or 0) + 1
  return (prefix or "MVP_DD") .. tostring(MVP._ddCounter)
end

local function createDropdown(parent, width, namePrefix)
  local dd = CreateFrame("Frame", nextDDName(namePrefix), parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(dd, width or 110)
  UIDropDownMenu_JustifyText(dd, "LEFT")
  return dd
end

local function sortedPairs(map)
  local t = {}
  for k, v in pairs(map or {}) do
    t[#t+1] = { k = k, v = v }
  end
  table.sort(t, function(a,b) return a.v > b.v end)
  return t
end

function UI:Init()
  if self.frame then return end

  local f = CreateFrame("Frame", "MVP_DBFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(1020, 580)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:Hide()
  -- Title
  f.TitleText:SetText("MVP - Reputation Database")
  f.TitleText:ClearAllPoints()
  f.TitleText:SetPoint("TOP", 0, -6)
  if f.TitleText.SetJustifyH then f.TitleText:SetJustifyH("CENTER") end

  -- Control row - all elements aligned to same baseline
  local ROW_Y = -38

  -- Search box
  f.searchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.searchLabel:SetPoint("TOPLEFT", 14, ROW_Y - 4)  -- Text needs slight offset to center with controls
  f.searchLabel:SetText("Search:")

  f.search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  f.search:SetSize(160, 20)
  f.search:SetPoint("TOPLEFT", 64, ROW_Y)
  f.search:SetAutoFocus(false)
  f.search:SetScript("OnTextChanged", function() UI:Refresh() end)

  -- Favorites first checkbox (after search box)
  f.favCB = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  f.favCB:SetSize(20, 20)
  f.favCB:SetPoint("TOPLEFT", 235, ROW_Y)
  f.favCB:SetChecked(false)
  f.favCB.text = f.favCB:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.favCB.text:SetPoint("LEFT", f.favCB, "RIGHT", 0, 0)
  f.favCB.text:SetText("Favs")
  f.favCB:SetScript("OnClick", function()
    UI.favoritesFirst = f.favCB:GetChecked()
    UI:Refresh()
  end)
  UI.favoritesFirst = false

  -- Role filter dropdown (dropdowns have built-in offset, so adjust up)
  f.roleDD = createDropdown(f, 100, "MVP_DBRoleDD")
  f.roleDD:SetPoint("TOPLEFT", 305, ROW_Y + 2)

  f.repDD = createDropdown(f, 100, "MVP_DBRepDD")
  f.repDD:SetPoint("TOPLEFT", 440, ROW_Y + 2)
  UIDropDownMenu_Initialize(f.roleDD, function(dd, level)
    for _, opt in ipairs(ROLE_FILTERS) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = opt.label
      info.value = opt.value
      info.func = function()
        UI.roleFilter = opt.value
        UIDropDownMenu_SetSelectedValue(dd, opt.value)
        UIDropDownMenu_SetText(dd, opt.label)
        UI:Refresh()
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  UI.roleFilter = "ALL"
  UIDropDownMenu_SetSelectedValue(f.roleDD, "ALL")
  UIDropDownMenu_SetText(f.roleDD, "All Roles")

  UIDropDownMenu_Initialize(f.repDD, function(dd, level)
    for _, opt in ipairs(REP_FILTERS) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = opt.label
      info.value = opt.value
      info.func = function()
        UI.repFilter = opt.value
        UIDropDownMenu_SetSelectedValue(dd, opt.value)
        UIDropDownMenu_SetText(dd, opt.label)
        UI:Refresh()
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  UI.repFilter = UI.repFilter or "ALL"
  UIDropDownMenu_SetSelectedValue(f.repDD, UI.repFilter)
  local repText = "All Reps"
  for _, opt in ipairs(REP_FILTERS) do if opt.value == UI.repFilter then repText = opt.label end end
  UIDropDownMenu_SetText(f.repDD, repText)

  -- Buttons (right side, same ROW_Y baseline)
  f.sync = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
  f.sync:SetPoint("TOPRIGHT", -14, ROW_Y)
  f.sync:SetSize(80, 20)
  f.sync:SetText("Sync")
  f.sync:SetScript("OnClick", function()
    MVP.Sync:RequestSync(true)  -- true = hardware event, can flush channel
  end)

  f.wipe = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
  f.wipe:SetPoint("RIGHT", f.sync, "LEFT", -8, 0)
  f.wipe:SetSize(80, 20)
  f.wipe:SetText("Wipe DB")
  f.wipe:SetScript("OnClick", function()
    MVP.Data:Wipe()
    UI.selected = nil
    UI:Refresh()
    print("|cff33ff99MVP|r Database wiped.")
  end)

  -- Column headers as clickable sort buttons
  f.headerBtns = {}
  local function makeSortBtn(col)
    local btn = CreateFrame("Button", nil, f)
    btn:SetSize(col.width, 18)
    btn:SetPoint("TOPLEFT", col.xPos, -76)
    btn:SetNormalFontObject("GameFontNormalSmall")
    btn:SetHighlightFontObject("GameFontHighlightSmall")

    local function updateLabel()
      local arrow = ""
      if UI.sortCol == col.id then
        arrow = UI.sortDir == "asc" and " \226\150\178" or " \226\150\188"  -- ▲ / ▼
      end
      btn:SetText(col.label .. arrow)
    end
    updateLabel()
    btn:SetScript("OnClick", function()
      if UI.sortCol == col.id then
        UI.sortDir = UI.sortDir == "asc" and "desc" or "asc"
      else
        UI.sortCol = col.id
        UI.sortDir = col.id == "name" and "asc" or "desc"
      end
      -- Refresh all header labels
      for _, b in ipairs(f.headerBtns) do b:updateLabel() end
      UI:Refresh()
    end)
    btn.updateLabel = updateLabel

    btn:SetScript("OnEnter", function()
      GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
      GameTooltip:SetText("Click to sort by " .. col.label, 1, 1, 1)
      GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.headerBtns[#f.headerBtns+1] = btn
  end
  for _, col in ipairs(COLUMNS) do makeSortBtn(col) end

  -- Detail panel (anchored from bottom, fixed height)
  local d = CreateFrame("Frame", nil, f, "InsetFrameTemplate3")
  d:SetPoint("BOTTOMLEFT", 12, 14)
  d:SetSize(996, 240)
  f.detail = d

  -- Stats bar anchored to TOP of detail panel with a small gap
  local sb = CreateFrame("Frame", nil, f)
  sb:SetPoint("BOTTOMLEFT",  d, "TOPLEFT",  0,  2)
  sb:SetPoint("BOTTOMRIGHT", d, "TOPRIGHT", 0,  2)
  sb:SetHeight(18)
  f.statsBar = sb

  f.statsText = sb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.statsText:SetAllPoints()
  f.statsText:SetJustifyH("CENTER")
  f.statsText:SetText("")

  -- Scroll list fills from column headers down to top of stats bar
  local listBox = CreateFrame("Frame", nil, f, "InsetFrameTemplate3")
  listBox:SetPoint("TOPLEFT",     12, -92)
  listBox:SetPoint("BOTTOMLEFT",  sb, "TOPLEFT",  0,  2)
  listBox:SetPoint("BOTTOMRIGHT", sb, "TOPRIGHT", 0,  2)
  f.listBox = listBox

  local sf = CreateFrame("ScrollFrame", nil, listBox, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 6, -6)
  sf:SetPoint("BOTTOMRIGHT", -26, 6)

  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(1, 1)
  sf:SetScrollChild(content)

  f.listSF = sf
  f.listContent = content
  f.listRows = {}

  -- Player name (large)
  d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  d.title:SetPoint("TOPLEFT", 16, -10)
  d.title:SetText("Select a player")

  -- Horizontal line under title
  d.titleLine = d:CreateTexture(nil, "ARTWORK")
  d.titleLine:SetPoint("TOPLEFT", 16, -32)
  d.titleLine:SetSize(964, 1)
  d.titleLine:SetColorTexture(0.4, 0.4, 0.4, 0.8)

  -- Column positions
  local col1X, col2X, col3X, col4X = 16, 250, 520, 770
  local headerY, bodyY = -42, -62

  -- Vertical divider lines
  d.div1 = d:CreateTexture(nil, "ARTWORK")
  d.div1:SetPoint("TOPLEFT", col2X - 12, -38)
  d.div1:SetSize(1, 185)
  d.div1:SetColorTexture(0.3, 0.3, 0.3, 0.6)

  d.div2 = d:CreateTexture(nil, "ARTWORK")
  d.div2:SetPoint("TOPLEFT", col3X - 12, -38)
  d.div2:SetSize(1, 185)
  d.div2:SetColorTexture(0.3, 0.3, 0.3, 0.6)

  d.div3 = d:CreateTexture(nil, "ARTWORK")
  d.div3:SetPoint("TOPLEFT", col4X - 12, -38)
  d.div3:SetSize(1, 185)
  d.div3:SetColorTexture(0.3, 0.3, 0.3, 0.6)

  -- Column 1: Summary stats
  d.col1Header = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  d.col1Header:SetPoint("TOPLEFT", col1X, headerY)
  d.col1Header:SetText("|cffFFD100Summary|r")

  d.col1Body = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  d.col1Body:SetPoint("TOPLEFT", col1X, bodyY)
  d.col1Body:SetWidth(210)
  d.col1Body:SetJustifyH("LEFT")
  d.col1Body:SetSpacing(4)

  -- Column 2: Role Breakdown
  d.col2Header = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  d.col2Header:SetPoint("TOPLEFT", col2X, headerY)
  d.col2Header:SetText("|cffFFD100Role Breakdown|r")

  d.col2Body = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  d.col2Body:SetPoint("TOPLEFT", col2X, bodyY)
  d.col2Body:SetWidth(245)
  d.col2Body:SetJustifyH("LEFT")
  d.col2Body:SetSpacing(4)

  -- Column 3: Upvote Reasons
  d.col3Header = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  d.col3Header:SetPoint("TOPLEFT", col3X, headerY)
  d.col3Header:SetText("|cff66ff66Upvote Reasons|r")

  d.col3Body = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  d.col3Body:SetPoint("TOPLEFT", col3X, bodyY)
  d.col3Body:SetWidth(225)
  d.col3Body:SetJustifyH("LEFT")
  d.col3Body:SetSpacing(4)

  -- Column 4: Downvote Reasons
  d.col4Header = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  d.col4Header:SetPoint("TOPLEFT", col4X, headerY)
  d.col4Header:SetText("|cffff6666Downvote Reasons|r")

  d.col4Body = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  d.col4Body:SetPoint("TOPLEFT", col4X, bodyY)
  d.col4Body:SetWidth(210)
  d.col4Body:SetJustifyH("LEFT")
  d.col4Body:SetSpacing(4)

  self.frame = f
end


function UI:_SetSelectedRow(row)
  local f = self.frame
  -- clear previous
  if f.selectedRow and f.selectedRow.selTex then
    f.selectedRow.selTex:Hide()
  end
  f.selectedRow = row
  if row and row.selTex then
    row.selTex:Show()
  end
end

function UI:_hideAllRows()
  local f = self.frame
  for _, row in ipairs(f.listRows or {}) do
    row:Hide()
  end
end

function UI:_renderDetail(playerKey)
  local f = self.frame
  local d = f.detail
  local agg = MVP.Data:GetPlayerAgg(playerKey)

  if not agg then
    d.title:SetText("Select a player")
    d.col1Body:SetText("")
    d.col2Body:SetText("")
    d.col3Body:SetText("")
    d.col4Body:SetText("")
    return
  end

  local total = agg.total or 0
  local pos = agg.pos or 0
  local neg = agg.neg or 0
  local rep = (agg.rep or (pos - neg))
  local tier = (agg.tier or MVP.Data:ReputationTier(rep))
  local hex = MVP.Data:ReputationColorHex(tier)

  -- Title with class color
  local titleText = MVP.Util.StripRealm(playerKey)
  if agg.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[agg.classFile] then
    local c = RAID_CLASS_COLORS[agg.classFile]
    local classHex = string.format("%02x%02x%02x", c.r*255, c.g*255, c.b*255)
    titleText = string.format("|cff%s%s|r", classHex, titleText)
  end
  d.title:SetText(titleText)

  -- Helper to format numbers (show decimal only if not whole)
  local function fmtNum(n)
    if n == math.floor(n) then return tostring(math.floor(n)) end
    return string.format("%.1f", n)
  end

  -- Column 1: Summary (with top reasons)
  local col1 = {}
  local topPK, topPV = MVP.Data:TopReason(agg.posReasons)
  local topNK, topNV = MVP.Data:TopReason(agg.negReasons)

  col1[#col1+1] = string.format("|cff%s%s|r  |cff888888(Score: %s)|r", hex, tier, fmtNum(rep))
  col1[#col1+1] = ""
  col1[#col1+1] = string.format("|cff66ff66+|r Upvotes:      |cffffffff%s|r", fmtNum(pos))
  col1[#col1+1] = string.format("|cffff6666-|r Downvotes:  |cffffffff%s|r", fmtNum(neg))
  col1[#col1+1] = string.format("|cffaaaaaa#|r Total:           |cffffffff%s|r", fmtNum(total))
  col1[#col1+1] = ""
  if topPK then
    local label = MVP.Data.POS_REASONS[topPK] or topPK
    col1[#col1+1] = string.format("|cff00ffffBest:|r %s |cff888888(%s)|r", label, fmtNum(topPV))
  end
  if topNK then
    local label = MVP.Data.NEG_REASONS[topNK] or topNK
    col1[#col1+1] = string.format("|cff8b0000Worst:|r %s |cff888888(%s)|r", label, fmtNum(topNV))
  end
  d.col1Body:SetText(table.concat(col1, "\n"))

  -- Column 2: Role Breakdown
  local col2 = {}
  for _, role in ipairs({ "TANK", "HEALER", "DPS" }) do
    local r = agg.roles and agg.roles[role]
    local roleTotal = r and (r.total or 0) or 0
    local rolePos = r and (r.pos or 0) or 0
    local roleNeg = r and (r.neg or 0) or 0
    col2[#col2+1] = string.format("|cffFFD100%s|r", MVP.Data.ROLE_LABELS[role])
    if roleTotal > 0 then
      col2[#col2+1] = string.format("  |cff66ff66+%s|r / |cffff6666-%s|r  |cff888888(%s total)|r", fmtNum(rolePos), fmtNum(roleNeg), fmtNum(roleTotal))
    else
      col2[#col2+1] = "  |cff555555No votes|r"
    end
    col2[#col2+1] = ""
  end
  d.col2Body:SetText(table.concat(col2, "\n"))

  -- Column 3: All Upvote Reasons (top highlighted in cyan/teal)
  local col3 = {}
  local posList = sortedPairs(agg.posReasons)
  if #posList == 0 then
    col3[#col3+1] = "|cff555555No upvotes recorded|r"
  else
    for i, it in ipairs(posList) do
      local label = MVP.Data.POS_REASONS[it.k] or it.k
      if i == 1 then
        -- Top reason highlighted in cyan/teal
        col3[#col3+1] = string.format("|cff00ffff%s|r |cff00ffff×|r |cff00ffff%s|r", fmtNum(it.v), label)
      else
        col3[#col3+1] = string.format("|cff66ff66%s|r |cffaaaaaa×|r %s", fmtNum(it.v), label)
      end
    end
  end
  d.col3Body:SetText(table.concat(col3, "\n"))

  -- Column 4: All Downvote Reasons (top highlighted in blood red)
  local col4 = {}
  local negList = sortedPairs(agg.negReasons)
  if #negList == 0 then
    col4[#col4+1] = "|cff555555No downvotes recorded|r"
  else
    for i, it in ipairs(negList) do
      local label = MVP.Data.NEG_REASONS[it.k] or it.k
      if i == 1 then
        -- Top reason highlighted in blood red
        col4[#col4+1] = string.format("|cff8b0000%s|r |cff8b0000×|r |cff8b0000%s|r", fmtNum(it.v), label)
      else
        col4[#col4+1] = string.format("|cffff6666%s|r |cffaaaaaa×|r %s", fmtNum(it.v), label)
      end
    end
  end
  d.col4Body:SetText(table.concat(col4, "\n"))
end

-- Helper to format numbers for display (used by row updates)
local function fmtVal(n)
  if not n then return "0" end
  if n == math.floor(n) then return tostring(math.floor(n)) end
  return string.format("%.1f", n)
end

-- Update an existing row with new data
function UI:_updateListRow(row, y, item, rowIndex)
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", 0, y)

  -- Update alternating background
  if row.altBg then
    if rowIndex % 2 == 0 then
      row.altBg:Show()
    else
      row.altBg:Hide()
    end
  elseif rowIndex % 2 == 0 then
    row.altBg = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    row.altBg:SetAllPoints(true)
    row.altBg:SetColorTexture(0.15, 0.15, 0.15, 0.5)
  end

  local isFav = isFavorite(item.key)

  -- Update favorite background
  if isFav then
    row.favBg:Show()
  else
    row.favBg:Hide()
  end

  -- Update selection state
  if UI.selected == item.key then
    row.selTex:Show()
  else
    row.selTex:Hide()
  end

  row.playerKey = item.key
  local agg = item.agg

  -- Update star
  if isFav then
    row.star:Show()
  else
    row.star:Hide()
  end

  -- Update name position and text
  row.text:ClearAllPoints()
  row.text:SetPoint("LEFT", isFav and 20 or 4, 0)
  row.text:SetWidth(isFav and 254 or 270)
  row.text:SetText(MVP.Util.StripRealm(item.key))

  -- Class color for player name
  if agg and agg.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[agg.classFile] then
    local c = RAID_CLASS_COLORS[agg.classFile]
    row.text:SetTextColor(c.r, c.g, c.b)
  else
    row.text:SetTextColor(1, 0.82, 0) -- default gold
  end

  -- Update pos/neg values
  local posVal = agg.pos or 0
  row.pos:SetText(fmtVal(posVal))

  local negVal = agg.neg or 0
  row.neg:SetText(fmtVal(negVal))

  -- Update rep
  local repVal = agg.rep or ((agg.pos or 0) - (agg.neg or 0))
  local tier = agg.tier or MVP.Data:ReputationTier(repVal)
  row.rep:SetText(string.format("%s (%s)", tier, fmtVal(repVal)))
  local rr, rg, rb = MVP.Data:ReputationColor(tier)
  row.rep:SetTextColor(rr, rg, rb)

  -- Update top reasons
  local topPK, topPV = MVP.Data:TopReason(agg.posReasons)
  local topPLabel = topPK and (MVP.Data.POS_REASONS[topPK] or topPK) or ""
  row.topPos:SetText(topPLabel ~= "" and (topPLabel .. " ("..fmtVal(topPV)..")") or "")

  local topNK, topNV = MVP.Data:TopReason(agg.negReasons)
  local topNLabel = topNK and (MVP.Data.NEG_REASONS[topNK] or topNK) or ""
  row.topNeg:SetText(topNLabel ~= "" and (topNLabel .. " ("..fmtVal(topNV)..")") or "")

  row:Show()
end

function UI:_createListRow(parent, y, item, rowIndex)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(992, 20)
  row:SetPoint("TOPLEFT", 0, y)
  row:SetNormalFontObject("GameFontHighlightSmall")
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  -- Alternating row background (created on demand)
  if rowIndex % 2 == 0 then
    row.altBg = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    row.altBg:SetAllPoints(true)
    row.altBg:SetColorTexture(0.15, 0.15, 0.15, 0.5)
  end

  -- Gold favorite background (always created, shown/hidden as needed)
  row.favBg = row:CreateTexture(nil, "BACKGROUND", nil, 0)
  row.favBg:SetAllPoints(true)
  row.favBg:SetColorTexture(0.8, 0.6, 0.0, 0.25)
  row.favBg:Hide()

  row.selTex = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  row.selTex:SetAllPoints(true)
  row.selTex:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  row.selTex:SetAlpha(0.25)
  row.selTex:Hide()

  row.playerKey = item.key
  row.lastClickTime = 0

  -- Gold star for favorites
  row.star = row:CreateTexture(nil, "OVERLAY")
  row.star:SetSize(14, 14)
  row.star:SetPoint("LEFT", 4, 0)
  row.star:SetTexture("Interface\\COMMON\\ReputationStar")
  row.star:SetTexCoord(0, 0.5, 0, 0.5)
  row.star:SetVertexColor(1, 0.82, 0)
  row.star:Hide()

  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.text:SetPoint("LEFT", 4, 0)
  row.text:SetWidth(270)
  row.text:SetJustifyH("LEFT")

  row.pos = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.pos:SetPoint("LEFT", 282, 0)
  row.pos:SetWidth(50)
  row.pos:SetJustifyH("CENTER")

  row.neg = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.neg:SetPoint("LEFT", 342, 0)
  row.neg:SetWidth(50)
  row.neg:SetJustifyH("CENTER")

  row.rep = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.rep:SetPoint("LEFT", 402, 0)
  row.rep:SetWidth(150)
  row.rep:SetJustifyH("LEFT")

  row.topPos = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.topPos:SetPoint("LEFT", 562, 0)
  row.topPos:SetWidth(210)
  row.topPos:SetJustifyH("LEFT")

  row.topNeg = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.topNeg:SetPoint("LEFT", 782, 0)
  row.topNeg:SetWidth(180)
  row.topNeg:SetJustifyH("LEFT")

  -- Set up click handler (only done once per row)
  row:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
      local key = row.playerKey
      local agg = MVP.Data:GetPlayerAgg(key)
      local pname = MVP.Util.StripRealm(key)

      local function send(msg)
        if IsInGroup() then
          local chan = IsInRaid() and "RAID" or "PARTY"
          SendChatMessage(msg, chan)
        else
          print(msg)
        end
      end

      if not agg then
        send(string.format("[MVP] %s - No reputation data in database.", pname))
        return
      end

      local pos   = agg.pos or 0
      local neg   = agg.neg or 0
      local total = agg.total or 0

      -- Line 1: header
      send(string.format("[MVP] Player Report: %s", pname))

      -- Line 2: vouch counts
      send(string.format("[MVP] %d total vouches — %d positive, %d negative", total, pos, neg))

      -- Line 3: top comments (if any)
      local topPK, topPV = MVP.Data:TopReason(agg.posReasons)
      local topNK, topNV = MVP.Data:TopReason(agg.negReasons)
      local hasFeedback = (topPK and topPV and topPV > 0) or (topNK and topNV and topNV > 0)
      if hasFeedback then
        local parts = {}
        if topPK and topPV and topPV > 0 then
          local lbl = MVP.Data.POS_REASONS[topPK] or topPK
          parts[#parts+1] = string.format("+%s (%d)", lbl, topPV)
        end
        if topNK and topNV and topNV > 0 then
          local lbl = MVP.Data.NEG_REASONS[topNK] or topNK
          parts[#parts+1] = string.format("-%s (%d)", lbl, topNV)
        end
        send("[MVP] Top comments: " .. table.concat(parts, ", "))
      end

      return
    end

    -- Left click - check for double-click to toggle favorite
    local now = GetTime()
    if (now - row.lastClickTime) < 0.3 then
      -- Double-click detected - toggle favorite
      toggleFavorite(row.playerKey)
      local wasFav = isFavorite(row.playerKey)
      if wasFav then
        print("|cff33ff99MVP|r Added " .. MVP.Util.StripRealm(row.playerKey) .. " to favorites")
      else
        print("|cff33ff99MVP|r Removed " .. MVP.Util.StripRealm(row.playerKey) .. " from favorites")
      end
      UI:Refresh()
      row.lastClickTime = 0  -- Reset to prevent triple-click toggle
      return
    end
    row.lastClickTime = now

    UI.selected = row.playerKey
    UI:_SetSelectedRow(row)
    UI:_renderDetail(row.playerKey)
  end)

  -- Populate initial data using the update function
  UI:_updateListRow(row, y, item, rowIndex)

  return row
end

function UI:Refresh()
  local f = self.frame
  if not f then return end

  local query     = f.search:GetText() or ""
  local roleFilter = UI.roleFilter or "ALL"
  local results   = MVP.Data:SearchPlayers(query, roleFilter)
  local repFilter = UI.repFilter or "ALL"
  if repFilter ~= "ALL" then
    local filtered = {}
    for _, item in ipairs(results) do
      local agg = item.agg or MVP.Data:GetPlayerAgg(item.key)
      local repVal = (agg and (agg.rep or ((agg.pos or 0) - (agg.neg or 0)))) or 0
      local tier   = (agg and (agg.tier or MVP.Data:ReputationTier(repVal))) or "Neutral"
      if tier == repFilter then
        item.agg = agg
        filtered[#filtered+1] = item
      end
    end
    results = filtered
  end

  -- ── Column sort ────────────────────────────────────────────────────────────
  local col = UI.sortCol or "neg"
  local asc = (UI.sortDir == "asc")

  -- Helper: get the sortable value for a column id
  local function colVal(item, colId)
    if not item then return colId == "name" and "" or 0 end
    local agg = item.agg
    if not agg then return colId == "name" and (item.key or ""):lower() or 0 end
    if colId == "name"   then return (item.key or ""):lower() end
    if colId == "pos"    then return agg.pos or 0 end
    if colId == "neg"    then return agg.neg or 0 end
    if colId == "rep"    then return agg.rep or ((agg.pos or 0) - (agg.neg or 0)) end
    if colId == "toppos" then
      local _, v = MVP.Data:GetTopReason(agg.posReasons)
      return v or 0
    end
    if colId == "topneg" then
      local _, v = MVP.Data:GetTopReason(agg.negReasons)
      return v or 0
    end
    return 0
  end

  table.sort(results, function(a, b)
    if not a then return false end
    if not b then return true end
    local av = colVal(a, col)
    local bv = colVal(b, col)
    -- Ensure same type for comparison
    if type(av) ~= type(bv) then
      av = tostring(av)
      bv = tostring(bv)
    end
    if asc then return av < bv else return av > bv end
  end)

  -- Favorites-first override (secondary sort within each fav/non-fav group)
  if UI.favoritesFirst then
    table.sort(results, function(a, b)
      local aFav = isFavorite(a.key)
      local bFav = isFavorite(b.key)
      if aFav and not bFav then return true end
      if bFav and not aFav then return false end
      -- preserve column sort within group
      local av = colVal(a, col)
      local bv = colVal(b, col)
      if asc then return av < bv else return av > bv end
    end)
  end

  -- ── Stats bar ──────────────────────────────────────────────────────────────
  if f.statsText then
    -- Count unique players and total vouches across entire DB (not filtered)
    local totalPlayers = 0
    local totalVouches = 0
    if MVPDB and MVPDB.players then
      for _ in pairs(MVPDB.players) do totalPlayers = totalPlayers + 1 end
    end
    if MVPDB and MVPDB.vouches then
      for _ in pairs(MVPDB.vouches) do totalVouches = totalVouches + 1 end
    end
    local showing = #results
    f.statsText:SetText(string.format(
      "|cff66ff66%d|r |cff888888unique players in DB  —  |r|cffaaaaaa%d|r |cff888888total vouches in database|r",
      totalPlayers, totalVouches))
  end

  -- ── Render rows ────────────────────────────────────────────────────────────
  self:_hideAllRows()

  local rowHeight = 22
  f.listContent:SetSize(992, math.max(#results * rowHeight, 1))

  f.listRows = f.listRows or {}
  for i, item in ipairs(results) do
    local y   = -((i-1) * rowHeight)
    local row = f.listRows[i]
    if row then
      self:_updateListRow(row, y, item, i)
    else
      row = self:_createListRow(f.listContent, y, item, i)
      f.listRows[i] = row
    end
  end

  if UI.selected then
    self:_renderDetail(UI.selected)
  end
end

function UI:RefreshIfOpen()
  if self.frame and self.frame:IsShown() then
    self:Refresh()
  end
end

function UI:Toggle()
  self:Init()
  if self.frame:IsShown() then
    self.frame:Hide()
  else
    -- Update any missing class info before showing
    if MVP.UpdateMissingClassInfo then
      MVP:UpdateMissingClassInfo()
    end
    self.frame:Show()
    self:Refresh()
  end
end
