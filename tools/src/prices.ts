import { parseMoney } from "./money.ts";

export interface PriceEntry {
  itemId: number;
  copper: number;
  note?: string;
}

// Format: one "itemId,price,note" per line. Blank lines, "#" comments and a
// header row are skipped. Duplicates are an error rather than last-one-wins,
// since a duplicate is almost always a copy-paste mistake.
export function parsePricesCsv(csv: string): PriceEntry[] {
  const entries: PriceEntry[] = [];
  const seenAt = new Map<number, number>();

  csv.split(/\r?\n/).forEach((rawLine, index) => {
    const lineNo = index + 1;
    const line = rawLine.trim();
    if (line === "" || line.startsWith("#")) return;

    const [rawId = "", rawPrice = "", ...noteCells] = line.split(",");
    const idCell = rawId.trim();
    const priceCell = rawPrice.trim();
    if (!/^\d+$/.test(idCell)) {
      if (entries.length === 0 && /item/i.test(idCell)) return; // header row
      throw new Error(`prices.csv line ${lineNo}: "${idCell}" isn't an item id`);
    }

    const itemId = Number(idCell);
    const previous = seenAt.get(itemId);
    if (previous !== undefined) {
      throw new Error(`prices.csv line ${lineNo}: item ${itemId} already priced on line ${previous}`);
    }

    let copper: number;
    try {
      copper = parseMoney(priceCell);
    } catch (error) {
      throw new Error(`prices.csv line ${lineNo}: ${(error as Error).message}`);
    }

    seenAt.set(itemId, lineNo);
    const note = noteCells.join(",").trim();
    entries.push(note ? { itemId, copper, note } : { itemId, copper });
  });

  return entries;
}
