#!/usr/bin/env python3
"""Reproduces costs.json and COSTS.md for the DateWise avatar decision brief.
Run:  python3 -I costs.py   (writes costs.json and COSTS.md next to this file)
Method follows wt-research/.../calc/model.py (net revenue, refunds, duty cycle, GPU $/h/streams/utilisation)
and AI_COST_MODEL.md (2 chat turns per voice minute, Llama 3.3 $/msg, 10,000 free neurons/day).
Every number below is an INPUT labelled with its source, or derived from inputs by the formulas in code."""
import json, math, os
HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------- revenue ----------------
PRICE = 19.99; REFUND = 0.03; ES_VAT = 0.21          # ES price is VAT-inclusive (21% IVA)
def net(price, comm, vat=0.0): return price / (1 + vat) * (1 - comm) * (1 - REFUND)
REV = {
  'US/CA/MX @15% (Small Business)': net(PRICE, .15),
  'US/CA/MX @30%':                  net(PRICE, .30),
  'ES @15% (VAT 21% incl.)':        net(PRICE, .15, ES_VAT),
  'ES @30% (VAT 21% incl.)':        net(PRICE, .30, ES_VAT),
}   # CA/MX local sales taxes not modelled (Apple remits; proceeds slightly lower)
BUDGETS = (4.00, 5.00)                                # owner's AI operating budget per subscriber per month
LEVELS = (15, 30, 60, 120, 300)                       # avatar session minutes (wall-clock) per subscriber per month

# ---------------- usage assumptions ----------------
DUTY = 2/3        # coach speaks ~20 s of every 30 s turn (AI_COST_MODEL s4: 10 s user + 20 s reply)
TURNS_PER_MIN = 2 # AI_COST_MODEL s4
MSG_COST = lambda m: 0.00126 if m <= 60 else 0.00193   # Llama 3.3 70B $/msg: typical (2000/300 tok) <=60 min, heavy (3500/400) above
MSG_NEURONS = lambda m: 114.8 if m <= 60 else 175.3    # AI_COST_MODEL s4
FREE_NEURONS_DAY = 10000
TTS_PER_SPEECH_MIN = 0.027   # Workers AI Aura-2 $0.030/1k chars ~ $0.027/speech-min (PAID_PROVIDER_BAKEOFF s2, AI_COST_MODEL s10)
KOKORO_PER_SPEECH_MIN = 0.002 # self-hosted Kokoro on the GPU box: $0.40 per 200 voice min (AI_COST_MODEL s10 table)
LK = 0.0114       # LiveKit Cloud per wall-min: agent session $0.01 + WebRTC $0.0005 + ~7.5 MB/min x $0.12/GB (livekit.com/pricing 2026-11-24)
TURN = 0.0004     # Cloudflare-style TURN egress $0.05/GB x 7.5 MB/min (COST_AUDIT M4, estimate)
FIXED_COMMON = 5.00  # Workers Paid (needed above ~10 typical subs; AI_COST_MODEL s4)

# ---------------- options ----------------
# rate: $/wall-minute at list (entry plan); rate_vol: best published/claimed; speaking_only: billed on speaking time only.
# voice: 'neural' = our Worker TTS (Aura-2) piped to vendor; 'device' = system voice ($0, needs native PCM bridge);
#        'bundled' = voice included in the vendor rate; 'kokoro' = self-hosted TTS on the GPU box.
# text:  'ours' = our Llama/Worker (keeps coach prompts, safety, StoreKit guard); 'vendor' = vendor LLM bundled (text cost 0, loses control).
O = []
def opt(**k): O.append(k)
opt(id='simli', name='Simli (Trinity), audio-in', kind='hosted', rate=0.01, rate_vol=0.0095, hint=0.005, voice='neural', text='ours',
    transport=TURN, floor=10.0, floor_note='Hobby $10 (1 custom avatar/mo, 1,000 min); Pro $49 for 5 custom avatars',
    src='simli.com/pricing 2026-11-24', status='verified price; hint = enterprise "as low as $0.005"')
