import numpy as np, cv2, sys
D='/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad/softsmile/'
o=cv2.imread(D+'ethan-v3a2.png'); s=cv2.imread(D+'ethan-v3a2-soft-3.png'); mk=cv2.imread(D+'ethan-v3a2-mask.png',0)>0
H,W=mk.shape
lo=cv2.cvtColor(o,cv2.COLOR_BGR2LAB).astype(np.float32); ls=cv2.cvtColor(s,cv2.COLOR_BGR2LAB).astype(np.float32)
xs=np.arange(W,dtype=np.float32)
# hand-traced lip-top curves (original vs soft-3); identical outside 380..615 => identity map there
px=[360,380,392,425,470,500,530,575,600,615,640]
po=[600,600,589,587,584,586,583,585,590,600,600]
ps=[600,600,612,607,601,600,600,605,611,600,600]
to=np.interp(xs,px,po); ts=np.interp(xs,px,ps)
mt=np.array([np.argmax(mk[:,x]) if mk[:,x].any() else H for x in range(W)],np.float32)
yy,xx=np.mgrid[0:H,0:W].astype(np.float32)
T0=mt[None,:]; TO=to[None,:]; TS=ts[None,:]
# map soft band [mt, ts] -> orig band [mt, to]
frac=np.clip((yy-T0)/np.maximum(TS-T0,1),0,1)
mapy=np.where(yy<TS, T0+frac*(TO-T0), yy).astype(np.float32)
mapy=np.where(yy<T0, yy, mapy).astype(np.float32)
ow=cv2.remap(lo,xx,mapy,cv2.INTER_LINEAR)
# weight: moustache band inside mask, fading out 5px above soft lip top
w=np.clip((TS-3-yy)/5,0,1)*(yy>=T0)*mk
w=cv2.GaussianBlur(w.astype(np.float32),(0,0),1.5)*mk
sig=float(sys.argv[1]) if len(sys.argv)>1 else 3.0
def hf(L): return L-cv2.GaussianBlur(L,(0,0),sig)
out=ls.copy()
# luminance: replace soft's smeared detail with original stubble detail
out[...,0]=ls[...,0]-w*hf(ls[...,0])+w*hf(ow[...,0])
# also match low-freq luminance mildly toward the warped original (stubble density/tone)
lowS=cv2.GaussianBlur(ls[...,0],(0,0),sig); lowO=cv2.GaussianBlur(ow[...,0],(0,0),sig)
out[...,0]+=w*0.5*(lowO-lowS)
# chroma: remove orange/brown cast in non-lip skin inside mask (push b-a toward original stubble ~0)
lf=cv2.GaussianBlur(out,(0,0),3); d=lf[...,2]-lf[...,1]
skin=np.clip((d+1)/2,0,1)*np.clip((146-lf[...,1])/3,0,1)
delta=cv2.GaussianBlur(np.clip(d-0.5,0,None)*skin,(0,0),1.5)
# blotches: also pull a,b toward a smooth local skin estimate
out[...,1]+=delta*0.5; out[...,2]-=delta*0.5
for c in (1,2):
    hfc=out[...,c]-cv2.GaussianBlur(out[...,c],(0,0),6)
    out[...,c]-=0.6*hfc*w + 0.6*hfc*skin*(1-w)
res=cv2.cvtColor(np.clip(out,0,255).astype(np.uint8),cv2.COLOR_LAB2BGR)
# remove the small pale bead at the left mouth corner
pm=np.zeros((H,W),np.uint8); cv2.circle(pm,(389,609),4,255,-1); pm[~mk]=0
res=cv2.inpaint(res,pm,3,cv2.INPAINT_TELEA)
res[~mk]=s[~mk]
cv2.imwrite(D+'ethan-v3a2-soft-3-fixed.png',res)
