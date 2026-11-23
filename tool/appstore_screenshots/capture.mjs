// App Store screenshots for DateWise AI, captured from the Flutter web review
// build (DW_FAKE_STORE + DW_MOCK_AI: sample data, simulated purchases, offline
// demo coach) and wrapped in a simple branded frame with a short headline.
//
// Normally run through ./generate.sh, which builds and serves the web app.
//   node capture.mjs --url http://127.0.0.1:8791 --web-root ../../build/web \
//        --out ../../docs/appstore/screenshots [--locales en,es] [--sizes 6.9,6.5,ipad-13]
//
// Output: <out>/<locale>/<size>/NN-name.png
//   6.9" = 1320x2868 (440x956 @3x), 6.5" = 1284x2778 (428x926 @3x)
//   ipad-13 = iPad 13" 2064x2752 (1032x1376 @2x): the app's own iPad layout
// Sizes per Apple's "Screenshot specifications" (App Store Connect Help).
//
// Headlines describe what is on screen; no statistics, ratings or claims.
// The chats are example conversations from the review build (offline demo
// coach); the chat caption says so. Nothing shows voice mode, video or
// animation: the coaches are still portraits.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const pw = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const { chromium } = pw.default ?? pw;

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../..');

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : fallback;
}
const baseUrl = arg('url', 'http://127.0.0.1:8791');
const webRoot = path.resolve(arg('web-root', path.join(repo, 'build/web')));
const outDir = path.resolve(arg('out', path.join(repo, 'docs/appstore/screenshots')));
const locales = arg('locales', 'en,es').split(',');
const sizeIds = arg('sizes', '6.9,6.5,ipad-13').split(',');

const SIZES = {
  '6.9': { w: 440, h: 956 },  // iPhone 6.9" display: 1320x2868
  '6.5': { w: 428, h: 926 },  // iPhone 6.5" display: 1284x2778
  'ipad-13': { w: 1032, h: 1376, scale: 2 }, // iPad 13" display: 2064x2752 (required: the app runs on iPad)
};
const SCALE = 3;

// --- App interactions ------------------------------------------------------

let currentLocale = 'en';
async function open(page, screen) {
  // Review mode (lib/dev/review_mode.dart) sets the app language from ?lang=.
  await page.goto(`${baseUrl}/?screen=${screen}&lang=${currentLocale}`);
  await page.waitForSelector('flt-glass-pane, flutter-view', { state: 'attached', timeout: 30000 });
  await page.waitForTimeout(3500);
  // Turn on Flutter's semantics tree so widgets can be found by label.
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(800);
}
// Scrolls a list screen (the You tab) to a position where no row is cut off:
// not by the top edge, not under the tab bar. Uses Flutter's semantics tree
// for positions and checks where the list actually is after each small wheel
// step (Flutter does not apply every wheel event one to one). The large title
// is merged into its scroll view and has no node of its own, so it must be
// either fully shown (no scroll) or scrolled away (past the first section
// label's top).
async function withoutCutRows(page) {
  const { width, height } = page.viewportSize();
  const measure = () =>
    page.evaluate(() =>
      [...document.querySelectorAll('flt-semantics')]
        .map((e) => {
          const r = e.getBoundingClientRect();
          const label = (e.getAttribute('aria-label') || e.textContent || '').trim();
          return { role: e.getAttribute('role'), label, top: r.top, bottom: r.bottom, h: r.height };
        })
        .filter((n) => n.h > 0 && n.h < 140),
    );
  const layout = (nodes) => {
    // The tab bar: the row of (at least four) buttons sharing one top near the bottom.
    const low = nodes.filter((n) => n.role === 'button' && n.top > height * 0.75);
    const tops = low.map((n) => Math.round(n.top));
    const tabTop = tops.find((t) => tops.filter((x) => x === t).length >= 4);
    const barTop = (tabTop ?? height) - 6; // DwTabBar's top padding
    const tabs = low.filter((n) => Math.round(n.top) === tabTop);
    return { barTop, items: nodes.filter((n) => !tabs.includes(n)) };
  };
  const isCut = ({ barTop, items }) =>
    items.some(
      (n) =>
        (n.top < 0.5 && n.bottom > 1 && n.h < height * 0.5) || // cut by the top edge
        (n.top < barTop - 2 && n.bottom > barTop + 2) || // runs under the tab bar
        (n.role === 'button' && n.h < 44 && n.top < barTop && n.bottom > barTop - 4), // row clipped by the bar
    );
  const first = layout(await measure());
  // The first section label (a short text node such as "COACHING") and the
  // first row below it: the row tracks how far the list has really moved.
  const label = first.items.filter((n) => n.role === null && n.h < 30 && n.top > 4).sort((a, b) => a.top - b.top)[0];
  const ref = first.items.filter((n) => n.role === 'button' && n.top > (label?.top ?? 0)).sort((a, b) => a.top - b.top)[0];
  const titleEnd = label ? label.top + label.h : 0;
  const scrolledBy = (items) => {
    const now = items.find((n) => n.role === 'button' && n.label === ref?.label);
    return now && ref ? ref.top - now.top : null;
  };
  await page.mouse.move(width / 2, height / 2);
  let lastSig = null;
  let still = 0;
  for (let i = 0; i < 600; i++) {
    const nodes = await measure();
    const l = layout(nodes);
    const by = scrolledBy(l.items);
    if (by !== null && !isCut(l) && (by < 0.5 || by >= titleEnd)) {
      // Let the desktop-style scrollbar fade out before the screenshot.
      if (by >= 0.5) await page.waitForTimeout(2000);
      return Math.round(by);
    }
    const sig = nodes.map((n) => Math.round(n.top)).join(',');
    still = sig === lastSig ? still + 1 : 0;
    if (still >= 40) break; // nothing moves any more: the end of the list
    lastSig = sig;
    await page.mouse.wheel(0, 2);
    await page.waitForTimeout(80);
  }
  throw new Error(`could not find a scroll position without cut-off rows (ref ${ref?.label}, title ends at ${titleEnd})`);
}

