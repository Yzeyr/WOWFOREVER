local _, ns = ...

-- A session's pace only means something once there's a few kills behind it.
local MIN_SESSION_KILLS = 5
local TOP_DROPS = 2

local function topDrops(mob)
  local drops = {}
  for itemId, count in pairs(mob.items) do
    table.insert(drops, { itemId = itemId, count = count, value = ns.itemValue(itemId) * count })
  end
  table.sort(drops, function(a, b) return a.value > b.value end)
  return drops
end

local function dropRate(count, kills)
  local perKill = count / kills
  if perKill > 1 then return string.format("x%.1f", perKill) end
  return string.format("%d%%", perKill * 100 + 0.5)
end

local function addMobLines(tooltip, npcId, unit)
  local mob = ns.db.mobs[npcId]
  if not mob then return end
  if not mob.name and unit then
    local name = UnitName(unit)
    if name and not ns.isSecret(name) then mob.name = name end
  end
  if mob.kills == 0 then return end

  local perKill = ns.valuePerKill(mob)
  tooltip:AddLine(" ")
  tooltip:AddDoubleLine("Forever Farm", mob.kills .. " looted", 1, 0.82, 0, 0.6, 0.6, 0.6)
  tooltip:AddDoubleLine("Per kill", ns.formatMoney(perKill), 1, 1, 1, 1, 1, 1)

  local session = ns.db.session
  if session and session.kills >= MIN_SESSION_KILLS then
    local summary = ns.summarizeSession(session)
    tooltip:AddDoubleLine("At this session's pace",
      ns.formatMoney(perKill * summary.killsPerMinute * 60) .. "/hr", 1, 1, 1, 0.3, 1, 0.3)
  end

  local drops = topDrops(mob)
  for i = 1, math.min(TOP_DROPS, #drops) do
    local drop = drops[i]
    if drop.value > 0 then
      tooltip:AddDoubleLine("  " .. ns.itemName(drop.itemId),
        dropRate(drop.count, mob.kills) .. " · " .. ns.formatMoney(ns.itemValue(drop.itemId)),
        0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    end
  end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
  if tooltip ~= GameTooltip or not ns.db then return end
  local _, unit = tooltip:GetUnit()
  local guid = data and data.guid or (unit and UnitGUID(unit))
  local npcId = ns.npcIdFromGUID(guid)
  if npcId then
    addMobLines(tooltip, npcId, unit)
  end
end)