opt(id='anam', name='Anam Cara (audio passthrough)', kind='hosted', rate=0.16, rate_vol=0.11, hint=0.04, voice='neural', text='ours',
    transport=0.0, floor=49.0, floor_note='Explorer $49 = 250 min ($0.196/min effective); Professional $999 = 8,000 min',
    src='anam.ai/pricing 2026-11-24', status='verified list; hint = enterprise "from $0.04" (sales)')
opt(id='bithuman_cloud', name='bitHuman cloud (LiveKit), audio-in', kind='hosted', rate=0.04, rate_vol=0.04, hint=None, voice='neural', text='ours',
    transport=LK, floor=20.0+50.0, floor_note='Creator $20 (+250 credits=$2.50 per Essence avatar) + LiveKit Ship $50',
    src='bithuman.ai/pricing 2026-11-24', status='verified')
opt(id='bithuman_device', name='bitHuman on-device (native Swift SDK, iPhone 16 Pro+)', kind='hosted-device', rate=0.02, rate_vol=0.02, hint=None, speaking_only=True,
    voice='device', text='ours', transport=0.0, floor=20.0, floor_note='Creator $20; SDK charges speaking seconds only',
    src='bithuman.ai/pricing 2026-11-24', status='verified price; NATIVE plugin required (AGENTS.md: not allowed in v1 Flutter)')
opt(id='liveavatar_lite', name='HeyGen LiveAvatar LITE (audio-in)', kind='hosted', rate=0.095, rate_vol=0.09, hint=0.01, voice='neural', text='ours',
    transport=LK, floor=99.0+50.0, floor_note='Essential $99 (1,110 credits = 1,110 LITE min) + LiveKit Ship $50',
    src='docs.liveavatar.com/docs/faq/credits 2026-11-24', status='verified list; hint $0.01 = secondary source (unverified)')
opt(id='liveavatar_full', name='HeyGen LiveAvatar FULL (vendor STT+LLM+TTS)', kind='hosted', rate=0.19, rate_vol=0.18, hint=None, voice='bundled', text='vendor',
    transport=0.0, floor=99.0, floor_note='Essential $99 (555 FULL min)', src='docs.liveavatar.com/docs/faq/credits 2026-11-24',
    status='verified; vendor sees whole conversation; our coach prompts bypassed')
opt(id='tavus', name='Tavus CVI (custom LLM endpoint)', kind='hosted', rate=0.35, rate_vol=0.26, hint=None, voice='bundled', text='ours',
    transport=0.0, floor=59.0, floor_note='Builder $59 = 175 min, 3 custom faces; Business $975 = 4,000 min', src='tavus.io/pricing 2026-11-24',
    status='verified (page also shows an older conflicting table)')
opt(id='did', name='D-ID Agents (Expressive, LiveKit)', kind='hosted', rate=0.70, rate_vol=0.69, hint=None, voice='bundled', text='ours',
    transport=LK, floor=18.0+50.0, floor_note='API Build from $18/mo (third party) + LiveKit Ship $50',
    src='activepieces/creatify blogs (derived from plan allowances), d-id.com/pricing/api page empty to fetch', status='UNVERIFIED: no official per-minute streaming rate found; $0.69-0.90 derived by third parties')
# self-hosted GPU: rate_hr, streams per GPU, hybrid (renders only while speaking), util of provisioned slots
GPU_SEC = 0.89  # RunPod 4090 Secure $/h (COST_AUDIT #1 confirmed 2026-11-24)
def sh(id_, name, rate_hr, streams, hybrid, floor_gpus, status, extra=''):
    opt(id=id_, name=name, kind='self-hosted', rate_hr=rate_hr, streams=streams, hybrid=hybrid, util=0.5, voice='kokoro', text='ours',
        transport=0.0, floor=rate_hr*730*floor_gpus, floor_note=f'{floor_gpus} warm GPU(s) 24/7 at ${rate_hr}/h x 730 h', src='costs-capacity.md, COST_AUDIT.md, free-gpu-and-licensing.md', status=status)
