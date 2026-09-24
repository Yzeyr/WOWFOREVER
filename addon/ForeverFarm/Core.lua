local ADDON_NAME, ns = ...

-- Everything here is driven by looting, not combat. Looting happens after the
-- fight, so it sidesteps the in-combat API restrictions entirely, and each
-- looted corpse doubles as a kill. Kills you never loot aren't counted; that
-- undercount is accepted for now.

local LOOT_SLOT_MONEY = (Enum and Enum.LootSlotType and Enum.LootSlotType.Money) or 2

-- Money can land a moment after the loot window closes (autoloot, server
-- round-trip), so money gained this soon after a close still counts as loot.
local MONEY_GRACE_SECONDS = 2

-- Corpses already counted this login, so reopening a half-looted corpse
-- doesn't count the kill or its drops twice. Capped so it can't grow forever.
local SEEN_CAP = 500

ns.prices = ns.prices or {}

local seen, seenOrder = {}, {}
local lootContext -- the current (or just-closed) loot window
local lastMoney

local function isSecret(value)
  return issecretvalue ~= nil and issecretvalue(value)
end
ns.isSecret = isSecret

function ns.npcIdFromGUID(guid)
  if guid == nil or isSecret(guid) then return nil end
  local unitType, _, _, _, _, npcId = strsplit("-", guid)
  if unitType ~= "Creature" then return nil end
  return tonumber(npcId)
end

local function getItemInfo(itemId)
  if C_Item and C_Item.GetItemInfo then
    return C_Item.GetItemInfo(itemId)
  end
  return GetItemInfo(itemId)
end

-- Vendor price is the floor since an NPC always buys. Values are worked out at
-- display time rather than stored, so refreshing prices re-values all history.
function ns.itemValue(itemId)
  local vendor = select(11, getItemInfo(itemId)) or 0
  local ah = ns.prices[itemId]
  if ah and ah > vendor then
    return ah, "ah"
  end
  return vendor, "vendor"
end

function ns.itemName(itemId)
  return getItemInfo(itemId) or ("item " .. itemId)
end

function ns.itemsValue(items)
  local total = 0
  for itemId, count in pairs(items) do
    total = total + ns.itemValue(itemId) * count
  end
  return total
end

function ns.formatMoney(copper)
  copper = math.floor(copper + 0.5)
  local gold = math.floor(copper / 10000)
  local silver = math.floor((copper % 10000) / 100)
  local rest = copper % 100
  if gold > 0 then return string.format("%dg %02ds", gold, silver) end
  if silver > 0 then return string.format("%ds %02dc", silver, rest) end
  return string.format("%dc", rest)
end

function ns.mobStats(npcId)
  local mob = ns.db.mobs[npcId]
  if not mob then
    mob = { kills = 0, money = 0, items = {} }
    ns.db.mobs[npcId] = mob
  end
  return mob
end

function ns.valuePerKill(mob)
  if mob.kills == 0 then return 0 end
  return (mob.money + ns.itemsValue(mob.items)) / mob.kills
end

-- Sessions pause across logout/reload, so time spent offline doesn't dilute g/hr.
function ns.sessionSeconds(session)
  local running = session.resumedAt and (time() - session.resumedAt) or 0
  return session.activeSeconds + running
end

function ns.summarizeSession(session)
  local seconds = ns.sessionSeconds(session)
  local itemsValue = ns.itemsValue(session.items)
  local total = session.money + itemsValue
  return {
    seconds = seconds,
    kills = session.kills,
    money = session.money,
    itemsValue = itemsValue,
    total = total,
    perHour = seconds > 0 and total * 3600 / seconds or 0,
    killsPerMinute = seconds > 0 and session.kills * 60 / seconds or 0,
  }
end

function ns.startSession()
  ns.db.session = {
    startedAt = time(),
    resumedAt = time(),
    activeSeconds = 0,
    zone = GetRealZoneText(),
    kills = 0,
    money = 0,
    items = {},
  }
  return ns.db.session
end

function ns.stopSession()
  local session = ns.db.session
  if not session then return nil end
  session.activeSeconds = ns.sessionSeconds(session)
  session.resumedAt = nil
  session.endedAt = time()
  table.insert(ns.db.history, session)
  ns.db.session = nil
  return session
end

local function addItem(items, itemId, count)
  items[itemId] = (items[itemId] or 0) + count
