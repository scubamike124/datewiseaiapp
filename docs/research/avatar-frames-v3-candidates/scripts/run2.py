import sys
from paint2 import *
c=sys.argv[1];rows=[]
for n,D,tu in [('a',20,False),('a2',15,False),('l',10,True)]:
    o,g=paint_open2(c,n,D,tu);f=frame(c,n)
    rows.append(cv2.resize(np.hstack([f[80:250,90:380],o[80:250,90:380]]),None,fx=2.5,fy=2.5,interpolation=cv2.INTER_CUBIC))
cv2.imwrite(f'../work/q-{c}.png',np.vstack(rows))
