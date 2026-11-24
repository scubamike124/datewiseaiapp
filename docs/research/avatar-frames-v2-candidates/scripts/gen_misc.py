from ov import *;from tones import TONE
from ov_o import soft_o2
from ava_fix import fix_blotch
from fv import make_fv
def mxy(c):
    m=man(c);x0,y0=m['frames']['a']['rect'][:2];return m['mouth'][0]-x0,m['mouth'][1]-y0,m['mouth_width']
def save(c,n,img): cv2.imwrite(OUT+f'{c}/{n}.jpg',img,[cv2.IMWRITE_JPEG_QUALITY,88])
# o/o2 all coaches
for c in ['ava','ethan','sofia','diego']:
    for n in ['o','o2']:
        S=1.2 if c=='diego' else 1.28
        o,_=soft_o2(c,n,S=S);save(c,n,o)
# fv ava,sofia
for c in ['ava','sofia']: save(c,'fv',make_fv(c))
# ava a blotch
n=cv2.imread(OUT+'ava/a.jpg');n,_=fix_blotch(n);save('ava','a',n)
# sofia i2 / sh teeth detail
c='sofia';mx,my,mw=mxy(c);t=dict(TONE[c])
for n in ['i2','sh']:
    f=frame(c,n);al=np.clip((lab(f)[...,0]-62)/10,0,1)*np.clip((14-lab(f)[...,1])/4,0,1)
    al=cv2.GaussianBlur(al,(0,0),0.7)
    save(c,n,teeth_detail(f,mx,mw*0.058,7,t,depth=0.085,al=al))