sh('musetalk', 'MuseTalk 1.5 via LiveTalking (4090 Secure, 1.5 streams)', GPU_SEC, 1.5, True, 2, 'weights MIT but HDTF/CelebAMask notice; offline CPU test 2026-11-24: soft teeth, mouth barely opens')
sh('flashhead_lite', 'SoulX-FlashHead Lite via Mynah (4090, 1 stream)', GPU_SEC, 1, True, 2, 'BLOCKED: weights "license: other", LTX-VAE terms')
sh('oac', 'OpenAvatarChat + FlashHead (GPU busy while idle, 1 stream)', GPU_SEC, 1, False, 2, 'BLOCKED as FlashHead; 1 session per GPU in shipped config')
sh('imtalker', 'IMTalker (4090, 1.5 streams est.)', GPU_SEC, 1.5, True, 2, 'licences clean (Apache/MIT); real-time unmeasured; CPU test: best lip closure, noisier, 512 crop only')
sh('leaptalk', 'LeapTalk (FlashHead Pro class, 1 stream on 2x5090 est.)', 1.35, 1, True, 2, 'licences look clean; consumer-GPU speed unpublished; unproven')
sh('liveavatar_open', 'Alibaba Live Avatar / FlashTalk (5-8 H800, ~$15/h, 1 stream)', 15.0, 1, False, 1, 'Apache-2.0 but InsightFace dep; real-time only on 5-8 H800 (alternatives.md)')

def avatar_wall_rate(o, vol=False, hint=False):
    if o['kind'] == 'self-hosted':
        spk = o['rate_hr'] / 60 / o['streams']
        return spk * (DUTY if o['hybrid'] else 1.0) / o['util']
    r = o['hint'] if hint else (o['rate_vol'] if vol else o['rate'])
    return r * (DUTY if o.get('speaking_only') else 1.0)

def voice_wall_rate(o):
    return {'neural': TTS_PER_SPEECH_MIN * DUTY, 'device': 0.0, 'bundled': 0.0, 'kokoro': KOKORO_PER_SPEECH_MIN * DUTY}[o['voice']]

def cost_row(o, m, vol=False, hint=False):
    av = avatar_wall_rate(o, vol, hint) * m
    vo = voice_wall_rate(o) * m
    tx = 0.0 if o['text'] == 'vendor' else MSG_COST(m) * TURNS_PER_MIN * m
    tr = o['transport'] * m
    tot = av + vo + tx + tr
    return dict(avatar=av, voice=vo, text=tx, transport=tr, total=tot)

def fits(tot): return 'FITS<=$4' if tot <= BUDGETS[0] else ('fits<=$5 only' if tot <= BUDGETS[1] else 'OVER')

out = dict(assumptions=dict(price=PRICE, refund=REFUND, es_vat=ES_VAT, duty=DUTY, turns_per_min=TURNS_PER_MIN, levels=LEVELS,
           revenue={k: round(v, 2) for k, v in REV.items()}, budgets=BUDGETS, tts_per_speech_min=TTS_PER_SPEECH_MIN, kokoro=KOKORO_PER_SPEECH_MIN,
           livekit_per_wall_min=LK, turn_per_min=TURN), options={})
for o in O:
    d = dict(name=o['name'], kind=o['kind'], status=o['status'], source=o['src'], voice=o['voice'], text=o['text'],
             floor_monthly=round(o['floor'] + FIXED_COMMON, 2), floor_note=o['floor_note'],
             avatar_rate_wall_min=round(avatar_wall_rate(o), 5), levels={})
    if o['kind'] != 'self-hosted':
        d['avatar_rate_wall_min_volume'] = round(avatar_wall_rate(o, vol=True), 5)
        if o.get('hint'): d['avatar_rate_wall_min_hint'] = round(avatar_wall_rate(o, hint=True), 5)
    for m in LEVELS:
        c = cost_row(o, m)
        row = {k: round(v, 3) for k, v in c.items()}
        row['fit'] = fits(c['total'])
        row['remaining'] = {k: round(v - c['total'], 2) for k, v in REV.items()}
        if o['kind'] != 'self-hosted':
            cv = cost_row(o, m, vol=True); row['total_at_volume_rate'] = round(cv['total'], 3)
            if o.get('hint'): row['total_at_hint_rate'] = round(cost_row(o, m, hint=True)['total'], 3)
        d['levels'][str(m)] = row
    # hard cap: minutes such that total <= budget using heavy text cost
    per_min = avatar_wall_rate(o) + voice_wall_rate(o) + o['transport'] + (0 if o['text']=='vendor' else MSG_COST(120)*TURNS_PER_MIN)
    d['cap_minutes_at_4usd'] = int(BUDGETS[0] / per_min)
    d['cap_minutes_at_5usd'] = int(BUDGETS[1] / per_min)
    d['marginal_cost_per_wall_min'] = round(per_min, 5)
    # blended with fixed floor at 100 and 1,000 subscribers (60 min)
    d['all_in_60min_with_floor'] = {str(S): round(d['levels']['60']['total'] + d['floor_monthly'] / S, 2) for S in (100, 1000)}
    out['options'][o['id']] = d

