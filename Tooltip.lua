-- MVP - Tooltip.lua
local addonName, MVP = ...
MVP.Tooltip = MVP.Tooltip or {}
local T = MVP.Tooltip

function T:Init()
  if self._inited then return end
  self._inited = true

  GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip)
    local name, unit = tooltip:GetUnit()
    if not unit then return end
    if not UnitExists(unit) then return end
    local key = MVP.Util.PlayerKeyFromUnit(unit)
    if not key then return end

    local agg = MVP.Data:GetPlayerAgg(key)
    if not agg then return end

    tooltip:AddLine(" ")
    tooltip:AddLine("|cff33ff99MVP|r Vouches", 0.2, 1, 0.6)
    tooltip:AddLine(("+%d  -%d  (Total %d)"):format(agg.pos or 0, agg.neg or 0, agg.total or 0), 1, 1, 1)

    local roles = agg.roles or {}
    local function addRole(role)
      local r = roles[role]
      if r and (r.total or 0) > 0 then
        tooltip:AddLine(("%s: +%d  -%d  (Total %d)"):format(MVP.Data.ROLE_LABELS[role], r.pos or 0, r.neg or 0, r.total or 0), 0.9, 0.9, 0.9)
      end
    end
    addRole("TANK"); addRole("HEALER"); addRole("DPS")

    local topK, topV = MVP.Data:TopReason(agg.negReasons)
    if topK then
      tooltip:AddLine(("Top negative: %s (%d)"):format(MVP.Data.NEG_REASONS[topK] or topK, topV or 0), 1, 0.7, 0.7)
    end
  end)
end
