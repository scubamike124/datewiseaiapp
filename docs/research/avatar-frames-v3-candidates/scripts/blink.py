from lib import *
def morph(c,t=0.5,pyr=0.5,win=41,ctrl=None):
    m=man(c);x,y,w,h=m['frames']['blink_half']['rect']
    hero=cv2.resize(cv2.imread(R+f'assets/coaches/{c}-hero.jpg'),(m['width'],m['height']),interpolation=cv2.INTER_AREA)
    Ro=hero[y:y+h,x:x+w].copy();C=frame(c,'blink_closed')
    g1=cv2.GaussianBlur(cv2.cvtColor(Ro,cv2.COLOR_BGR2GRAY),(0,0),1.5);g2=cv2.GaussianBlur(cv2.cvtColor(C,cv2.COLOR_BGR2GRAY),(0,0),1.5)
    F=cv2.calcOpticalFlowFarneback(g1,g2,None,0.5,6,win,5,7,1.5,0)
    F=cv2.GaussianBlur(F,(0,0),3)
    H,W=g1.shape;yy,xx=np.mgrid[0:H,0:W].astype(np.float32)
    A=cv2.remap(Ro,(xx-t*F[...,0]).astype(np.float32),(yy-t*F[...,1]).astype(np.float32),cv2.INTER_CUBIC,borderMode=cv2.BORDER_REPLICATE)
    B=cv2.remap(C,(xx+(1-t)*F[...,0]).astype(np.float32),(yy+(1-t)*F[...,1]).astype(np.float32),cv2.INTER_CUBIC,borderMode=cv2.BORDER_REPLICATE)
    return ((1-t)*A.astype(np.float32)+t*B.astype(np.float32)).astype(np.uint8),Ro,C
if __name__=='__main__':
    rows=[]
    for c in ['ava','diego']:
        o,Ro,C=morph(c,0.5);rows.append(np.vstack([np.hstack([Ro,frame(c,'blink_half')]),np.hstack([o,C])]))
    [cv2.imwrite(f'../work/bh-{n}.png',r) for n,r in zip(['ava','diego'],rows)]
