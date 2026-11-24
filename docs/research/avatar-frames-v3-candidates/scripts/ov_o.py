from lib import *
def soften(c,name,a_lip=0.45,a_skin=0.8,sig=6):
    o=frame(c,name);r=hero_patch(c);H,W=o.shape[:2]
    go=cv2.cvtColor(o,cv2.COLOR_BGR2GRAY);gr=cv2.cvtColor(r,cv2.COLOR_BGR2GRAY)
    go=cv2.GaussianBlur(go,(0,0),1.5);gr=cv2.GaussianBlur(gr,(0,0),1.5)
    F=cv2.calcOpticalFlowFarneback(go,gr,None,0.5,5,31,5,7,1.5,0)
    F=cv2.GaussianBlur(F,(0,0),sig)
    # border fade (keeps the seam identical to the portrait)
    yy,xx=np.mgrid[0:H,0:W].astype(np.float32)
    bd=np.minimum(np.minimum(xx,W-1-xx),np.minimum(yy,H-1-yy))
    fade=np.clip(bd/28.0,0,1)**1.5
    # lips region (red-ish) gets less correction
    L=lab(o);lip=np.clip((L[...,1]-14)/10,0,1);lip=cv2.GaussianBlur(lip,(0,0),6)
    alpha=(a_skin*(1-lip)+a_lip*lip)*fade
    mapx=(xx-alpha*F[...,0]).astype(np.float32);mapy=(yy-alpha*F[...,1]).astype(np.float32)
    return cv2.remap(o,mapx,mapy,cv2.INTER_CUBIC,borderMode=cv2.BORDER_REPLICATE),F
def soft_o(c,name,S=1.28,sv=1.07,a_lip=0.4,a_skin=0.8,rx=0.62,ry=0.30,dyc=0.03):
    s,F=soften(c,name,a_lip,a_skin);H,W=s.shape[:2]
    m=man(c);x0,y0=m['frames']['a']['rect'][:2];mx=m['mouth'][0]-x0;my=m['mouth'][1]-y0+dyc*m['mouth_width'];mw=m['mouth_width']
    yy,xx=np.mgrid[0:H,0:W].astype(np.float32)
    e=((xx-mx)/(rx*mw))**2+((yy-my)/(ry*mw))**2
    w=np.clip(1-e,0,1)**0.8
    mapx=xx-(xx-mx)*(1-1/S)*w;mapy=yy-(yy-my)*(1-1/sv)*w
    return cv2.remap(s,mapx.astype(np.float32),mapy.astype(np.float32),cv2.INTER_CUBIC,borderMode=cv2.BORDER_REPLICATE)
def lipmask(img,m_a=7):
    L=lab(img);H,W=img.shape[:2]
    ring=np.concatenate([L[:12,:,1].ravel(),L[:, :12,1].ravel()]);sk=np.median(ring)
    lp=((L[...,1]>sk+m_a)|(L[...,0]<28)).astype(np.uint8)
    lp=cv2.morphologyEx(lp,cv2.MORPH_OPEN,np.ones((3,3),np.uint8))
    lp=cv2.morphologyEx(lp,cv2.MORPH_CLOSE,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(9,9)))
    n,lb,st,_=cv2.connectedComponentsWithStats(lp)
    if n>1:
        k=1+int(np.argmax(st[1:,4]));lp=(lb==k).astype(np.uint8)
    return lp
def soft_o2(c,name,ex=0.60,ey=0.21,S=1.28,sv=1.07,rx=0.62,ry=0.30,dil=8,feather=5,a_lip=0.4,a_skin=0.8):
    s=soft_o(c,name,S,sv,a_lip,a_skin,rx,ry);r=hero_patch(c)
    m=man(c);x0,y0=m['frames']['a']['rect'][:2];mx=m['mouth'][0]-x0;my=m['mouth'][1]-y0+0.03*m['mouth_width'];mw=m['mouth_width']
    H,W=s.shape[:2];yy,xx=np.mgrid[0:H,0:W].astype(np.float32)
    ml=((((xx-mx)/(ex*mw))**2+((yy-my)/(ey*mw))**2)<1).astype(np.float32)
    ml=cv2.GaussianBlur(ml,(0,0),feather)
    # skin part: take rest, but keep o's lighting by low-frequency match inside the feather band
    out=s.astype(np.float32)*ml[...,None]+r.astype(np.float32)*(1-ml[...,None])
    return np.clip(out,0,255).astype(np.uint8),ml
if __name__=='__main__':
    rows=[]
    for c in ['ava','sofia','ethan','diego']:
        rs=[hero_patch(c)[70:250,80:420]]
        for n in ['o','o2']:
            o,ml=soft_o2(c,n);rs+= [frame(c,n)[70:250,80:420],o[70:250,80:420]]
        rows.append(np.hstack(rs))
    cv2.imwrite('t8.jpg',np.vstack(rows))
