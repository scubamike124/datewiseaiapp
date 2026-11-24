import sys, glob, json
from PIL import Image, ImageDraw, ImageFont
L='/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad/listening'
name, V = sys.argv[1], sys.argv[2]
files = sorted(glob.glob(f'{L}/render/{V}/{name}/f*.png'))
log = json.load(open(f'{L}/render/{V}/{name}.log.json'))['frames']
F = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 15)
ts = [i*15 for i in range(0, 26)]  # every 0.5 s, 0..12.5 s
ts = [t for t in ts if t < len(files)]
cols = 4; tw = 390; th = 195
rows = (len(ts)+cols-1)//cols
sheet = Image.new('RGB', (cols*tw, rows*(th+20)+24), (12,12,12))
d = ImageDraw.Draw(sheet); d.text((6,4), f'SIMULATION (host render of the app animator), {name} {V}: one frame per 0.5 s, listening 0-8 s, thinking 8-10.3 s, speaking after', font=F, fill=(255,90,90))
for k,i in enumerate(ts):
    im = Image.open(files[i]).convert('RGB').resize((tw,th), Image.LANCZOS)
    x = (k%cols)*tw; y = 24+(k//cols)*(th+20)
    sheet.paste(im,(x,y+18))
    fr = log[i]; lay = ','.join(l.split('@')[0] if l.startswith(('blink','gaze','mbp')) else l for l in fr['layers']) or '-'
    d.text((x+3,y+1), f"{i/30:4.1f}s {fr['mood'][:5]} dy={fr['dy']:+.1f} rot={fr['rot']*57.3:+.2f} {lay}", font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 11), fill=(220,220,220))
sheet.save(f'{L}/strips/{name}-{V}-strip.png')
