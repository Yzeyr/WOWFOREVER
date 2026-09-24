// Turns data/prices.csv into the addon's Data/PriceData.lua, and optionally
// copies the addon into your WoW AddOns folder.
//
//   npm run build-data
//   npm run build-data -- --install "<path to Forever>/Interface/AddOns"
//
// After running, /reload in game to pick up the new prices.

import { cpSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { parseArgs } from "node:util";
import { renderPriceData } from "./lua.ts";
import { parsePricesCsv } from "./prices.ts";

const repoRoot = path.resolve(import.meta.dirname, "../..");
const addonDir = path.join(repoRoot, "addon", "ForeverFarm");

const { values } = parseArgs({
  options: {
    prices: { type: "string", default: path.join(repoRoot, "data", "prices.csv") },
    source: { type: "string", default: "prices.csv" },
    install: { type: "string" },
  },
});

const csvPath = path.resolve(values.prices);
if (!existsSync(csvPath)) {
  console.error(`No price file at ${csvPath}`);
  process.exit(1);
}

let entries;
try {
  entries = parsePricesCsv(readFileSync(csvPath, "utf8"));
} catch (error) {
  console.error((error as Error).message);
  process.exit(1);
}

const outPath = path.join(addonDir, "Data", "PriceData.lua");
writeFileSync(outPath, renderPriceData(entries, { generatedAt: Date.now() / 1000, source: values.source }));
console.log(`Wrote ${entries.length} price(s) to ${path.relative(repoRoot, outPath)}`);

if (values.install) {
  const addonsDir = path.resolve(values.install);
  if (!existsSync(addonsDir)) {
    console.error(`AddOns folder not found: ${addonsDir}`);
    process.exit(1);
  }
  // Only the addon code lives here; your recorded history is in the WTF
  // folder's SavedVariables, so overwriting this never touches it.
  const target = path.join(addonsDir, "ForeverFarm");
  cpSync(addonDir, target, { recursive: true });
  console.log(`Installed addon to ${target}. /reload in game.`);
}
