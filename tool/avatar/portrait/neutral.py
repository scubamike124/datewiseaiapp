import os
# Step 1-2: level the head by rotating the whole image (no face change), then relax the mouth with LivePortrait.
import sys, os, math, json, numpy as np, cv2
SP=os.environ.get('DW_PORTRAIT_WORK', os.path.expanduser('~/dw-portrait-work'))
os.environ['AVATAR_TOOLS']=SP+'/avatar-tools'
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')); sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fl
from lp_engine import Engine
import gen_frames as gf
OUT=SP+'/fp/neutral'; os.makedirs(OUT,exist_ok=True)
PAD=400
def lp_roll(eng,bgr):
    l=eng.prepare(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB))['lmk203']
    el,er=l[0:24].mean(0),l[24:48].mean(0); lips=l[48:96]; ml,mr=lips[lips[:,0].argmin()],lips[lips[:,0].argmax()]
    return (math.degrees(math.atan2(er[1]-el[1],er[0]-el[0]))+math.degrees(math.atan2(mr[1]-ml[1],mr[0]-ml[0])))/2
def level(c,eng):
    img=cv2.imread(f'{SP}/dw-ref/up-{c}.png')
    f=fl.face(img); roll=math.degrees(math.atan2(f[7]-f[5],f[6]-f[4]))
    big=cv2.copyMakeBorder(img,PAD,PAD,PAD,PAD,cv2.BORDER_CONSTANT,value=0)
    valid=cv2.copyMakeBorder(np.full(img.shape[:2],255,np.uint8),PAD,PAD,PAD,PAD,cv2.BORDER_CONSTANT,value=0)
    cx,cy=(f[4]+f[6])/2+PAD,(f[5]+f[7])/2+PAD
    for it in range(3):  # YuNet's roll on the rotated image can differ a little: iterate on the residual
        M=cv2.getRotationMatrix2D((cx,cy),roll,1.0)
        r=cv2.warpAffine(big,M,big.shape[1::-1],flags=cv2.INTER_LANCZOS4)
        res=lp_roll(eng,r)  # LivePortrait's 203-point eyes and mouth corners (YuNet's 5 points are biased on a turned head)
        if abs(res)<0.5: break
        roll+=res
    v=cv2.warpAffine(valid,M,big.shape[1::-1],flags=cv2.INTER_LINEAR)
    return r,v,roll
if __name__=='__main__':
    coaches=sys.argv[1].split(',')
    params=json.loads(sys.argv[2]) # list of dicts
    eng=Engine(crop_scale=float(os.environ.get('CS','1.7')))
    for c in coaches:
        r,v,roll=level(c,eng)
        cv2.imwrite(f'{OUT}/{c}-level.png',r); cv2.imwrite(f'{OUT}/{c}-valid.png',v)
        rgb=cv2.cvtColor(r,cv2.COLOR_BGR2RGB)
        st=eng.prepare(rgb)
        reg=gf.regions(st['face'],rgb.shape,st['lmk203'])
        mask,box=reg['mouth']
        print(c,'roll',round(roll,1),'lip_ratio',round(st['lip_ratio'],3),'eye',round(st['eye_ratio'],3),flush=True)
        for i,kw in enumerate(params):
            _,full=eng.render(st,**kw)
            full=gf.match_detail(full,rgb,mask)
            comp=gf.blend(rgb,full,mask)
            bgr=cv2.cvtColor(comp,cv2.COLOR_RGB2BGR)
            cv2.imwrite(f'{OUT}/{c}-n{i}.png',bgr)
            s=fl.stats(bgr,c); s.pop('emb')
            print(c,i,kw,s,flush=True)
