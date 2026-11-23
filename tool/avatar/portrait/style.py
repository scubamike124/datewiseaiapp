import os
# Stage A: non-face styling in the levelled image (hair colour, lip colour, earrings, stubble) + masks.
import sys, os, json, math, numpy as np, cv2
SP=os.environ.get('DW_PORTRAIT_WORK', os.path.expanduser('~/dw-portrait-work'))
os.environ['AVATAR_TOOLS']=SP+'/avatar-tools'
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')); sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fl, seg
N=SP+'/fp/neutral'; O=SP+'/fp/styled'; os.makedirs(O,exist_ok=True)
CFG={
 # hair: target (a,b) offsets in OpenCV LAB units, lightness multiplier/offset, chroma multiplier
 'ava':  dict(hair=dict(da=7, db=4, lmul=1.0, ladd=2, cmul=1.05), lips=dict(da=-4, db=2, ladd=5, cmul=0.75), earrings='silver', stubble=0),
 'sofia':dict(hair=dict(da=0, db=-2, lmul=0.82, ladd=-2, cmul=0.6), lips=dict(da=6, db=-3, ladd=-6, cmul=1.1), earrings=None, stubble=0),
 'ethan':dict(hair=dict(da=2, db=5, lmul=1.2, ladd=8, cmul=1.05), lips=None, earrings=None, stubble=-0.45),
 'diego':dict(hair=dict(da=-1, db=-3, lmul=0.8, ladd=-2, cmul=0.5), lips=None, earrings=None, stubble=0.35),
}
def lab_edit(bgr, m, da=0, db=0, lmul=1.0, ladd=0, cmul=1.0):
    lab=cv2.cvtColor(bgr,cv2.COLOR_BGR2LAB).astype(np.float32)
    L,a,b=lab[...,0],lab[...,1]-128,lab[...,2]-128
    w=np.clip(L/max(1,np.percentile(L[m>0.5],70) if (m>0.5).any() else 128),0.3,1.4)  # colour shift scales with brightness (dark strands stay dark)
    L2=L*lmul+ladd; a2=a*cmul+da*w; b2=b*cmul+db*w
    new=np.stack([np.clip(L2,0,255),np.clip(a2+128,0,255),np.clip(b2+128,0,255)],-1).astype(np.uint8)
    new=cv2.cvtColor(new,cv2.COLOR_LAB2BGR).astype(np.float32)
    mm=m[...,None]
    return np.clip(new*mm+bgr.astype(np.float32)*(1-mm),0,255).astype(np.uint8)
def run(c, eng):
    img=cv2.imread(f'{N}/{c}-n0.png'); v=cv2.imread(f'{N}/{c}-valid.png',0).astype(np.float32)/255
    ys,xs=np.where(v>0.99); y0,y1,x0,x1=ys.min(),ys.max(),xs.min(),xs.max()
    P=np.zeros(img.shape[:2]+(6,),np.float32); P[...,0]=1
    P[y0:y1,x0:x1]=seg.segment(img[y0:y1,x0:x1])
    P*=v[...,None]; P[...,0]+=1-v
    st=eng.prepare(cv2.cvtColor(img,cv2.COLOR_BGR2RGB)); l=st['lmk203']; f=st['face']
    cfg=CFG[c]; out=img.copy()
    hair=cv2.GaussianBlur(P[...,1],(0,0),1.5)
    out=lab_edit(out,hair,**cfg['hair'])
    lips=np.zeros(img.shape[:2],np.float32); cv2.fillPoly(lips,[cv2.convexHull(l[48:96].astype(np.int32))],1.0)
    lips=cv2.GaussianBlur(cv2.erode(lips,np.ones((3,3))),(0,0),2.5)
    if cfg['lips']: out=lab_edit(out,lips,**cfg['lips'])
    if cfg['earrings']=='silver':
        ear=(P[...,5]>0.35).astype(np.float32); ear[:int(f[5]),:]=0  # below eye level only
        ear=cv2.GaussianBlur(cv2.dilate(ear,np.ones((5,5))),(0,0),1.5)
        out=lab_edit(out,ear,lmul=1.12,ladd=6,cmul=0.08)
    if cfg['stubble']:
        # stubble zone: face skin below the nose, outside the lips; darken (or lighten) only the dark fine detail already there
        zone=cv2.erode((P[...,3]>0.5).astype(np.float32),np.ones((61,61))); zone[:int(f[9]+0.15*f[3]),:]=0
        zone*=1-cv2.dilate(lips,np.ones((15,15)))
        zone=cv2.GaussianBlur(zone,(0,0),8)
        lab=cv2.cvtColor(out,cv2.COLOR_BGR2LAB).astype(np.float32); L=lab[...,0]
        d=L-cv2.GaussianBlur(L,(0,0),5); dark=np.clip(d,-12,0)
        lab[...,0]=np.clip(L+cfg['stubble']*dark*zone*1.6,0,255)
        out=cv2.cvtColor(lab.astype(np.uint8),cv2.COLOR_LAB2BGR)
    cv2.imwrite(f'{O}/{c}.png',out); np.save(f'{O}/{c}-seg.npy',P.astype(np.float16))
    np.save(f'{O}/{c}-lmk.npy',l); np.save(f'{O}/{c}-face.npy',f)
    s=fl.stats(out,c); s.pop('emb'); print(c,'styled',s,flush=True)
if __name__=='__main__':
    from lp_engine import Engine
    eng=Engine()
    for c in sys.argv[1].split(','): run(c,eng)