end

local function markSeen(guid)
  seen[guid] = true
  table.insert(seenOrder, guid)
  if #seenOrder > SEEN_CAP then
    seen[table.remove(seenOrder, 1)] = nil
  end
end

-- Names come for free from whatever unit points at the corpse; the tooltip
-- fills in any we miss here.
local function rememberName(mob, guid)
  if mob.name then return end
  for _, unit in ipairs({ "target", "mouseover" }) do
    local unitGuid = UnitGUID(unit)
    if unitGuid and not isSecret(unitGuid) and unitGuid == guid then
      local name = UnitName(unit)
      if name and not isSecret(name) then
        mob.name = name
        return
      end
    end
  end
end

local handlers = {}

function handlers.ADDON_LOADED(name)
  if name ~= ADDON_NAME then return end
  ForeverFarmDB = ForeverFarmDB or {}
  local db = ForeverFarmDB
  db.version = 1
  db.mobs = db.mobs or {}
  db.history = db.history or {}
  ns.db = db
  if db.session then
    db.session.resumedAt = time()
  end
end

function handlers.PLAYER_ENTERING_WORLD()
  lastMoney = GetMoney()
end

function handlers.PLAYER_LOGOUT()
  local session = ns.db and ns.db.session
  if session and session.resumedAt then
    session.activeSeconds = ns.sessionSeconds(session)
    session.resumedAt = nil
  end
end

function handlers.LOOT_READY()
  -- LOOT_READY can fire more than once for the same window.
  if lootContext and not lootContext.closedAt then return end
  lootContext = { moneyWeights = {} }

  local session = ns.db.session
  local newSources = {}

  for slot = 1, GetNumLootItems() do
    local slotType = GetLootSlotType(slot)
    local itemId
    if slotType ~= LOOT_SLOT_MONEY then
      local link = GetLootSlotLink(slot)
      itemId = link and tonumber(link:match("item:(%d+)"))
    end

    local sources = { GetLootSourceInfo(slot) }
    if #sources == 0 and itemId and session then
      -- No source info: still worth something to the session, just not to a mob.
      local _, _, quantity = GetLootSlotInfo(slot)
      addItem(session.items, itemId, quantity or 1)
    end

    for i = 1, #sources, 2 do
      local guid, quantity = sources[i], sources[i + 1]
      if guid and not isSecret(guid) then
        if slotType == LOOT_SLOT_MONEY then
          -- Weighted by each corpse's share so AoE loot splits money fairly.
          lootContext.moneyWeights[guid] = (quantity and quantity > 0) and quantity or 1
        end
        if not seen[guid] then
          newSources[guid] = true
          if itemId then
            local count = quantity or 1
            if session then addItem(session.items, itemId, count) end
            local npcId = ns.npcIdFromGUID(guid)
            if npcId then addItem(ns.mobStats(npcId).items, itemId, count) end
          end
        end
      end
    end
  end

  for guid in pairs(newSources) do
    markSeen(guid)
    local npcId = ns.npcIdFromGUID(guid)
    if npcId then
      local mob = ns.mobStats(npcId)
      mob.kills = mob.kills + 1
      rememberName(mob, guid)
      if session then session.kills = session.kills + 1 end
    end
  end
end

function handlers.LOOT_CLOSED()
  if lootContext then
    lootContext.closedAt = GetTime()
  end
end

function handlers.PLAYER_MONEY()
  local money = GetMoney()
  local gained = lastMoney and (money - lastMoney) or 0
  lastMoney = money
  if gained <= 0 or not lootContext then return end
  if lootContext.closedAt and GetTime() - lootContext.closedAt > MONEY_GRACE_SECONDS then return end

  local session = ns.db.session
  if session then session.money = session.money + gained end

  local totalWeight = 0
  for _, weight in pairs(lootContext.moneyWeights) do
    totalWeight = totalWeight + weight
  end
  if totalWeight == 0 then return end
  for guid, weight in pairs(lootContext.moneyWeights) do
    local npcId = ns.npcIdFromGUID(guid)
    if npcId then
      local mob = ns.mobStats(npcId)
      mob.money = mob.money + gained * weight / totalWeight
    end
  end
end

local frame = CreateFrame("Frame")
for event in pairs(handlers) do
  frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event, ...)
  handlers[event](...)
end)
