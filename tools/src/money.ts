const COPPER_PER = { g: 10000, s: 100, c: 1 } as const;

// Accepts whatever is easiest to paste from a price site: "12g 34s 5c",
// "1.5g", "80s", or a bare copper integer like "123405".
export function parseMoney(text: string): number {
  const input = text.trim().toLowerCase();
  if (/^\d+$/.test(input)) return Number(input);

  let total = 0;
  let matchedAny = false;
  const leftover = input.replace(/(\d+(?:\.\d+)?)\s*([gsc])/g, (_, amount: string, unit: keyof typeof COPPER_PER) => {
    total += Number(amount) * COPPER_PER[unit];
    matchedAny = true;
    return "";
  });
  if (!matchedAny || leftover.trim() !== "") {
    throw new Error(`Can't read "${text}" as money (try "12g 34s", "80s" or a copper amount)`);
  }
  return Math.round(total);
}
