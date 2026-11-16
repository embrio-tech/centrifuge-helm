import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { fileURLToPath } from "node:url";

const EXAMPLES = {
  eu: fileURLToPath(new URL("../examples/argocd-cfg-api-erpc-eu-v0-5.yaml", import.meta.url)),
  us: fileURLToPath(new URL("../examples/argocd-cfg-api-erpc-us-v0-5.yaml", import.meta.url)),
};
const FAST_CHAINS = [42161, 143, 56, 196, 8453, 10, 5042];
const TOP_THREE = [42161, 143, 56];
const HOUR = 3_600_000;
const NOW = 1_700_000_000_000;

const predicate = () => () => false;
const keep = function () {
  return this;
};
for (const name of [
  "removeCordoned",
  "excludeIf",
  "whenEmpty",
  "preferTag",
  "sortByScore",
  "probeExcluded",
]) {
  Object.defineProperty(Array.prototype, name, {
    configurable: true,
    value: keep,
    writable: true,
  });
}
globalThis.all = predicate;
globalThis.any = predicate;
globalThis.samplesAbove = predicate;
globalThis.errorRateAbove = predicate;
globalThis.throttleRateAbove = predicate;
globalThis.latencyAbove = predicate;
globalThis.latencyDeviationAbove = predicate;
globalThis.blockNumberLagAbove = predicate;
globalThis.blockSecondsLagAbove = predicate;
globalThis.PREFER_FASTEST = "PREFER_FASTEST";

function upstream(id, endpoint) {
  return {
    id,
    endpoint,
    metrics: { blockHeadLag: 0, errorRate: 0 },
    score: 1,
  };
}

function upstreamsFor(chain) {
  if (chain === 999) {
    return [
      upstream("hl-quicknode-evm", "https://example.quiknode.pro/evm"),
      upstream("hl-alchemy-evm", "https://hyperliquid-mainnet.g.alchemy.com/v2/key"),
      upstream("hl-quicknode-nanoreth", "https://example.quiknode.pro/nanoreth"),
    ];
  }
  return [
    upstream(`quicknode-evm:${chain}`, "https://example.quiknode.pro"),
    upstream(`alchemy-evm:${chain}`, "https://example.g.alchemy.com/v2/key"),
    upstream(`drpc-evm:${chain}`, "https://lb.drpc.live"),
  ];
}

function vendorOf(upstream) {
  const id = upstream.id;
  if (id.startsWith("quicknode-") || id.startsWith("hl-quicknode")) return "quicknode";
  if (id.startsWith("alchemy-") || id.startsWith("hl-alchemy")) return "alchemy";
  if (id.startsWith("drpc-")) return "drpc";
  const endpoint = upstream.endpoint;
  if (endpoint.includes("alchemy")) return "alchemy";
  if (endpoint.includes("quiknode") || endpoint.includes("quicknode")) return "quicknode";
  if (endpoint.includes("drpc")) return "drpc";
  return "other";
}

function evalFuncs(path) {
  const lines = readFileSync(path, "utf8").split("\n");
  const funcs = [];
  for (let i = 0; i < lines.length; i++) {
    const match = lines[i].match(/^(\s*)evalFunc: \|$/);
    if (!match) continue;
    const baseIndent = match[1].length;
    const body = [];
    let j = i + 1;
    while (j < lines.length) {
      const line = lines[j];
      const indent = line.match(/^ */)[0].length;
      if (line.trim() !== "" && indent <= baseIndent) break;
      body.push(line);
      j++;
    }
    const contentIndent = Math.min(
      ...body.filter((line) => line.trim() !== "").map((line) => line.match(/^ */)[0].length),
    );
    funcs.push({
      line: i + 1,
      code: body.map((line) => line.slice(contentIndent)).join("\n"),
    });
    i = j - 1;
  }
  return funcs;
}

function compile(code) {
  return new Function(`return (${code})`)();
}