# text-AI free allowance
fa = {}
for m in LEVELS:
    neur_month = TURNS_PER_MIN * m * MSG_NEURONS(m); per_day = neur_month / 30
    fa[str(m)] = dict(neurons_per_sub_month=round(neur_month), neurons_per_sub_day=round(per_day, 1),
                      subs_covered_by_free_10k_per_day=int(FREE_NEURONS_DAY / per_day), text_cost_list=round(MSG_COST(m)*TURNS_PER_MIN*m, 3))
out['text_ai_free_allowance'] = fa
json.dump(out, open(os.path.join(HERE, 'costs.json'), 'w'), indent=1)

# ---------------- COSTS.md ----------------
L = []
w = L.append
w('# COSTS: avatar options at 15, 30, 60, 120 and 300 minutes per subscriber per month\n')
w('Generated by `costs.py` (run `python3 -I costs.py`; it rewrites this file and `costs.json`). Date of prices: 2026-11-24. No account was opened and nothing was bought. All figures are per subscriber per month, in USD, list price, before any free allowance.\n')
w('## 1. Method and assumptions (each is an input in the script)\n')
w('| Item | Value | Source / reasoning |\n|---|---|---|')
w(f'| Subscription | ${PRICE} / month, one tier | owner decision (AI_COST_MODEL header) |')
for k, v in REV.items(): w(f'| Net per subscriber, {k} | ${v:.2f} | price / (1+VAT) x (1-commission) x (1-3% refunds). ES: 21% IVA included in the price (Apple pays out after tax). CA/MX sales tax not modelled |')
w(f'| Budget to test | ${BUDGETS[0]:.2f} and ${BUDGETS[1]:.2f} AI operating cost per subscriber | owner: $4-5 |')
w(f'| "Minutes" | wall-clock minutes the avatar session is open (vendors bill idle/listening time too) | vendor billing pages |')
w(f'| Duty cycle (coach speaking) | {DUTY:.3f} | 20 s of reply per 30 s turn (AI_COST_MODEL s4); prior model used 0.5, audit asked 0.6 |')
w(f'| Chat turns per avatar minute | {TURNS_PER_MIN} | AI_COST_MODEL s4 |')
w('| Text-AI $/message | $0.00126 (<=60 min), $0.00193 (>=120 min) | AI_COST_MODEL s4, Llama 3.3 70B, typical vs heavy message size. Priced at list, BEFORE the free allowance |')
w(f'| Neural TTS (our Worker, Aura-2) | ${TTS_PER_SPEECH_MIN}/speech-min = ${TTS_PER_SPEECH_MIN*DUTY:.4f}/wall-min | PAID_PROVIDER_BAKEOFF s2 / AI_COST_MODEL s10. PLACEHOLDER: another agent is researching voice. On-device system voice = $0 |')
w(f'| Self-hosted TTS (Kokoro) | ${KOKORO_PER_SPEECH_MIN}/speech-min | AI_COST_MODEL s10 ($0.40 per 200 voice min) |')
w(f'| LiveKit Cloud transport | ${LK}/wall-min | $0.01 agent session + $0.0005 WebRTC + 7.5 MB/min x $0.12/GB (livekit.com/pricing, 2026-11-24). Applied to options whose official path is a LiveKit plugin |')
w(f'| TURN/egress, direct WebRTC | ${TURN}/wall-min | 7.5 MB/min x $0.05/GB (COST_AUDIT M4, estimate) |')
w('| Self-hosted GPU | RunPod 4090 Secure $0.89/h (confirmed in COST_AUDIT); $/wall-min = $/h / 60 / streams x (duty if hybrid, else 1) / utilisation 0.5 | calc/model.py method; 1-1.5 streams per 4090 per audit M1 |')
w(f'| Fixed monthly floors | Workers Paid ${FIXED_COMMON:.0f} + vendor plan + LiveKit Ship $50 where used | shown separately in section 4, NOT in the per-subscriber tables |')
w('| Apple Developer fee ($8.25/mo), monitoring, coach portrait generation | not included | immaterial per subscriber |\n')
w('Formula per option: **total = avatar_rate x minutes + voice_rate x minutes + text-AI x 2 x minutes + transport x minutes** (text = $0 only where the vendor LLM is bundled; those rows lose our coach prompts and safety rules).\n')
w('## 2. Cost per subscriber per month (list rate of the entry plan)\n')
w('`fit` tests the total against the $4 and $5 budget. Rates are $/wall-minute.\n')
hdr = '| Option | avatar $/min | ' + ' | '.join(f'{m} min' for m in LEVELS) + ' |\n|---|---|' + '---|' * len(LEVELS)
w(hdr)
for oid, d in out['options'].items():
    cells = []
    for m in LEVELS:
        r = d['levels'][str(m)]
        mark = '' if r['fit'] == 'OVER' else (' **ok**' if r['fit'].startswith('FITS') else ' ~')
        cells.append(f"${r['total']:.2f}{mark}")
    w(f"| {d['name']} | {d['avatar_rate_wall_min']:.4f} | " + ' | '.join(cells) + ' |')
