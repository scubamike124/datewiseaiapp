#!/usr/bin/env node
/**
 * White Glove: App Store Connect subscription automation (plan, then create-only apply).
 *
 * One dependency-free file (Node >= 20, node:crypto signs the ES256 token). White Glove ships it unchanged into a
 * customer repo and runs it in that repo's GitHub Actions with the app's own App Store Connect API key, the same way
 * its build workflows use the key. Amber's server can import it too.
 *
 *   node asc-subscriptions.mjs plan  --spec subscriptions.json [--report report.md] [--json plan.json]
 *   node asc-subscriptions.mjs apply --spec subscriptions.json --expect-plan <sha256 from an approved plan>
 *
 * Safety (the reason this exists instead of clicking in App Store Connect):
 *  - plan is read-only: GET requests only, enforced by the client (`readOnly`), and prints CREATE / UNCHANGED /
 *    CONFLICT for every object.
 *  - apply only CREATES what is missing. The client has no DELETE and no PATCH at all, so nothing that exists can be
 *    removed, renamed, repriced or re-localized by this tool. A difference on an existing object is a CONFLICT for a
 *    person to resolve; apply refuses to run while any CONFLICT exists.
 *  - apply re-reads the live state and recomputes the plan; it runs only if the plan hash equals the one the owner
 *    approved (--expect-plan), so it can never do more than what was reviewed.
 *  - Duplicates: a product id is matched across every subscription group of the app; groups by reference name;
 *    localizations by locale; prices and availability per territory. Before each create the live state is re-read,
 *    and a 409 from Apple is treated as "already exists" (re-read, not retried blindly), so a re-run after an
 *    interrupted apply only creates what is still missing.
 *  - Secrets: the key is only used to sign tokens sent to api.appstoreconnect.apple.com; redirects are refused;
 *    output carries ids, names, prices and Apple error codes, never the key or the token.
 */
import { createPrivateKey, createHash, sign as cryptoSign } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

export const API = "https://api.appstoreconnect.apple.com";
const PERIODS = new Set(["ONE_WEEK", "ONE_MONTH", "TWO_MONTHS", "THREE_MONTHS", "SIX_MONTHS", "ONE_YEAR"]);

export class AscError extends Error {
  constructor(message, { status = 0, code = "", kind = "api" } = {}) {
    super(message);
    this.status = status;
    this.code = code;
    this.kind = kind; // "auth" | "permission" | "conflict" | "not_found" | "rate_limit" | "server" | "network" | "api" | "safety"
  }
}

const b64url = (buf) => Buffer.from(buf).toString("base64").replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");

