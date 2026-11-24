from paint import *
from lipo import lip_only,remove_tail_box
from sofia_i import enhance
def save(c,n,img): cv2.imwrite(OUT+f'{c}/{n}.jpg',img,[cv2.IMWRITE_JPEG_QUALITY,88])
rs=np.random.RandomState(3)
for n in ['o','o2']:
    o,M=lip_only('ava',n,S=1.22)
    o2,m=remove_tail_box(o,(118,174,146,165))
    g=cv2.GaussianBlur(m.astype(np.float32),(0,0),1.5)[...,None]
    nz=cv2.GaussianBlur(rs.normal(0,1,o.shape[:2]).astype(np.float32),(0,0),0.6)[...,None]*2.2
    o2=np.clip(o2.astype(np.float32)+nz*g,0,255).astype(np.uint8)
    save('ava',n,o2)
    o,M=lip_only('ethan',n,S=1.24);save('ethan',n,o)
for n in ['i2','sh']: save('sofia',n,enhance('sofia',n))