w('\n`ok` = within $4, `~` = within $5 only, no mark = over $5.\n')
w('### 2.1 Breakdown at 60 minutes\n')
w('| Option | avatar | voice | text-AI | transport | total | voice assumption |\n|---|---|---|---|---|---|---|')
for oid, d in out['options'].items():
    r = d['levels']['60']
    w(f"| {d['name']} | ${r['avatar']:.2f} | ${r['voice']:.2f} | ${r['text']:.2f} | ${r['transport']:.2f} | **${r['total']:.2f}** | {d['voice']} |")
w('\n### 2.2 Same table at the volume or sales-hint rate (what negotiation could reach)\n')
w('| Option | rate used | ' + ' | '.join(f'{m} min' for m in LEVELS) + ' |\n|---|---|' + '---|' * len(LEVELS))
for oid, d in out['options'].items():
    if d['kind'] == 'self-hosted': continue
    for key, lab in (('total_at_volume_rate', 'best published'), ('total_at_hint_rate', 'sales hint (UNVERIFIED)')):
        if key in d['levels']['60']:
            rr = {'total_at_volume_rate': d.get('avatar_rate_wall_min_volume'), 'total_at_hint_rate': d.get('avatar_rate_wall_min_hint')}[key]
            w(f"| {d['name']} | {lab} ${rr:.4f}/min | " + ' | '.join(f"${d['levels'][str(m)][key]:.2f}" for m in LEVELS) + ' |')
w('\n## 3. Remaining revenue per subscriber (net of Apple, refunds, VAT, minus total above)\n')
w('Shown for 60 and 300 minutes; the full grid is in costs.json (`remaining`). Negative = loss on that subscriber.\n')
for m in (60, 300):
    w(f'\n**{m} minutes**\n')
    w('| Option | ' + ' | '.join(REV.keys()) + ' |\n|---|' + '---|' * len(REV))
    for oid, d in out['options'].items():
        w(f"| {d['name']} | " + ' | '.join(f"${v:.2f}" for v in d['levels'][str(m)]['remaining'].values()) + ' |')
w('\n## 4. Fixed floors, free tiers, minimums and the blended cost at small scale\n')
w('| Option | monthly floor (incl. $5 Workers) | what the floor buys | all-in per sub at 100 subs, 60 min | at 1,000 subs |\n|---|---|---|---|---|')
for oid, d in out['options'].items():
    w(f"| {d['name']} | ${d['floor_monthly']:,.0f} | {d['floor_note']} | ${d['all_in_60min_with_floor']['100']:.2f} | ${d['all_in_60min_with_floor']['1000']:.2f} |")
