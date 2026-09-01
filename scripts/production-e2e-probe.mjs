/**
 * DateWise production E2E probe against live Worker + App Store metadata.
 * Does NOT use local mock AI — hits production photo-coach worker.
 */
import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";

const WORKER = "https://datewise-photo-coach.scubamike124.workers.dev";
const APPSTORE_ID = "6780110141";
const SUPABASE = "https://cprnegusibbmcyltylzk.supabase.co";
const ANON =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNwcm5lZ3VzaWJibWN5bHR5bHprIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA3ODU3MzMsImV4cCI6MjA5NjM2MTczM30.8OQ6Bm0u6Jb7Z4zfWKmWuTRyjTXA2_-P1xl7ru6mE8E";

const out = [];
function log(section, status, detail, extra = {}) {
  out.push({ section, status, detail, ...extra, at: new Date().toISOString() });
  console.log(`[${status}] ${section}: ${detail}`);
}

async function fetchText(url, init = {}) {
  const t0 = Date.now();
  const res = await fetch(url, { ...init, cache: "no-store" });
  const text = await res.text();
  return { res, text, ms: Date.now() - t0 };
}

function parseSse(text) {
  return text
    .split(/\r?\n/)
    .filter((l) => l.startsWith("data:"))
    .map((l) => l.slice(5).trim())
    .filter((l) => l && l !== "[DONE]")
    .map((l) => {
      try {
        const j = JSON.parse(l);
        return typeof j.response === "string" ? j.response : "";
      } catch {
        return "";
      }
    })
    .join("");
}

async function chat(messages, label) {
  const { res, text, ms } = await fetchText(WORKER, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "text/event-stream" },
    body: JSON.stringify({ tier: "magnet", messages }),
  });
  const reply = parseSse(text);
  const ok = res.ok && reply.length > 40;
  log(
    label,
    ok ? "PASS" : "FAIL",
    ok ? `reply ${reply.length} chars in ${ms}ms` : `HTTP ${res.status} chars=${reply.length} ms=${ms}`,
    { replyPreview: reply.slice(0, 280), ms, replyLen: reply.length },
  );
  return reply;
}

/** Minimal valid JPEG (1x1) */
function tinyJpegBase64() {
  const hex =
    "ffd8ffe000104a46494600010100000100010000ffdb004300080606070605080707070909080a0c140d0c0b0b0c1912130f141d1a1f1e1d1a1c1c20242e2720222c231c1c2837292c30313434341f27393d38323c2e333432ffdb0043010909090c0b0c180d0d1832211c213232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232ffc00011080001000103011100021100031101ffc40014000100000000000000000000000000000000ffc40014100100000000000000000000000000000000ffda000c0301000210031000003f00bf80ffd9";
  return Buffer.from(hex, "hex").toString("base64");
}