/** ES256 App Store Connect token (Apple accepts at most 20 minutes; we use 10). */
export function makeToken({ keyId, issuerId, p8, now = Math.floor(Date.now() / 1000) }) {
  if (!/^[A-Z0-9]{10}$/.test(keyId || "")) throw new AscError("Key ID must be the 10-character App Store Connect Key ID", { kind: "auth" });
  if (!/^[0-9a-fA-F-]{36}$/.test(issuerId || "")) throw new AscError("Issuer ID must be the UUID shown in App Store Connect", { kind: "auth" });
  let key;
  try {
    key = createPrivateKey(String(p8 || "").replace(/\\n/g, "\n"));
  } catch {
    throw new AscError("The .p8 is not a valid private key", { kind: "auth" });
  }
  if (key.asymmetricKeyType !== "ec") throw new AscError("The .p8 is not an EC (ES256) key", { kind: "auth" });
  const header = b64url(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" }));
  const payload = b64url(JSON.stringify({ iss: issuerId, iat: now, exp: now + 600, aud: "appstoreconnect-v1" }));
  const sig = cryptoSign("sha256", Buffer.from(`${header}.${payload}`), { key, dsaEncoding: "ieee-p1363" });
  return `${header}.${payload}.${b64url(sig)}`;
}

function classify(status) {
  if (status === 401) return "auth";
  if (status === 403) return "permission";
  if (status === 404) return "not_found";
  if (status === 409) return "conflict";
  if (status === 429) return "rate_limit";
  if (status >= 500) return "server";
  return "api";
}

/**
 * A minimal client: GET (paginated) and POST only. `readOnly` refuses POST. Retries 429/5xx/network up to 3 times.
 */
export function createClient({ keyId, issuerId, p8, fetchImpl = fetch, sleep = (ms) => new Promise((r) => setTimeout(r, ms)), readOnly = true, log = () => {} }) {
  makeToken({ keyId, issuerId, p8 }); // validate the shapes up front, before any request
  let requests = 0;
  async function call(method, pathOrUrl, body) {
    if (method !== "GET" && method !== "POST") throw new AscError(`refused: ${method} is never sent by this tool`, { kind: "safety" });
    if (method === "POST" && readOnly) throw new AscError("refused: plan mode is read-only", { kind: "safety" });
    const url = pathOrUrl.startsWith("https://") ? pathOrUrl : API + pathOrUrl;
    if (!url.startsWith(API + "/")) throw new AscError("refused: only api.appstoreconnect.apple.com is contacted", { kind: "safety" });
    for (let attempt = 0; ; attempt++) {
      requests++;
      let res;
      try {
        res = await fetchImpl(url, {
          method,
          redirect: "error",
          headers: { Authorization: `Bearer ${makeToken({ keyId, issuerId, p8 })}`, "Content-Type": "application/json" },
          body: body ? JSON.stringify(body) : undefined,
        });
      } catch (e) {
        if (attempt < 3) {
          await sleep(500 * 2 ** attempt);
          continue;
        }
        throw new AscError(`network error (${e && e.name ? e.name : "error"}) on ${method} ${new URL(url).pathname}`, { kind: "network" });
      }
      const text = await res.text();
      let json = {};
      try {
        json = text ? JSON.parse(text) : {};
      } catch {
        json = {};
      }
      if (res.ok) {
        log(`${method} ${new URL(url).pathname} -> ${res.status}`);
        return json;
      }
      const kind = classify(res.status);
      const code = ((json.errors || [])[0] || {}).code || "";
      if ((kind === "rate_limit" || kind === "server") && attempt < 3) {
        await sleep(1000 * 2 ** attempt);
        continue;
      }
      const hint =
        kind === "auth"
          ? "Apple rejected the key (wrong Key ID / Issuer ID / .p8, revoked key, or a clock more than a few minutes off)"
          : kind === "permission"
            ? "the key's role cannot do this (App Manager or Admin is needed to create subscriptions)"
            : `Apple returned ${res.status}`;
      throw new AscError(`${method} ${new URL(url).pathname}: ${hint}${code ? ` [${code}]` : ""}`, { status: res.status, code, kind });
    }
  }
  async function getAll(path) {
    const out = { data: [], included: [] };
    let next = path;
    let pages = 0;
    while (next) {
      if (++pages > 20) throw new AscError(`too many pages for ${path}`, { kind: "api" });
      const j = await call("GET", next);
      out.data.push(...(Array.isArray(j.data) ? j.data : j.data ? [j.data] : []));
      out.included.push(...(j.included || []));
      next = j.links && j.links.next ? j.links.next : null;
    }
    return out;
  }
  return {
    get: (p) => call("GET", p),
    getAll,
    post: (p, body) => call("POST", p, body),
    get requests() {
      return requests;
    },
  };
}

// ---------------------------------------------------------------- spec

/** Validate and normalise the desired configuration. Throws AscError(kind "safety") on anything unexpected. */
export function validateSpec(spec) {
  const err = (m) => {
    throw new AscError(`spec: ${m}`, { kind: "safety" });
  };
  if (!spec || typeof spec !== "object") err("not an object");
  if (!/^[A-Za-z0-9.-]{3,155}$/.test(spec.bundleId || "")) err("bundleId missing or invalid");
  const g = spec.group || {};
  if (!g.referenceName || g.referenceName.length > 64) err("group.referenceName missing or too long");
  const terr = (list, where) => {
    if (!Array.isArray(list) || !list.length || list.some((t) => !/^[A-Z]{3}$/.test(t))) err(`${where} must be a list of 3-letter territory codes`);
  };
  const locs = (o, where, withDesc) => {
    if (!o || typeof o !== "object" || !Object.keys(o).length) err(`${where} needs at least one locale`);
    for (const [loc, v] of Object.entries(o)) {
      if (!/^[a-z]{2}(-[A-Z]{2})?$/.test(loc)) err(`${where}: bad locale ${loc}`);
      if (!v || !v.name || v.name.length > (withDesc ? 35 : 75)) err(`${where}.${loc}.name missing or too long`);
      if (withDesc && (!v.description || v.description.length > 55)) err(`${where}.${loc}.description missing or longer than 55`);
    }
  };
  locs(g.localizations, "group.localizations", false);
  if (!Array.isArray(spec.subscriptions) || !spec.subscriptions.length) err("subscriptions must be a non-empty list");
  const ids = new Set();
  for (const s of spec.subscriptions) {
    if (!/^[A-Za-z0-9._]{2,100}$/.test(s.productId || "")) err("productId missing or invalid");
    if (ids.has(s.productId)) err(`duplicate productId ${s.productId} in spec`);
    ids.add(s.productId);
    if (!s.referenceName || s.referenceName.length > 64) err(`${s.productId}: referenceName missing`);
    if (!PERIODS.has(s.period)) err(`${s.productId}: period must be one of ${[...PERIODS].join(", ")}`);
    if (typeof s.familySharable !== "boolean") err(`${s.productId}: familySharable must be true or false (it can never be turned off once on)`);
    if (s.introductoryOffers !== "none") err(`${s.productId}: introductoryOffers must be "none" (offers are not automated)`);
    locs(s.localizations, `${s.productId}.localizations`, true);
    const p = s.price || {};
    if (!/^[A-Z]{3}$/.test(p.baseTerritory || "") || !/^\d+\.\d{2}$/.test(p.customerPrice || "")) err(`${s.productId}: price.baseTerritory and price.customerPrice ("19.99") required`);
    terr(p.territories, `${s.productId}.price.territories`);
    if (!p.territories.includes(p.baseTerritory)) err(`${s.productId}: price.territories must include the base territory`);
    const a = s.availability || {};
    terr(a.territories, `${s.productId}.availability.territories`);
    if (typeof a.availableInNewTerritories !== "boolean") err(`${s.productId}: availability.availableInNewTerritories must be true or false`);
    for (const t of p.territories) if (!a.territories.includes(t)) err(`${s.productId}: priced territory ${t} is not in availability`);
  }
  return spec;
}

// ---------------------------------------------------------------- live state (read-only)

const rel = (o, name) => (((o || {}).relationships || {})[name] || {}).data;

/** Read everything the plan needs. GET only. */
export async function readState(client, spec) {
  const apps = await client.getAll(`/v1/apps?filter[bundleId]=${encodeURIComponent(spec.bundleId)}&fields[apps]=name,bundleId`);
  const app = apps.data.find((a) => a.attributes && a.attributes.bundleId === spec.bundleId);
  if (!app) throw new AscError(`no App Store Connect app record with bundle id ${spec.bundleId}`, { kind: "not_found" });
  const groupsRes = await client.getAll(`/v1/apps/${app.id}/subscriptionGroups?include=subscriptions&limit=50&limit[subscriptions]=50`);
  const allSubs = groupsRes.included.filter((x) => x.type === "subscriptions");
  const groups = [];
  for (const g of groupsRes.data) {
    const locs = await client.getAll(`/v1/subscriptionGroups/${g.id}/subscriptionGroupLocalizations?limit=50`);
    const subIds = new Set((rel(g, "subscriptions") || []).map((d) => d.id));
    groups.push({ id: g.id, referenceName: g.attributes.referenceName, localizations: locs.data.map((l) => ({ id: l.id, ...l.attributes })), subscriptions: allSubs.filter((s) => subIds.has(s.id)).map((s) => ({ id: s.id, ...s.attributes })) });
  }
  // Every subscription the app has (any group), with the details the spec covers.
  const subs = {};
  for (const g of groups) {
    for (const s of g.subscriptions) {
      const [locs, prices, avail, offers] = await Promise.all([
        client.getAll(`/v1/subscriptions/${s.id}/subscriptionLocalizations?limit=50`),
        client.getAll(`/v1/subscriptions/${s.id}/prices?include=subscriptionPricePoint,territory&limit=200`),
        client.get(`/v1/subscriptions/${s.id}/subscriptionAvailability`).catch((e) => {
          if (e.kind === "not_found") return null;
          throw e;
        }),
        client.getAll(`/v1/subscriptions/${s.id}/introductoryOffers?limit=50`),
      ]);
      const points = new Map(prices.included.filter((x) => x.type === "subscriptionPricePoints").map((x) => [x.id, x.attributes]));
      const today = new Date().toISOString().slice(0, 10);
      const priceByTerritory = {};
      for (const p of prices.data) {
        const t = (rel(p, "territory") || {}).id;
        const pp = points.get((rel(p, "subscriptionPricePoint") || {}).id) || {};
        const start = p.attributes && p.attributes.startDate;
        if (!t || (start && start > today)) continue;
        if (!priceByTerritory[t] || (start || "") >= (priceByTerritory[t].startDate || "")) priceByTerritory[t] = { customerPrice: pp.customerPrice, startDate: start || null };
      }
      subs[s.productId] = {
        id: s.id,
        groupId: g.id,
        groupReferenceName: g.referenceName,
        name: s.name,
        state: s.state,
        period: s.subscriptionPeriod,
        familySharable: s.familySharable,
        localizations: Object.fromEntries(locs.data.map((l) => [l.attributes.locale, { id: l.id, name: l.attributes.name, description: l.attributes.description }])),
        prices: priceByTerritory,
        availability: avail && avail.data ? { id: avail.data.id, availableInNewTerritories: avail.data.attributes.availableInNewTerritories, territories: (await client.getAll(`/v1/subscriptionAvailabilities/${avail.data.id}/availableTerritories?limit=200`)).data.map((x) => x.id).sort() } : null,
        introductoryOffers: offers.data.length,
      };
    }
  }
  return { app: { id: app.id, name: app.attributes.name }, groups, subs };
}

/** The price points Apple offers in the base territory, and Apple's equalized points for the other territories. */
export async function resolvePrices(client, subscriptionId, price) {
  const base = await client.getAll(`/v1/subscriptions/${subscriptionId}/pricePoints?filter[territory]=${price.baseTerritory}&limit=200`);
  const point = base.data.find((p) => p.attributes && p.attributes.customerPrice === price.customerPrice);
  if (!point) throw new AscError(`Apple has no ${price.baseTerritory} price point of ${price.customerPrice}`, { kind: "not_found" });
  const result = { [price.baseTerritory]: { pointId: point.id, customerPrice: point.attributes.customerPrice } };
  const others = price.territories.filter((t) => t !== price.baseTerritory);
  if (others.length) {
    const eq = await client.getAll(`/v1/subscriptionPricePoints/${point.id}/equalizations?filter[territory]=${others.join(",")}&include=territory&limit=200`);
    for (const p of eq.data) {
      const t = (rel(p, "territory") || {}).id;
      if (others.includes(t)) result[t] = { pointId: p.id, customerPrice: p.attributes.customerPrice };
    }
    for (const t of others) if (!result[t]) throw new AscError(`Apple returned no equalized price for ${t}`, { kind: "not_found" });
  }
  return result;
}

// ---------------------------------------------------------------- plan

/**
 * Compare the spec with the live state. Returns ordered steps: {op: "create"|"unchanged"|"conflict", what, detail}.
 * `equalized` (optional) holds the price per territory Apple would use, for the report and the hash.
 */
export function computePlan(spec, state, equalized = {}) {
  const steps = [];
  const add = (op, what, detail = "") => steps.push({ op, what, detail });
  const group = state.groups.find((g) => g.referenceName === spec.group.referenceName);
  if (state.groups.filter((g) => g.referenceName === spec.group.referenceName).length > 1) add("conflict", `group "${spec.group.referenceName}"`, "more than one group has this reference name");
  add(group ? "unchanged" : "create", `subscription group "${spec.group.referenceName}"`, group ? `id ${group.id}` : "");
  for (const [loc, v] of Object.entries(spec.group.localizations)) {
    const have = group && group.localizations.find((l) => l.locale === loc);
    if (!have) add("create", `group localization ${loc}`, `name "${v.name}"`);
    else if (have.name !== v.name) add("conflict", `group localization ${loc}`, `live name "${have.name}", wanted "${v.name}" (not changed by this tool)`);
    else add("unchanged", `group localization ${loc}`, `"${have.name}"`);
  }
  for (const s of spec.subscriptions) {
    const have = state.subs[s.productId];
    if (!have) {
      add("create", `subscription ${s.productId}`, `"${s.referenceName}", ${s.period}, family sharing ${s.familySharable ? "on" : "off"}, group level 1`);
    } else {
      const diffs = [];
      if (have.groupReferenceName !== spec.group.referenceName) diffs.push(`it is in group "${have.groupReferenceName}"`);
      if (have.period !== s.period) diffs.push(`period ${have.period}`);
      if (have.familySharable !== s.familySharable) diffs.push(`family sharing ${have.familySharable ? "ON (Apple never allows turning it off)" : "off"}`);
      add(diffs.length ? "conflict" : "unchanged", `subscription ${s.productId}`, diffs.length ? diffs.join("; ") : `id ${have.id}, state ${have.state}`);
    }
    for (const [loc, v] of Object.entries(s.localizations)) {
      const l = have && have.localizations[loc];
      if (!l) add("create", `${s.productId} localization ${loc}`, `"${v.name}" / "${v.description}"`);
      else if (l.name !== v.name || l.description !== v.description) add("conflict", `${s.productId} localization ${loc}`, `live "${l.name}" / "${l.description}" (not changed by this tool)`);
      else add("unchanged", `${s.productId} localization ${loc}`, `"${l.name}"`);
    }
    for (const t of s.price.territories) {
      const live = have && have.prices[t];
      const want = t === s.price.baseTerritory ? s.price.customerPrice : (equalized[s.productId] || {})[t] || "Apple's equalized price";
      if (!live) add("create", `${s.productId} price ${t}`, `${want}${t === s.price.baseTerritory ? "" : ` (equalized from ${s.price.baseTerritory} ${s.price.customerPrice})`}`);
      else if (t === s.price.baseTerritory && live.customerPrice !== s.price.customerPrice) add("conflict", `${s.productId} price ${t}`, `live ${live.customerPrice}, wanted ${s.price.customerPrice} (not changed by this tool)`);
      else add("unchanged", `${s.productId} price ${t}`, `${live.customerPrice}`);
    }
    const extraPriced = have ? Object.keys(have.prices).filter((t) => !s.price.territories.includes(t)) : [];
    if (extraPriced.length) add("conflict", `${s.productId} prices`, `also priced in ${extraPriced.join(", ")} (left as is; review by hand)`);
    const wantTerr = [...s.availability.territories].sort();
    if (!have || !have.availability) add("create", `${s.productId} availability`, `${wantTerr.join(", ")}; new territories ${s.availability.availableInNewTerritories ? "on" : "off"}`);
    else if (have.availability.territories.join(",") !== wantTerr.join(",") || have.availability.availableInNewTerritories !== s.availability.availableInNewTerritories)
      add("conflict", `${s.productId} availability`, `live ${have.availability.territories.join(", ") || "none"}; new territories ${have.availability.availableInNewTerritories ? "on" : "off"} (not changed by this tool)`);
    else add("unchanged", `${s.productId} availability`, wantTerr.join(", "));
    if (have && have.introductoryOffers > 0) add("conflict", `${s.productId} introductory offers`, `${have.introductoryOffers} offer(s) exist; spec wants none (not removed by this tool)`);
    else add("unchanged", `${s.productId} introductory offers`, "none");
  }
  // Anything else in the target group is reported, never touched.
  if (group) {
    const wanted = new Set(spec.subscriptions.map((s) => s.productId));
    for (const s of group.subscriptions) if (!wanted.has(s.productId)) add("conflict", `other subscription ${s.productId} in group`, `state ${s.state}; the spec has no such plan (left as is)`);
  }
  const hash = createHash("sha256").update(JSON.stringify({ spec, steps: steps.map(({ op, what, detail }) => [op, what, detail]) })).digest("hex");
  return { app: state.app, steps, hash, creates: steps.filter((s) => s.op === "create").length, conflicts: steps.filter((s) => s.op === "conflict").length };
}

export function renderReport(plan, { mode = "plan" } = {}) {
  const icon = { create: "CREATE", unchanged: "UNCHANGED", conflict: "CONFLICT" };
  const lines = [
    `### White Glove subscription ${mode === "plan" ? "dry run (read-only)" : "apply"}: ${plan.app.name} (Apple ID ${plan.app.id})`,
    "",
    `- Would create: **${plan.creates}**; conflicts: **${plan.conflicts}**; nothing is ever deleted or edited.`,
    `- Plan hash (approve this exact plan with \`--expect-plan\`): \`${plan.hash}\``,
    "",
    "| Action | Object | Detail |",
    "|---|---|---|",
    ...plan.steps.map((s) => `| ${icon[s.op]} | ${s.what.replace(/\|/g, "/")} | ${String(s.detail).replace(/\|/g, "/")} |`),
  ];
  return lines.join("\n") + "\n";
}

/** Read-only: state, Apple's equalized prices when the subscription exists, and the plan. */
export async function plan(client, spec) {
  validateSpec(spec);
  const state = await readState(client, spec);
  const equalized = {};
  for (const s of spec.subscriptions) {
    const have = state.subs[s.productId];
    if (have) {
      const r = await resolvePrices(client, have.id, s.price);
      equalized[s.productId] = Object.fromEntries(Object.entries(r).map(([t, v]) => [t, v.customerPrice]));
    }
  }
  return { state, plan: computePlan(spec, state, equalized) };
}

// ---------------------------------------------------------------- apply (create-only)

const body = (type, attributes, relationships) => ({ data: { type, attributes, relationships } });
const ref = (type, id) => ({ data: { type, id } });

/**
 * Create what the approved plan says is missing. Re-reads the live state first and refuses if the plan hash differs
 * from `expectPlan`, or if any conflict exists. Every create is preceded by a fresh check, and a 409 means "someone
 * (or an interrupted earlier run) created it": the object is re-read, never created twice.
 */
export async function apply(client, spec, { expectPlan, log = () => {} }) {
  if (!/^[0-9a-f]{64}$/.test(expectPlan || "")) throw new AscError("apply needs --expect-plan <sha256> from an approved dry run", { kind: "safety" });
  const first = await plan(client, spec);
  if (first.plan.hash !== expectPlan) throw new AscError(`the live plan (${first.plan.hash}) is not the approved plan; run a new dry run and approve it`, { kind: "safety" });
  if (first.plan.conflicts) throw new AscError(`${first.plan.conflicts} conflict(s); resolve them by hand first`, { kind: "safety" });
  const created = [];
  const tolerate409 = async (fn, what) => {
    try {
      const r = await fn();
      created.push(what);
      log(`created ${what}`);
      return r;
    } catch (e) {
      if (e.kind === "conflict") {
        log(`${what}: Apple says it already exists (409); keeping the existing one`);
        return null;
      }
      throw e;
    }
  };
  let state = first.state;
  let group = state.groups.find((g) => g.referenceName === spec.group.referenceName);
  if (!group) {
    await tolerate409(() => client.post("/v1/subscriptionGroups", body("subscriptionGroups", { referenceName: spec.group.referenceName }, { app: ref("apps", state.app.id) })), `group ${spec.group.referenceName}`);
    state = await readState(client, spec);
    group = state.groups.find((g) => g.referenceName === spec.group.referenceName);
    if (!group) throw new AscError("the group was not found after creating it", { kind: "api" });
  }
  for (const [loc, v] of Object.entries(spec.group.localizations)) {
    if (group.localizations.some((l) => l.locale === loc)) continue;
    await tolerate409(() => client.post("/v1/subscriptionGroupLocalizations", body("subscriptionGroupLocalizations", { name: v.name, locale: loc }, { subscriptionGroup: ref("subscriptionGroups", group.id) })), `group localization ${loc}`);
  }
  for (const s of spec.subscriptions) {
    state = await readState(client, spec);
    let have = state.subs[s.productId];
    if (!have) {
      await tolerate409(
        () =>
          client.post(
            "/v1/subscriptions",
            body("subscriptions", { name: s.referenceName, productId: s.productId, subscriptionPeriod: s.period, familySharable: s.familySharable, groupLevel: 1, ...(s.reviewNote ? { reviewNote: s.reviewNote } : {}) }, { group: ref("subscriptionGroups", group.id) }),
          ),
        `subscription ${s.productId}`,
      );
      state = await readState(client, spec);
      have = state.subs[s.productId];
      if (!have) throw new AscError(`subscription ${s.productId} not found after creating it`, { kind: "api" });
    }
    for (const [loc, v] of Object.entries(s.localizations)) {
      if (have.localizations[loc]) continue;
      await tolerate409(() => client.post("/v1/subscriptionLocalizations", body("subscriptionLocalizations", { name: v.name, description: v.description, locale: loc }, { subscription: ref("subscriptions", have.id) })), `${s.productId} localization ${loc}`);
    }
    if (!have.availability) {
      await tolerate409(
        () =>
          client.post(
            "/v1/subscriptionAvailabilities",
            body("subscriptionAvailabilities", { availableInNewTerritories: s.availability.availableInNewTerritories }, { subscription: ref("subscriptions", have.id), availableTerritories: { data: s.availability.territories.map((t) => ({ type: "territories", id: t })) } }),
          ),
        `${s.productId} availability`,
      );
    }
    const points = await resolvePrices(client, have.id, s.price);
    for (const t of s.price.territories) {
      if (have.prices[t]) continue;
      await tolerate409(
        () =>
          client.post(
            "/v1/subscriptionPrices",
            body("subscriptionPrices", { startDate: null, preserveCurrentPrice: false }, { subscription: ref("subscriptions", have.id), subscriptionPricePoint: ref("subscriptionPricePoints", points[t].pointId), territory: ref("territories", t) }),
          ),
        `${s.productId} price ${t} ${points[t].customerPrice}`,
      );
    }
  }
  const after = await plan(client, spec);
  return { created, after: after.plan };
}

// ---------------------------------------------------------------- CLI

function arg(name) {
  const i = process.argv.indexOf(name);
  return i > 0 ? process.argv[i + 1] : undefined;
}

async function main() {
  const mode = process.argv[2];
  if (mode !== "plan" && mode !== "apply") {
    console.error("usage: asc-subscriptions.mjs plan|apply --spec file.json [--report out.md] [--json out.json] [--expect-plan sha256]");
    process.exit(2);
  }
  const spec = JSON.parse(readFileSync(arg("--spec") || "subscriptions.json", "utf8"));
  const client = createClient({ keyId: (process.env.ASC_KEY_ID || "").trim(), issuerId: (process.env.ASC_ISSUER_ID || "").trim(), p8: process.env.ASC_KEY_P8 || "", readOnly: mode === "plan" });
  try {
    if (mode === "plan") {
      const { plan: p } = await plan(client, spec);
      const report = renderReport(p);
      process.stdout.write(report);
      if (arg("--report")) writeFileSync(arg("--report"), report);
      if (arg("--json")) writeFileSync(arg("--json"), JSON.stringify(p, null, 2));
      if (process.env.GITHUB_STEP_SUMMARY) writeFileSync(process.env.GITHUB_STEP_SUMMARY, report, { flag: "a" });
    } else {
      const r = await apply(client, spec, { expectPlan: arg("--expect-plan"), log: (m) => console.log(m) });
      const report = `Created ${r.created.length}: ${r.created.join("; ") || "nothing"}\n\n` + renderReport(r.after, { mode: "apply" });
      process.stdout.write(report);
      if (process.env.GITHUB_STEP_SUMMARY) writeFileSync(process.env.GITHUB_STEP_SUMMARY, report, { flag: "a" });
    }
    console.error(`requests: ${client.requests}`);
  } catch (e) {
    console.error(`::error::${e instanceof AscError ? `${e.kind}: ${e.message}` : "unexpected error"}`);
    process.exit(1);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) main();
