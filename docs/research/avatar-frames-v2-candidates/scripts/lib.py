import cv2,numpy as np,json,os
R='/home/user/datewiseaiapp/'
OUT='/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad/avatar-frames-v2/'
def man(c): return json.load(open(R+f'assets/avatar/{c}/manifest.json'))
def frame(c,n): return cv2.imread(R+f'assets/avatar/{c}/{n}.jpg')
def hero_patch(c):
    m=man(c);h=cv2.imread(R+f'assets/coaches/{c}-hero.jpg')
    h=cv2.resize(h,(m['width'],m['height']),interpolation=cv2.INTER_AREA)
    x,y,w,hh=m['frames']['a']['rect'];return h[y:y+hh,x:x+w].copy()
def lab(img):
    l=cv2.cvtColor(img,cv2.COLOR_BGR2LAB).astype(np.float32);l[...,0]*=100/255.;l[...,1:]-=128;return l
def unlab(l):
    l=l.copy();l[...,0]*=255/100.;l[...,1:]+=128
    return cv2.cvtColor(np.clip(l,0,255).astype(np.uint8),cv2.COLOR_LAB2BGR)
def teeth_mask(img,lmin=55,amax=13):
    L=lab(img);return ((L[...,0]>lmin)&(L[...,1]<amax)).astype(np.uint8)