async function main() {
  // 1. App Store live version
  try {
    const { res, text } = await fetchText(`https://itunes.apple.com/lookup?id=${APPSTORE_ID}`);
    const j = JSON.parse(text);
    const r = j.results?.[0];
    if (r) {
      log(
        "App Store listing",
        "PASS",
        `version=${r.version} bundle=${r.bundleId} name=${r.trackName} released=${r.currentVersionReleaseDate}`,
        { version: r.version, bundleId: r.bundleId },
      );
    } else log("App Store listing", "FAIL", "no results");
  } catch (e) {
    log("App Store listing", "FAIL", String(e.message || e));
  }

  // 2. Worker version
  try {
    const { res, text, ms } = await fetchText(`${WORKER}/?version`);
    const j = JSON.parse(text);
    log("Production Worker", res.ok ? "PASS" : "FAIL", `${text} (${ms}ms)`, { worker: j });
  } catch (e) {
    log("Production Worker", "FAIL", String(e.message || e));
  }

  // 3. Site
  try {
    const { res, ms } = await fetchText("https://datewiseai.com/");
    log("Marketing site datewiseai.com", res.ok ? "PASS" : "FAIL", `HTTP ${res.status} (${ms}ms)`);
  } catch (e) {
    log("Marketing site datewiseai.com", "FAIL", String(e.message || e));
  }

  // 4. Supabase DNS/auth
  try {
    const { res, text, ms } = await fetchText(`${SUPABASE}/auth/v1/settings`, {
      headers: { apikey: ANON, Authorization: `Bearer ${ANON}` },
    });
    log("Supabase auth settings", res.ok ? "PASS" : "FAIL", `HTTP ${res.status} (${ms}ms) ${text.slice(0, 120)}`);
  } catch (e) {
    log(
      "Supabase auth backend",
      "FAIL",
      `UNREACHABLE: ${e.message || e} — project host NXDOMAIN; signup/login cannot work in production`,
    );
  }

  // 5. Profile coach — different goals must differ
  const serious = await chat(
    [
      {
        role: "user",
        content:
          "Profile coach. Goal: SERIOUS long-term relationship. Age 34. Bio: 'Engineer who loves hiking and cooking. Looking for someone genuine.' Give strengths, weaknesses, and 3 rewrite suggestions tied to THIS bio.",
      },
    ],
    "Profile coach — serious relationship",
  );
  const casual = await chat(
    [
      {
        role: "user",
        content:
          "Profile coach. Goal: CASUAL dating only, no commitment. Age 26. Bio: 'Weekend adventurer, karaoke addict, always down for tacos and spontaneous road trips.' Give strengths, weaknesses, and 3 rewrite suggestions tied to THIS bio.",
      },
    ],
    "Profile coach — casual dating",
  );
  const overlap =
    serious && casual
      ? [...serious.toLowerCase().split(/\W+/)].filter((w) => w.length > 5 && casual.toLowerCase().includes(w)).length
      : 0;
  const distinct =
    serious.length > 40 &&
    casual.length > 40 &&
    !serious.slice(0, 120).includes(casual.slice(0, 80)) &&
    (serious.toLowerCase().includes("hike") ||
      serious.toLowerCase().includes("engineer") ||
      serious.toLowerCase().includes("cook") ||
      casual.toLowerCase().includes("karaoke") ||
      casual.toLowerCase().includes("taco") ||
      casual.toLowerCase().includes("road"));
  log(
    "Profile coach personalization",
    distinct ? "PASS" : "FAIL",
    distinct
      ? `Serious vs casual replies differ and reference supplied details (token-ish overlap=${overlap})`
      : "Replies too similar or not grounded in supplied bios",
  );

  // 6. Message coach scenarios
  const scenarios = [
    [
      "Message coach — opener",
      "She likes rock climbing and has a golden retriever in her photos. Write 3 distinct opening messages. No hey/hi alone.",
    ],
    [
      "Message coach — early convo",
      "Conversation so far:\nMe: How was your weekend hike?\nHer: Amazing — we hit the ridge at sunrise.\nSuggest 3 replies that continue interest without being clingy.",
    ],
    [
      "Message coach — ask for date",
      "We've been texting 5 days about coffee and indie films. Suggest 3 ways to ask her out this weekend. Keep it low-pressure.",
    ],
    [
      "Message coach — stalled",
      "Last messages:\nMe: Want to grab coffee Saturday?\nHer: Maybe, I'll let you know.\n(2 days silence)\nSuggest 3 follow-ups that aren't needy.",
    ],
    [
      "Message coach — short replies",
      "She only replies 'lol' and 'nice'. Suggest 3 pivots to reopen a real conversation.",
    ],
    [
      "Message coach — after date",
      "We had a great first date at a taco place yesterday. Suggest 3 follow-up texts for the next morning.",
    ],
  ];
  const replies = [];
  for (const [label, prompt] of scenarios) {
    const r = await chat([{ role: "user", content: prompt }], label);
    replies.push(r);
  }
  const identicalPairs = [];
  for (let i = 0; i < replies.length; i++) {
    for (let j = i + 1; j < replies.length; j++) {
      if (replies[i] && replies[i] === replies[j]) identicalPairs.push([i, j]);
    }
  }
  log(
    "Message coach diversity",
    identicalPairs.length === 0 ? "PASS" : "FAIL",
    identicalPairs.length === 0
      ? "No identical replies across scenarios"
      : `Identical replies at pairs ${JSON.stringify(identicalPairs)}`,
  );

  // 7. Empty / long / failure modes
  await chat([{ role: "user", content: "" }], "AI failure — empty prompt");
  const long = "word ".repeat(3000) + "Summarize in one sentence what I should text next.";
  await chat([{ role: "user", content: long }], "AI failure — extremely long conversation");

  // 8. Photo analysis — tiny jpeg
  try {
    const img = tinyJpegBase64();
    const { res, text, ms } = await fetchText(WORKER, {
      method: "POST",
      headers: { "Content-Type": "application/json", Origin: "https://datewiseai.com" },
      body: JSON.stringify({ imageBase64: img, tier: "magnet", mode: "quick" }),
    });
    let parsed = null;
    try {
      parsed = JSON.parse(text);
    } catch {
      /* */
    }
    const ok =
      res.ok &&
      parsed &&
      typeof parsed.overallScore === "number" &&
      typeof parsed.headline === "string";
    log(
      "Photo analysis — minimal JPEG",
      ok ? "PASS" : "WARN",
      ok
        ? `score=${parsed.overallScore} verdict=${parsed.verdict} headline=${parsed.headline} (${ms}ms)`
        : `HTTP ${res.status} body=${text.slice(0, 200)} (${ms}ms)`,
      { photo: parsed, ms },
    );
  } catch (e) {
    log("Photo analysis — minimal JPEG", "FAIL", String(e.message || e));
  }

  // Bad file
  try {
    const { res, text, ms } = await fetchText(WORKER, {
      method: "POST",
      headers: { "Content-Type": "application/json", Origin: "https://datewiseai.com" },
      body: JSON.stringify({ imageBase64: "not-an-image!!!", tier: "magnet", mode: "quick" }),
    });
    log(
      "Photo analysis — bad file",
      res.status >= 400 || /error|invalid/i.test(text) ? "PASS" : "WARN",
      `HTTP ${res.status} (${ms}ms) ${text.slice(0, 160)}`,
    );
  } catch (e) {
    log("Photo analysis — bad file", "PASS", `rejected: ${e.message || e}`);
  }

  // Oversized guard
  try {
    const huge = "A".repeat(1_600_000);
    const { res, text, ms } = await fetchText(WORKER, {
      method: "POST",
      headers: { "Content-Type": "application/json", Origin: "https://datewiseai.com" },
      body: JSON.stringify({ imageBase64: huge, tier: "magnet" }),
    });
    log(
      "Photo analysis — oversized",
      res.status >= 400 ? "PASS" : "FAIL",
      `HTTP ${res.status} (${ms}ms) ${text.slice(0, 160)}`,
    );
  } catch (e) {
    log("Photo analysis — oversized", "PASS", `rejected: ${e.message || e}`);
  }

  // Screenshot workflow — photo path with text note about conversation
  await chat(
    [
      {
        role: "user",
        content:
          "I uploaded a screenshot of this chat (imagine OCR):\nHer: hey stranger\nMe: hey!\nHer: what are you up to this weekend?\nIdentify who said what in order and suggest 3 reply options that answer her question.",
      },
    ],
    "Screenshot-to-reply (text-simulated conversation extract)",
  );

  // Cross-feature context
  await chat(
    [
      {
        role: "user",
        content:
          "Remember my context: serious relationship, engineer, hiking. Now write one opener for someone whose prompt says they just got a rescue dog.",
      },
    ],
    "Cross-feature — profile context into opener",
  );

  // Codebase static checks (local tree)
  const root = "C:/Users/michael/Documents/New folder/_amber_portfolio/datewiseaiapp";
  const purchase = fs.readFileSync(path.join(root, "lib/services/purchase_service.dart"), "utf8");
  const flags = fs.readFileSync(path.join(root, "lib/app_flags.dart"), "utf8");
  const links = fs.readFileSync(path.join(root, "lib/app_links.dart"), "utf8");
  log(
    "IAP implementation",
    /MockPurchaseService/.test(purchase) && /freeLaunch = true/.test(flags) ? "FAIL" : "PASS",
    /MockPurchaseService/.test(purchase)
      ? "App uses MockPurchaseService; freeLaunch=true — no real StoreKit products, Restore Purchases is no-op"
      : "Real purchase service present",
  );
  log(
    "App Store ID wired in client",
    /iosAppStoreId = '6780110141'|iosAppStoreId = \"6780110141\"/.test(links) ? "PASS" : "FAIL",
    /iosAppStoreId = ''/.test(links)
      ? "iosAppStoreId is empty — in-app Rate App hidden; listing id 6780110141 not wired"
      : "App Store id present in AppLinks",
  );
  log(
    "Screenshot OCR dedicated workflow",
    "FAIL",
    "No dedicated screenshot→OCR→speaker-split feature in codebase; photo coach critiques profile photos; conversation screenshots only work if user pastes text or vision treats image as photo critique",
  );

  const dest = path.join(root, "docs/qa/DATEWISE_PRODUCTION_E2E_RESULTS.json");
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  const summary = {
    testedAt: new Date().toISOString(),
    appStoreId: APPSTORE_ID,
    worker: WORKER,
    supabase: SUPABASE,
    results: out,
    pass: out.filter((r) => r.status === "PASS").length,
    fail: out.filter((r) => r.status === "FAIL").length,
    warn: out.filter((r) => r.status === "WARN").length,
  };
  fs.writeFileSync(dest, JSON.stringify(summary, null, 2));
  console.log("\nSUMMARY", JSON.stringify({ pass: summary.pass, fail: summary.fail, warn: summary.warn, dest }, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