const tap = async (page, name) => {
  await page.getByRole('button', { name }).first().click();
  await page.waitForTimeout(1200);
};
async function send(page, text) {
  await page.getByRole('textbox').first().click();
  await page.keyboard.type(text, { delay: 5 });
  await page.keyboard.press('Enter');
  await waitForReply(page);
}
// The demo coach streams its reply; wait until the composer is idle again
// (the Stop button has turned back into Send), so no shot shows a reply
// mid-stream or the loading icon.
async function waitForReply(page) {
  const idle = page.getByRole('button', { name: /^(Send|Enviar)$/ });
  const busy = page.getByRole('button', { name: /^(Stop reply|Detener respuesta)$/ });
  await busy.first().waitFor({ state: 'visible', timeout: 5000 }).catch(() => {});
  await idle.first().waitFor({ state: 'visible', timeout: 60000 });
  await page.waitForTimeout(900); // let the last frame settle
}

// --- Shot list (five per locale) --------------------------------------------

const SHOTS = {
  en: [
    { name: '01-coaches', headline: 'Choose your AI dating coach', sub: 'Four coaches, in English and Spanish', run: (p) => open(p, 'coaches') },
    { name: '02-home', headline: 'A simple plan for your week', sub: 'Profile, conversations and first dates', run: (p) => open(p, 'home') },
    { name: '03-chat', headline: 'Know what to say next', sub: 'Example chat: openers and replies you can adapt', run: (p) => open(p, 'chat') },
    { name: '04-coach', headline: 'Honest, practical advice', sub: 'From an AI dating coach, not a person', run: (p) => open(p, 'welcome') },
    { name: '05-privacy', headline: 'Your data, your controls', sub: 'Coach memory is off unless you turn it on', run: async (p) => { await open(p, 'you'); await withoutCutRows(p); } },
  ],
  es: [
    { name: '01-coaches', headline: 'Elige tu coach de citas con IA', sub: 'Cuatro coaches, en inglés y en español', run: (p) => open(p, 'coaches') },
    { name: '02-home', headline: 'Un plan sencillo para tu semana', sub: 'Perfil, conversaciones y primeras citas', run: (p) => open(p, 'home') },
    // One finished exchange with Sofía (review mode seeds it with ?lang=es).
    { name: '03-chat', headline: 'Sabrás qué escribir', sub: 'Chat de ejemplo: primeros mensajes y respuestas a tu medida', run: (p) => open(p, 'chat') },
    { name: '04-coach', headline: 'Coaches en español', sub: 'Sofía y Diego te ayudan en tu idioma', run: async (p) => { await open(p, 'coaches'); await tap(p, /Chatear con Diego/); } },
    { name: '05-privacy', headline: 'Tus datos, tu control', sub: 'La memoria del coach está apagada salvo que la actives', run: async (p) => { await open(p, 'you'); await withoutCutRows(p); } },
  ],
};

// --- Frame -----------------------------------------------------------------

const font = (f) => `data:font/ttf;base64,${fs.readFileSync(path.join(repo, 'assets/fonts', f)).toString('base64')}`;
const FONTS = `
@font-face { font-family: Newsreader; src: url(${font('Newsreader-Medium.ttf')}); font-weight: 500; }
@font-face { font-family: Inter; src: url(${font('Inter-Medium.ttf')}); font-weight: 500; }
@font-face { font-family: Inter; src: url(${font('Inter-SemiBold.ttf')}); font-weight: 600; }`;

