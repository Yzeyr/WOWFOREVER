-- Runs the addon outside the game against a stubbed WoW API and simulates a
-- short farming session. Not a substitute for testing in the client (the stubs
-- encode our assumptions about the real API), but it catches logic and syntax
-- bugs without logging in. Run from the repo root: lua5.1 tests/addon_sim.lua

local ADDON_DIR = "addon/ForeverFarm/"
local ADDON_NAME = "ForeverFarm"

local failures = 0
local function check(label, actual, expected)
  if actual == expected then
    print("ok    " .. label)
  else
    failures = failures + 1
    print(string.format("FAIL  %s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

-- Fake world state the stubs read from.
local world = {
  now = 1000000,
  gameTime = 500,
  money = 50000,
  zone = "Stranglethorn Vale",
  loot = {}, -- slots: { type=1|2, link=, quantity=, sources = {guid, qty, ...} }
  units = {},
  items = {
    [4338] = { name = "Mageweave Cloth", sell = 250 },
    [4306] = { name = "Silk Cloth", sell = 150 },
  },
}

local chat = {}
local eventFrame

function time() return world.now end
function GetTime() return world.gameTime end
function GetMoney() return world.money end
function GetRealZoneText() return world.zone end
function strsplit(sep, text)
  local parts = {}
  for part in (text .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do
    table.insert(parts, part)
  end
  return unpack(parts)
end
Enum = { LootSlotType = { Item = 1, Money = 2 }, TooltipDataType = { Unit = 2 } }
C_Item = {
  GetItemInfo = function(id)
    local item = world.items[id]
    if not item then return nil end
    return item.name, nil, nil, nil, nil, nil, nil, nil, nil, nil, item.sell
  end,
}
function GetNumLootItems() return #world.loot end
function GetLootSlotType(slot) return world.loot[slot].type end
function GetLootSlotLink(slot) return world.loot[slot].link end
function GetLootSlotInfo(slot) return nil, nil, world.loot[slot].quantity end
function GetLootSourceInfo(slot) return unpack(world.loot[slot].sources) end
function UnitGUID(unit) return world.units[unit] and world.units[unit].guid end
function UnitName(unit) return world.units[unit] and world.units[unit].name end
function CreateFrame()
  local frame = { events = {} }
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:SetScript(_, fn) self.onEvent = fn end
  eventFrame = frame
  return frame
end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(chat, msg) end }
SlashCmdList = {}

local tooltipHook
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) tooltipHook = fn end }
local tooltipLines = {}
GameTooltip = {
  unit = nil,
  GetUnit = function(self) return nil, self.unit end,
  AddLine = function(_, text) table.insert(tooltipLines, text) end,
  AddDoubleLine = function(_, left, right) table.insert(tooltipLines, left .. " | " .. right) end,
}

local function fire(event, ...)
  assert(eventFrame.events[event], "addon didn't register " .. event)
  eventFrame.onEvent(eventFrame, event, ...)
end

local function slash(input)
  chat = {}
  SlashCmdList.FOREVERFARM(input)
  return table.concat(chat, "\n")
end

-- Load the addon files in .toc order with a shared namespace, like the client does.
local ns = {}
for _, file in ipairs({ "Data/PriceData.lua", "Core.lua", "Tooltip.lua", "Commands.lua" }) do
  local chunk = assert(loadfile(ADDON_DIR .. file))
  chunk(ADDON_NAME, ns)
end

local RAPTOR = "Creature-0-1-2-3-686-0000AAAA"
local RAPTOR2 = "Creature-0-1-2-3-686-0000BBBB"
local TROLL = "Creature-0-1-2-3-2640-0000CCCC"

fire("ADDON_LOADED", ADDON_NAME)
fire("PLAYER_ENTERING_WORLD")
ns.prices[4338] = 1200 -- AH beats vendor (250)
slash("start")

-- Corpse 1: raptor with money + 2 mageweave. Targeted, so we learn its name.
world.units.target = { guid = RAPTOR, name = "Jungle Stalker" }
world.loot = {
  { type = 2, sources = { RAPTOR, 300 } },
  { type = 1, link = "|Hitem:4338::|h", quantity = 2, sources = { RAPTOR, 2 } },
}
fire("LOOT_READY")
fire("LOOT_READY") -- duplicate event for the same window must be ignored
world.money = world.money + 300
fire("PLAYER_MONEY")
fire("LOOT_CLOSED")