w('\nFree tiers (each needs an account, so owner approval first): Simli 50 min/mo, template faces only (own face needs Hobby $10); Anam 30 min/mo, 3-min sessions, own image upload included, no card; LiveAvatar 10 credits/mo; Tavus 20 min, stock faces; bitHuman 99 credits (an Essence avatar costs 250); LiveKit Build 1,000 agent min, 5,000 WebRTC min, 5 concurrent. Self-hosted rows are dominated by the warm-GPU floor and by ops time (COST_AUDIT B1, M8), not by the per-minute figure.\n')
w('## 5. Text-AI and the free Workers AI allowance (10,000 neurons/day, whole account)\n')
w('| Minutes | neurons / sub / month | neurons / sub / day | subscribers the free allowance covers | text-AI at list |\n|---|---|---|---|---|')
for m in LEVELS:
    f_ = fa[str(m)]
    w(f"| {m} | {f_['neurons_per_sub_month']:,} | {f_['neurons_per_sub_day']} | {f_['subs_covered_by_free_10k_per_day']} | ${f_['text_cost_list']:.2f} |")
w('\nAbove those subscriber counts, Workers Paid ($5/mo + $0.011 per 1,000 neurons) is the only way to keep serving; no paid fallback is enabled today, so on Workers Free the Worker returns errors once 10,000 neurons are used (AI_COST_MODEL s1). Neural TTS through Workers AI draws on the same neuron pool (not separately modelled here), so any neural-voice option needs Workers Paid almost immediately: an owner decision.\n')
w('## 6. Hard-cap policy (keeps the worst case inside the budget)\n')
w('Maximum avatar minutes per subscriber per month before total cost exceeds $4 / $5 (heavy text cost, entry-plan list rate):\n')
w('| Option | marginal $/wall-min | cap at $4 | cap at $5 |\n|---|---|---|---|')
for oid, d in out['options'].items():
    w(f"| {d['name']} | ${d['marginal_cost_per_wall_min']:.4f} | {d['cap_minutes_at_4usd']} | {d['cap_minutes_at_5usd']} |")
w('''
Recommendation (applies to whichever vendor is chosen):

1. **Included premium-avatar minutes per month = the largest of 15/30/60/120 that is at or under the cap-at-$4 column** (minutes x marginal $/min, heavy text cost). Simli: cap 123, so include **60** (cost $1.85, less than half the budget, about $1.9 at the cap with heavy-size messages). bitHuman cloud: 54, so 30. Anam and LiveAvatar LITE at entry rates: 21 and 31, so 15 and 30; only enterprise-rate Anam ($0.04) would allow 60. Tavus and D-ID: not viable as an included feature.
2. **Enforce in the Worker, not the app.** The session endpoint is the only place a vendor token is minted. It refuses to mint after the monthly seconds are used and mints tokens with `max_duration` = min(remaining seconds, 10 min). It counts seconds from mint to close, because vendors bill listening time too. Reuse `UsageGuard` (Durable Object) with one more monthly counter.
3. **Idle timeout 45-60 s** with no coach audio: close the session and show the on-device avatar. An open silent session still bills.
4. **After the cap, or on any vendor error, quota exhaustion or offline:** the existing on-device avatar and system voice take over with no error dialog; text chat keeps working under its own 150/day, 1,500/month limits. The cap is a feature boundary, never a paywall.
5. **Global kill switch** (wrangler var) and a vendor-side monthly spend limit or prepaid plan with overage OFF (LiveAvatar and Anam both require overage to be switched on, so keep it off).
6. **Worst case per subscriber** is then cap x marginal cost + text. Text worst case is already bounded by the chat-v7 guard ($5.34 only if every one of 1,500 messages is maximum size, so it is a separate risk, not an avatar one).
''')
w('## 7. What the numbers say\n')
w('Read the tables with section 6: options whose 60-minute total is over $5 only work as a small capped premium allowance, or at an enterprise rate that has not been quoted. Self-hosted rows look cheap per minute but carry a warm-GPU floor (about $1,300/month for two 4090s) and unresolved licences; see COST_AUDIT B1 for the crossover (not before 5,000-7,000 typical subscribers).')
open(os.path.join(HERE, 'COSTS.md'), 'w').write('\n'.join(L) + '\n')
print('ok')