function frameHtml({ w, h }, shot, png) {
  // iPad frames are wider: larger type and corners, same layout.
  const k = w > 600 ? 1.45 : 1;
  const cardW = Math.round(w * 0.75);
  const cardH = Math.round(cardW * h / w);
  const top = h - cardH - Math.round(h * 0.028);
  return `<!doctype html><html><head><meta charset="utf-8"><style>${FONTS}
  html,body{margin:0;width:${w}px;height:${h}px;overflow:hidden}
  body{background:radial-gradient(120% 70% at 50% 0%,#3a1d27 0%,#1d1015 55%,#120a0d 100%);color:#F7EFE7;font-family:Inter,sans-serif;position:relative}
  header{position:absolute;top:0;left:24px;right:24px;height:${top}px;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;gap:${Math.round(h*0.012)}px}
  .brand{font:600 ${Math.round(11 * k)}px Inter;letter-spacing:${(2.6 * k).toFixed(1)}px;color:#DDB67F}
  h1{margin:0;font:500 ${w > 600 ? 52 : 33}px/1.1 Newsreader,serif;letter-spacing:-0.3px;text-wrap:balance}
  .sub{text-wrap:balance}
  .sub{font:500 ${Math.round(14 * k)}px/1.3 Inter;color:#C2B2A8}
  .card{position:absolute;left:${(w - cardW) / 2}px;top:${top}px;width:${cardW}px;height:${cardH}px;border-radius:${Math.round(30 * k)}px;overflow:hidden;
    box-shadow:0 0 0 1.5px rgba(221,182,127,.55),0 24px 60px rgba(0,0,0,.55),0 0 80px rgba(196,88,122,.18)}
  .card img{width:100%;height:100%;display:block}
  </style></head><body>
  <header><div class="brand">DATEWISE AI</div>
  <h1>${shot.headline}</h1>
  <div class="sub">${shot.sub}</div></header>
  <div class="card"><img src="data:image/png;base64,${png.toString('base64')}"></div>
  </body></html>`;
}

// --- Main ------------------------------------------------------------------

// Chromium occasionally fails one capture of a large page ("Unable to capture
// screenshot"); try again once before giving up.
async function screenshot(page, options = {}) {
  try {
    return await page.screenshot(options);
  } catch (e) {
    console.warn(`screenshot failed (${e.message.split('\n')[0]}), retrying`);
    await page.waitForTimeout(1500);
    return page.screenshot(options);
  }
}

const browser = await chromium.launch();
try {
  for (const sizeId of sizeIds) {
    const size = SIZES[sizeId];
    if (!size) throw new Error(`unknown size ${sizeId}`);
    const scale = size.scale ?? SCALE;
    for (const locale of locales) {
      const dir = path.join(outDir, locale, sizeId);
      fs.mkdirSync(dir, { recursive: true });
      currentLocale = locale;
      for (const shot of SHOTS[locale]) {
        const ctx = await browser.newContext({ viewport: { width: size.w, height: size.h }, deviceScaleFactor: scale, locale: locale === 'es' ? 'es-MX' : 'en-US' });
        const page = await ctx.newPage();
        // Serve CanvasKit from the local build instead of the gstatic CDN, and
        // skip the Roboto fallback font download (works offline / behind proxies).
        await page.route(/gstatic\.com\/flutter-canvaskit\/[^/]+\/.*$/, async (route) => {
          const rel = route.request().url().replace(/^.*flutter-canvaskit\/[^/]+\//, '');
          const file = path.join(webRoot, 'canvaskit', rel);
          if (!fs.existsSync(file)) return route.continue();
          await route.fulfill({ body: fs.readFileSync(file), contentType: file.endsWith('.wasm') ? 'application/wasm' : 'text/javascript' });
        });
        await page.route(/fonts\.gstatic\.com/, (route) => route.abort());
        await shot.run(page);
        const png = await screenshot(page);
        await ctx.close();

        const fctx = await browser.newContext({ viewport: { width: size.w, height: size.h }, deviceScaleFactor: scale });
        const fpage = await fctx.newPage();
        await fpage.setContent(frameHtml(size, shot, png), { waitUntil: 'load' });
        await fpage.evaluate(() => document.fonts.ready);
        const file = path.join(dir, `${shot.name}.png`);
        await screenshot(fpage, { path: file });
        await fctx.close();
        console.log(`wrote ${path.relative(repo, file)} (${size.w * scale}x${size.h * scale})`);
      }
    }
  }
} finally {
  await browser.close();
}
