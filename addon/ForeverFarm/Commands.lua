local _, ns = ...

local MIN_KILLS_FOR_TOP = 5

local function say(message)
  DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Forever Farm:|r " .. message)
end

local function formatDuration(seconds)
  local minutes = math.floor(seconds / 60)
  if minutes < 60 then return minutes .. "m" end
  return string.format("%dh %02dm", math.floor(minutes / 60), minutes % 60)
end

local function printSummary(session, label)
  local s = ns.summarizeSession(session)
  say(string.format("%s %s in %s", label, formatDuration(s.seconds), session.zone or "?"))
  say(string.format("  %d kills (%.1f/min) · looted gold %s · items %s",
    s.kills, s.killsPerMinute, ns.formatMoney(s.money), ns.formatMoney(s.itemsValue)))
  say(string.format("  ≈ |cff4dff4d%s per hour|r", ns.formatMoney(s.perHour)))
  if s.seconds < 180 then
    say("  (under 3 minutes: the estimate will jump around for a bit)")
  end
end

local function priceAge()
  local meta = ns.priceMeta
  if not meta or meta.count == 0 then
    return "no AH prices loaded: using vendor prices only"
  end
  local days = math.floor((time() - meta.generatedAt) / 86400)
  return string.format("%d AH prices from %s, %d day(s) old", meta.count, meta.source, days)
end

local function printTop()
  local ranked = {}
  for npcId, mob in pairs(ns.db.mobs) do
    if mob.kills >= MIN_KILLS_FOR_TOP then
      table.insert(ranked, { npcId = npcId, mob = mob, perKill = ns.valuePerKill(mob) })
    end
  end
  if #ranked == 0 then
    say("not enough data yet: loot at least " .. MIN_KILLS_FOR_TOP .. " of a mob to rank it.")
    return
  end
  table.sort(ranked, function(a, b) return a.perKill > b.perKill end)
  say("best value per kill:")
  for i = 1, math.min(5, #ranked) do
    local entry = ranked[i]
    say(string.format("  %d. %s: %s (%d looted)", i, entry.mob.name or ("npc " .. entry.npcId),
      ns.formatMoney(entry.perKill), entry.mob.kills))
  end
end

local commands = {}

function commands.start()
  if ns.db.session then
    say("a session is already running. /ff stop first.")
    return
  end
  ns.startSession()
  say("session started in " .. (ns.db.session.zone or "?") .. ". Go farm!")
end

function commands.stop()
  local session = ns.stopSession()
  if not session then
    say("no session running. /ff start to begin one.")
    return
  end
  printSummary(session, "session ended:")
end

function commands.status()
  if ns.db.session then
    printSummary(ns.db.session, "session running:")
  else
    say("no session running. /ff start to begin one.")
  end
  say(priceAge())
end

commands.top = printTop

function commands.wipe(arg)
  if arg ~= "confirm" then
    say("this deletes all mob and session history. Type /ff wipe confirm to do it.")
    return
  end
  ns.db.mobs, ns.db.history, ns.db.session = {}, {}, nil
  say("all data wiped.")
end

function commands.help()
  say("/ff start · /ff stop · /ff (status) · /ff top · /ff wipe")
end

SLASH_FOREVERFARM1 = "/ff"
SLASH_FOREVERFARM2 = "/foreverfarm"
SlashCmdList.FOREVERFARM = function(input)
  local command, arg = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  command = command:lower()
  if command == "" then command = "status" end
  local handler = commands[command] or commands.help
  handler(arg)
end
