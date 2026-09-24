import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { luaString, renderPriceData } from "../src/lua.ts";
import { parseMoney } from "../src/money.ts";
import { parsePricesCsv } from "../src/prices.ts";

test("parseMoney reads the common formats", () => {
  assert.equal(parseMoney("12g 34s 5c"), 123405);
  assert.equal(parseMoney("12g34s"), 123400);
  assert.equal(parseMoney("80s"), 8000);
  assert.equal(parseMoney("1.5g"), 15000);
  assert.equal(parseMoney(" 250 "), 250);
  assert.equal(parseMoney("3G 2S"), 30200);
});

test("parseMoney rejects junk", () => {
  assert.throws(() => parseMoney(""));
  assert.throws(() => parseMoney("12 gold"));
  assert.throws(() => parseMoney("12g banana"));
});

test("parsePricesCsv skips header, comments and blanks, keeps notes", () => {
  const entries = parsePricesCsv(
    ["itemId,price,note", "# cloth", "", "4338,1g 20s,Mageweave Cloth", "14047, 3g ,Runecloth, bulk"].join("\n"),
  );
  assert.deepEqual(entries, [
    { itemId: 4338, copper: 12000, note: "Mageweave Cloth" },
    { itemId: 14047, copper: 30000, note: "Runecloth, bulk" },
  ]);
});

test("parsePricesCsv reports the line of a mistake", () => {
  assert.throws(() => parsePricesCsv("4338,1g\n4338,2g"), /line 2: item 4338 already priced on line 1/);
  assert.throws(() => parsePricesCsv("4338,1g\nabc,2g"), /line 2/);
  assert.throws(() => parsePricesCsv("4338,lots"), /line 1/);
});

test("luaString escapes quotes, backslashes and newlines", () => {
  assert.equal(luaString('a "b" \\ c\nd'), '"a \\"b\\" \\\\ c\\nd"');
});

test("rendered PriceData.lua is valid Lua the addon can load", (t) => {
  const lua = renderPriceData(
    [
      { itemId: 14047, copper: 30000, note: "Runecloth" },
      { itemId: 4338, copper: 12000, note: "evil\nnote -- ]]" },
    ],
    { generatedAt: 1700000000.7, source: 'Booty "Bay"' },
  );
  assert.match(lua, /\[4338\] = 12000,[^\n]*\n {2}\[14047\] = 30000/); // sorted by id

  const dir = mkdtempSync(path.join(tmpdir(), "ff-"));
  const dataFile = path.join(dir, "PriceData.lua");
  writeFileSync(dataFile, lua);
  const probe = `
    local ns = {}
    assert(loadfile(${luaString(dataFile)}))("ForeverFarm", ns)
    io.write(ns.prices[4338], " ", ns.prices[14047], " ", ns.priceMeta.count, " ", ns.priceMeta.source, " ", ns.priceMeta.generatedAt)
  `;
  let output: string;
  try {
    output = execFileSync("lua5.1", ["-e", probe], { encoding: "utf8" });
  } catch {
    t.skip("lua5.1 not installed");
    return;
  }
  assert.equal(output, '12000 30000 2 Booty "Bay" 1700000000');
});