check("raptor kill counted once", ns.db.mobs[686].kills, 1)
check("raptor name from target", ns.db.mobs[686].name, "Jungle Stalker")
check("raptor money", ns.db.mobs[686].money, 300)
check("raptor mageweave", ns.db.mobs[686].items[4338], 2)

-- Reopen corpse 1 (left the silk behind last time): no double counting.
world.loot = {
  { type = 1, link = "|Hitem:4306::|h", quantity = 1, sources = { RAPTOR, 1 } },
}
world.gameTime = world.gameTime + 10
fire("LOOT_READY")
fire("LOOT_CLOSED")
check("reopened corpse not recounted", ns.db.mobs[686].kills, 1)
check("reopened corpse items not recounted", ns.db.mobs[686].items[4306], nil)

-- AoE loot: raptor 2 + troll in one window; money split by each corpse's share.
world.units.target = nil
world.loot = {
  { type = 2, sources = { RAPTOR2, 100, TROLL, 300 } },
  { type = 1, link = "|Hitem:4306::|h", quantity = 3, sources = { TROLL, 3 } },
}
world.gameTime = world.gameTime + 10
fire("LOOT_READY")
fire("LOOT_CLOSED")
-- Money arrives just after close (within the grace window).
world.gameTime = world.gameTime + 1
world.money = world.money + 400
fire("PLAYER_MONEY")

check("raptor kills after aoe", ns.db.mobs[686].kills, 2)
check("raptor money after aoe", ns.db.mobs[686].money, 400)
check("troll kill", ns.db.mobs[2640].kills, 1)
check("troll money", ns.db.mobs[2640].money, 300)
check("troll silk", ns.db.mobs[2640].items[4306], 3)

-- Money long after looting (e.g. a quest reward) isn't farming income.
world.gameTime = world.gameTime + 60
world.money = world.money + 5000
fire("PLAYER_MONEY")
check("late money ignored for session", ns.db.session.money, 700)

-- Session: 3 kills, 700c money, 2 mageweave @1200 AH + 3 silk @150 vendor.
check("session kills", ns.db.session.kills, 3)
check("session items value", ns.itemsValue(ns.db.session.items), 2 * 1200 + 3 * 150)

-- Reload mid-session: offline time must not count.
world.now = world.now + 600
fire("PLAYER_LOGOUT")
world.now = world.now + 3600
fire("ADDON_LOADED", ADDON_NAME)
check("session paused across reload", ns.sessionSeconds(ns.db.session), 600)
world.now = world.now + 600
local summary = ns.summarizeSession(ns.db.session)
check("session seconds", summary.seconds, 1200)
-- (700 + 2850) copper over 20 minutes → x3 per hour
check("session per hour", summary.perHour, (700 + 2850) * 3)

-- Tooltip on the raptor: value per kill = (400 + 2*1200) / 2 = 1400c = 14s.
GameTooltip.unit = "mouseover"
world.units.mouseover = { guid = RAPTOR, name = "Jungle Stalker" }
tooltipHook(GameTooltip, { guid = RAPTOR })
local text = table.concat(tooltipLines, "\n")
check("tooltip shows per kill", text:find("Per kill | 14s 00c", 1, true) ~= nil, true)
check("tooltip shows top drop", text:find("Mageweave Cloth | x1.0", 1, true) ~= nil
  or text:find("Mageweave Cloth | 100%", 1, true) ~= nil, true)

-- Tooltip on a player or unknown mob adds nothing.
tooltipLines = {}
tooltipHook(GameTooltip, { guid = "Player-1-0000DDDD" })
check("no lines for players", #tooltipLines, 0)

-- Secret GUIDs (in-combat restriction) are skipped rather than erroring.
issecretvalue = function(v) return v == RAPTOR end
tooltipHook(GameTooltip, { guid = RAPTOR })
check("secret guid skipped", #tooltipLines, 0)
issecretvalue = nil

local status = slash("")
check("status prints per hour", status:find("per hour", 1, true) ~= nil, true)
check("status mentions AH prices", status:find("using vendor prices only", 1, true) ~= nil, true)
local stopped = slash("stop")
check("stop ends session", ns.db.session, nil)
check("stop records history", #ns.db.history, 1)
check("stop prints summary", stopped:find("session ended", 1, true) ~= nil, true)
check("top needs 5 kills", slash("top"):find("not enough data", 1, true) ~= nil, true)

print(failures == 0 and "\nall checks passed" or ("\n" .. failures .. " check(s) failed"))
os.exit(failures == 0 and 0 or 1)