for (const [region, path] of Object.entries(EXAMPLES)) {
  const funcs = evalFuncs(path);
  const generic = funcs.find((func) => func.code.includes("VENDOR_ORDER"));
  const hyperliquid = funcs.find((func) => func.code.includes("hl-quicknode-evm"));
  const avalanche = funcs.find((func) => func.code.includes("isAvax"));

  assert.ok(generic, `${region}: generic selection policy missing`);
  assert.ok(hyperliquid, `${region}: Hyperliquid selection policy missing`);
  assert.ok(avalanche, `${region}: Avalanche selection policy missing`);

  test(`${region}: top three fast chains use different vendors every hour`, () => {
    const policy = compile(generic.code);
    for (let hour = 0; hour < 24; hour++) {
      const now = NOW + hour * HOUR;
      const vendors = TOP_THREE.map((chain) =>
        vendorOf(
          policy(upstreamsFor(chain), {
            method: "*",
            network: `evm:${chain}`,
            now,
          })[0],
        ),
      );
      assert.equal(
        new Set(vendors).size,
        3,
        `${region} hour ${hour}: ${JSON.stringify(vendors)}`,
      );
    }
  });

  test(`${region}: the whole fast set spreads across all three vendors`, () => {
    const policy = compile(generic.code);
    for (let hour = 0; hour < 24; hour++) {
      const now = NOW + hour * HOUR;
      const vendors = FAST_CHAINS.map((chain) =>
        vendorOf(
          policy(upstreamsFor(chain), {
            method: "*",
            network: `evm:${chain}`,
            now,
          })[0],
        ),
      );
      assert.equal(new Set(vendors).size, 3, `${region} hour ${hour}: ${JSON.stringify(vendors)}`);
    }
  });

  test(`${region}: custom policies return a primary`, () => {
    for (const [name, func, chain] of [
      ["Hyperliquid", hyperliquid, 999],
      ["Avalanche", avalanche, 43114],
    ]) {
      const result = compile(func.code)(upstreamsFor(chain), {
        method: "*",
        network: `evm:${chain}`,
        now: NOW,
      });
      assert.ok(Array.isArray(result) && result.length > 0, `${region}: ${name} returned no primary`);
      assert.ok(result[0].id, `${region}: ${name} primary has no id`);
    }
  });
}

test("every region balances all fast chains across the three vendors", () => {
  for (const [region, path] of Object.entries(EXAMPLES)) {
    const funcs = evalFuncs(path);
    const generic = compile(funcs.find((func) => func.code.includes("VENDOR_ORDER")).code);
    const hyperliquid = compile(funcs.find((func) => func.code.includes("hl-quicknode-evm")).code);
    const avalanche = compile(funcs.find((func) => func.code.includes("isAvax")).code);
    const allFast = [...FAST_CHAINS, 999, 43114];
    for (let hour = 0; hour < 24; hour++) {
      const now = NOW + hour * HOUR;
      const counts = { alchemy: 0, drpc: 0, quicknode: 0 };
      for (const chain of allFast) {
        const policy = chain === 999 ? hyperliquid : chain === 43114 ? avalanche : generic;
        const primary = policy(upstreamsFor(chain), {
          method: "*",
          network: `evm:${chain}`,
          now,
        })[0];
        counts[vendorOf(primary)] += 1;
      }
      assert.equal(
        Object.values(counts).every((count) => count >= 2 && count <= 4),
        true,
        `${region} hour ${hour}: ${JSON.stringify(counts)}`,
      );
    }
  }
});

test("EU and US never share a fast-chain vendor for the same hour", () => {
  const eu = compile(evalFuncs(EXAMPLES.eu).find((func) => func.code.includes("VENDOR_ORDER")).code);
  const us = compile(evalFuncs(EXAMPLES.us).find((func) => func.code.includes("VENDOR_ORDER")).code);
  for (let hour = 0; hour < 24; hour++) {
    const now = NOW + hour * HOUR;
    for (const chain of FAST_CHAINS) {
      const euVendor = vendorOf(eu(upstreamsFor(chain), { method: "*", network: `evm:${chain}`, now })[0]);
      const usVendor = vendorOf(us(upstreamsFor(chain), { method: "*", network: `evm:${chain}`, now })[0]);
      assert.notEqual(euVendor, usVendor, `chain ${chain} hour ${hour}: both ${euVendor}`);
    }
  }
});
