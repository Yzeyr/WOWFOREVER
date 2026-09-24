# Forever Farm

Which mobs are actually worth farming in WoW Forever?

- **In-game addon**: logs every corpse you loot (money and items), tracks farming
  sessions as gold per hour, and adds your own numbers to mob tooltips.
- **Data script**: turns a price list into a Lua file the addon loads, since
  addons can't reach the internet themselves.

Everything is counted from **looting**, not combat, so the Midnight-era in-combat
addon restrictions don't get in the way. Mobs you kill but never loot aren't counted.

## Install

1. Copy `addon/ForeverFarm` into your Forever client's `Interface/AddOns` folder,
   or let the script do it (below).
2. In game: `/ff start`, farm, then `/ff` for the live estimate and `/ff stop` to end.

The `.toc` says `## Interface: 16001`. If the addon shows as out of date, check the real
number in game with `/dump select(4, GetBuildInfo())` and update the `.toc`.

## Commands

| Command | What it does |
|---|---|
| `/ff start` | Start a farming session |
| `/ff` | Session so far: kills/min, gold looted, item value, gold per hour |
| `/ff stop` | End the session and save it to history |
| `/ff top` | Best value per kill among mobs you've looted 5+ times |
| `/ff wipe` | Delete all recorded data (asks for confirmation) |

Hover a mob you've looted before to see value per kill, its best drops, and the
gold/hr you'd make at your current session's kill pace.

## Prices

Item value = AH price from `data/prices.csv` if it beats the vendor price, otherwise
vendor price. Edit the CSV, then (needs Node 22.18+):

```sh
npm install
npm run build-data                                   # writes the addon's Data/PriceData.lua
npm run build-data -- --install "<Forever>/Interface/AddOns"   # ...and copies the addon into WoW
```

Then `/reload` in game. Your history lives in SavedVariables (WTF folder), so
reinstalling the addon never wipes it.

## Development

- `npm test` runs the script tests; `npm run typecheck` checks types.
- `npm run test:addon` runs the addon against a stubbed WoW API and simulates a farming
  session (needs `lua5.1`). The stubs encode assumptions about the real API, so
  testing in the actual client is still the real check.

## Not yet

- Automatic prices from Booty Bay Broker (need to find out if it has an API or export).
- Drop rates and spawn data from outside sources: for now the addon only knows what
  *you* have looted.
- The desktop app with maps.
