// App Store screenshots for DateWise AI, captured from the Flutter web review
// build (DW_FAKE_STORE + DW_MOCK_AI: sample data, simulated purchases, offline
// demo coach) and wrapped in a simple branded frame with a short headline.
//
// Normally run through ./generate.sh, which builds and serves the web app.
//   node capture.mjs --url http://127.0.0.1:8791 --web-root ../../build/web \
//        --out ../../docs/appstore/screenshots [--locales en,es] [--sizes 6.9,6.5]
//
// Output: <out>/<locale>/<size>/NN-name.png
//   6.9" = 1320x2868 (440x956 @3x), 6.5" = 1284x2778 (428x926 @3x)
//
// Headlines describe what is on screen; no statistics, ratings or claims.
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
const sizeIds = arg('sizes', '6.9,6.5').split(',');

const SIZES = {
  '6.9': { w: 440, h: 956 },  // iPhone 6.9" display: 1320x2868
  '6.5': { w: 428, h: 926 },  // iPhone 6.5" display: 1284x2778
  '13': { w: 1032, h: 1376, scale: 2 }, // iPad 13" (2064x2752), optional
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
const tap = async (page, name) => {
  await page.getByRole('button', { name }).first().click();
  await page.waitForTimeout(1200);
};
async function send(page, text) {
  await page.getByRole('textbox').first().click();
  await page.keyboard.type(text, { delay: 5 });
  await page.keyboard.press('Enter');
  await page.waitForTimeout(4500); // demo coach streams its reply
}
const sofiaChat = async (page) => {
  await open(page, 'coaches');
  await tap(page, /Chatear con Sofía/);
  await send(page, '¿Qué le escribo primero? Le gusta el senderismo');
};

// --- Shot list (five per locale) --------------------------------------------

const SHOTS = {
  en: [
    { name: '01-coaches', headline: 'Choose your AI dating coach', sub: 'Four coaches, in English and Spanish', run: (p) => open(p, 'coaches') },
    { name: '02-home', headline: 'A simple plan for your week', sub: 'Profile, conversations and first dates', run: (p) => open(p, 'home') },
    { name: '03-chat', headline: 'Know what to say next', sub: 'Openers and replies you can adapt', run: (p) => open(p, 'chat') },
    { name: '04-coach', headline: 'A coach who listens', sub: 'Honest, practical dating advice from AI', run: (p) => open(p, 'welcome') },
    { name: '05-privacy', headline: 'Your data, your controls', sub: 'Coach memory is off unless you turn it on', run: (p) => open(p, 'you') },
  ],
  es: [
    { name: '01-coaches', headline: 'Elige tu coach de citas con IA', sub: 'Cuatro coaches, en inglés y en español', run: (p) => open(p, 'coaches') },
    { name: '02-home', headline: 'Un plan sencillo para tu semana', sub: 'Perfil, conversaciones y primeras citas', run: async (p) => { await sofiaChat(p); await tap(p, /Pestaña Inicio/); } },
    { name: '03-chat', headline: 'Sabrás qué escribir', sub: 'Primeros mensajes y respuestas a tu medida', run: sofiaChat },
    { name: '04-coach', headline: 'Coaches en español', sub: 'Sofía y Diego te ayudan en tu idioma', run: async (p) => { await open(p, 'coaches'); await tap(p, /Chatear con Diego/); } },
    { name: '05-privacy', headline: 'Tus datos, tu control', sub: 'La memoria del coach está apagada salvo que la actives', run: async (p) => {
      // The UI is already in Spanish (?lang=es), so the You tab is shown directly.
      await sofiaChat(p);
      await tap(p, /Pestaña Tú/);
    } },
  ],
};

// --- Frame -----------------------------------------------------------------

const font = (f) => `data:font/ttf;base64,${fs.readFileSync(path.join(repo, 'assets/fonts', f)).toString('base64')}`;
const FONTS = `
@font-face { font-family: Newsreader; src: url(${font('Newsreader-Medium.ttf')}); font-weight: 500; }
@font-face { font-family: Inter; src: url(${font('Inter-Medium.ttf')}); font-weight: 500; }
@font-face { font-family: Inter; src: url(${font('Inter-SemiBold.ttf')}); font-weight: 600; }`;

function frameHtml({ w, h }, shot, png) {
  const cardW = Math.round(w * 0.75);
  const cardH = Math.round(cardW * h / w);
  const top = h - cardH - Math.round(h * 0.028);
  return `<!doctype html><html><head><meta charset="utf-8"><style>${FONTS}
  html,body{margin:0;width:${w}px;height:${h}px;overflow:hidden}
  body{background:radial-gradient(120% 70% at 50% 0%,#3a1d27 0%,#1d1015 55%,#120a0d 100%);color:#F7EFE7;font-family:Inter,sans-serif;position:relative}
  header{position:absolute;top:0;left:24px;right:24px;height:${top}px;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;gap:${Math.round(h*0.012)}px}
  .brand{font:600 11px Inter;letter-spacing:2.6px;color:#DDB67F}
  h1{margin:0;font:500 ${w > 600 ? 52 : 33}px/1.1 Newsreader,serif;letter-spacing:-0.3px}
  .sub{font:500 14px/1.3 Inter;color:#C2B2A8}
  .card{position:absolute;left:${(w - cardW) / 2}px;top:${top}px;width:${cardW}px;height:${cardH}px;border-radius:30px;overflow:hidden;
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
        const png = await page.screenshot();
        await ctx.close();

        const fctx = await browser.newContext({ viewport: { width: size.w, height: size.h }, deviceScaleFactor: scale });
        const fpage = await fctx.newPage();
        await fpage.setContent(frameHtml(size, shot, png), { waitUntil: 'load' });
        await fpage.evaluate(() => document.fonts.ready);
        const file = path.join(dir, `${shot.name}.png`);
        await fpage.screenshot({ path: file });
        await fctx.close();
        console.log(`wrote ${path.relative(repo, file)} (${size.w * scale}x${size.h * scale})`);
      }
    }
  }
} finally {
  await browser.close();
}
