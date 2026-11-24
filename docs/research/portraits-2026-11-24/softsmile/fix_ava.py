import numpy as np, cv2
D='/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad/softsmile/'
s=cv2.imread(D+'ava-1-blazer-soft-17.png'); m=cv2.imread(D+'ava-1-blazer-mask.png',0)>0
lab=cv2.cvtColor(s,cv2.COLOR_BGR2LAB).astype(np.float32)
H,W=m.shape; yy,xx=np.mgrid[0:H,0:W].astype(np.float32)
# 1) chroma: remove yellow excess on left side
lf=cv2.GaussianBlur(lab,(0,0),5); d=lf[...,2]-lf[...,1]
sp=np.clip((440-xx)/30,0,1)
delta=cv2.GaussianBlur(np.clip(d-3,0,None)*sp,(0,0),2)
lab[...,1]+=delta*0.55; lab[...,2]-=delta*0.45
# 2) soften the waxy bulge: attenuate mid-frequency luminance in a feathered disc at the corner
r=np.hypot(xx-362,(yy-510)*1.1)
wd=np.clip((26-r)/12,0,1)*m
wd=cv2.GaussianBlur(wd.astype(np.float32),(0,0),3)
L=lab[...,0]; g1=cv2.GaussianBlur(L,(0,0),1.5); g2=cv2.GaussianBlur(L,(0,0),9)
mid=g1-g2
lab[...,0]=L-mid*0.55*wd
out=cv2.cvtColor(np.clip(lab,0,255).astype(np.uint8),cv2.COLOR_LAB2BGR)
out[~m]=s[~m]
cv2.imwrite(D+'ava-1-blazer-soft-17-fixed.png',out)
