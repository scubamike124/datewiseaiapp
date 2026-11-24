import json, cv2, numpy as np, os
from PIL import Image, ImageDraw, ImageFont
S='/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad'
OLD='/home/user/wt-before'; NEW='/home/user/wt-after'
F=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',22); Sm=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',17)
def comp(root,coach,name,man,hero):
    img=hero.copy()
    if name!='rest':
        x,y,w,h=man['frames'][name]['rect']; p=cv2.imread(f'{root}/assets/avatar/{coach}/{name}.jpg'); assert p.shape[:2]==(h,w)
        img[y:y+h,x:x+w]=p
    return img
for coach in ['ava','ethan','sofia','diego']:
    mo=json.load(open(f'{OLD}/assets/avatar/{coach}/manifest.json')); mn=json.load(open(f'{NEW}/assets/avatar/{coach}/manifest.json'))
    assert (mo['width'],mo['height'])==(mn['width'],mn['height'])
    hero=cv2.resize(cv2.imread(f'{OLD}/assets/coaches/{coach}-hero.jpg'),(mo['width'],mo['height']),interpolation=cv2.INTER_AREA)
    names=[n for n in mn['frames'] if open(f'{OLD}/assets/avatar/{coach}/{n}.jpg','rb').read()!=open(f'{NEW}/assets/avatar/{coach}/{n}.jpg','rb').read()]
    rects=[mn['frames'][n]['rect'] for n in names]+[mo['frames'][n]['rect'] for n in names]
    x0=max(0,min(r[0] for r in rects)-30); y0=max(0,min(r[1] for r in rects)-40)
    x1=min(hero.shape[1],max(r[0]+r[2] for r in rects)+30); y1=min(hero.shape[0],max(r[1]+r[3] for r in rects)+30)
    sc=360/(x1-x0); tw=360; th=int((y1-y0)*sc)
    cols=2; # each name = before|after pair; 2 pairs per row
    pairs=[]
    for n in ['rest']+names:
        a=comp(OLD,coach,n,mo,hero)[y0:y1,x0:x1]; b=comp(NEW,coach,n,mn,hero)[y0:y1,x0:x1]
        pairs.append((n,cv2.resize(a,(tw,th),interpolation=cv2.INTER_AREA),cv2.resize(b,(tw,th),interpolation=cv2.INTER_AREA)))
    per=2; rows=(len(pairs)+per-1)//per; cw=2*tw+30; PW=per*cw+20; PH=90+rows*(th+36)
    sheet=Image.new('RGB',(PW,PH),(14,14,14)); d=ImageDraw.Draw(sheet)
    d.text((12,8),f"{coach.capitalize()}: changed mouth frames, before | after  ('rest' = unchanged reference)",font=F,fill=(255,255,255))
    d.text((12,42),"Each tile pastes the patch on the approved portrait exactly as the app does. Static, not a device screenshot.",font=Sm,fill=(255,120,120))
    for i,(n,a,b) in enumerate(pairs):
        r,c=divmod(i,per); x=10+c*cw; y=80+r*(th+36)
        d.text((x,y),f"{n}  before",font=Sm,fill=(200,200,200)); d.text((x+tw+10,y),f"{n}  after",font=Sm,fill=(120,230,140))
        sheet.paste(Image.fromarray(cv2.cvtColor(a,cv2.COLOR_BGR2RGB)),(x,y+22)); sheet.paste(Image.fromarray(cv2.cvtColor(b,cv2.COLOR_BGR2RGB)),(x+tw+10,y+22))
    sheet.save(f'{S}/before-after/{coach}-sheet.jpg',quality=90); print(coach,names,sheet.size)
