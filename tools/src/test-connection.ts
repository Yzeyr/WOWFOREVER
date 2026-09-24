// Checks your Blizzard API key works, and which game versions ("namespaces")
// list realms. The point is to find out whether Forever's realms, beta
// included, are in the public API at all before building a price fetcher.
//
//   npm run test-connection
//   npm run test-connection -- --find "Realm Name"
//   npm run test-connection -- --region eu --env "C:\path\to\.env"

import { existsSync } from "node:fs";
import path from "node:path";
import { parseArgs } from "node:util";

const repoRoot = path.resolve(import.meta.dirname, "../..");

// The first three are known WoW namespaces; "forever" is a guess at what a
// Forever-specific one would be called. Whichever lists your realm wins.
const NAMESPACE_KINDS = ["dynamic", "dynamic-classic", "dynamic-classic1x", "dynamic-forever"];

const { values } = parseArgs({
  options: {
    env: { type: "string", default: path.join(repoRoot, ".env") },
    region: { type: "string" },
    find: { type: "string" },
  },
});

const envPath = path.resolve(values.env);
if (!existsSync(envPath)) {
  console.error(`No key file at ${envPath}.
Create it with these two lines (values from develop.battle.net):

BLIZZARD_CLIENT_ID=your-client-id
BLIZZARD_CLIENT_SECRET=your-client-secret
`);
  process.exit(1);
}
process.loadEnvFile(envPath);

const clientId = process.env.BLIZZARD_CLIENT_ID?.trim();
const clientSecret = process.env.BLIZZARD_CLIENT_SECRET?.trim();
if (!clientId || !clientSecret) {
  console.error(`${envPath} needs both BLIZZARD_CLIENT_ID and BLIZZARD_CLIENT_SECRET.`);
  process.exit(1);
}

async function getToken(id: string, secret: string): Promise<string> {
  const response = await fetch("https://oauth.battle.net/token", {
    method: "POST",
    headers: {
      Authorization: `Basic ${Buffer.from(`${id}:${secret}`).toString("base64")}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });
  if (!response.ok) {
    throw new Error(`Blizzard rejected the key (HTTP ${response.status}). Check the Client ID and Secret.`);
  }
  const body = (await response.json()) as { access_token: string };
  return body.access_token;
}

interface RealmIndex {
  realms: { name: string; slug: string }[];
}

let token: string;
try {
  token = await getToken(clientId, clientSecret);
} catch (error) {
  // fetch throws a bare "fetch failed" on network trouble; say what that means.
  const message = (error as Error).message;
  console.error(message === "fetch failed" ? "Couldn't reach battle.net. Check your internet connection." : message);
  process.exit(1);
}
console.log("Key works: got an access token.\n");

const regions = values.region ? [values.region.toLowerCase()] : ["eu", "us"];
const needle = values.find?.toLowerCase();

for (const region of regions) {
  for (const kind of NAMESPACE_KINDS) {
    const namespace = `${kind}-${region}`;
    const url = `https://${region}.api.blizzard.com/data/wow/realm/index?namespace=${namespace}&locale=en_US`;
    const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (!response.ok) {
      console.log(`✗ ${namespace}: not available (HTTP ${response.status})`);
      continue;
    }
    const { realms } = (await response.json()) as RealmIndex;
    const names = realms.map((realm) => realm.name).sort();
    if (needle) {
      const matches = names.filter((name) => name.toLowerCase().includes(needle));
      console.log(`✓ ${namespace}: ${realms.length} realms, matches: ${matches.length ? matches.join(", ") : "none"}`);
    } else {
      const preview = names.slice(0, 8).join(", ");
      console.log(`✓ ${namespace}: ${realms.length} realms (${preview}${names.length > 8 ? ", ..." : ""})`);
    }
  }
}
