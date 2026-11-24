from lib import *
SS=R+'../../tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad/softsmile/'
SS='/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad/softsmile/'
SRC={'ava':('ava-1-blazer.png',(445,525)),'ethan':('ethan-v3a2.png',(448,600)),'sofia':('sofia-v3a1.png',(448,600))}
ROI={'ava':(105,240,80,135),'ethan':(140,290,100,142),'sofia':(115,250,60,100)}
def src_teeth(c):
    """returns dict: img(BGR), mask(float), per-column top/bot, xs range of the upper-teeth component in source px (crop coords), crop"""
    n,(cx,cy)=SRC[c];im=cv2.imread(SS+n)[cy-110:cy+110,cx-170:cx+170]
    L=lab(im);T=((L[...,0]>34)&(L[...,1]<8.5)&(L[...,2]<22)).astype(np.uint8)
    x0,x1,y0,y1=ROI[c];r=np.zeros_like(T);r[y0:y1,x0:x1]=1;T=T*r
    T=cv2.morphologyEx(T,cv2.MORPH_OPEN,np.ones((2,2),np.uint8))
    nn,lb,st,_=cv2.connectedComponentsWithStats(T)
    k=1+int(np.argmax(st[1:,4]));T=(lb==k).astype(np.uint8)
    T=cv2.morphologyEx(T,cv2.MORPH_CLOSE,np.ones((3,5),np.uint8))
    return im,T
if __name__=='__main__':
    for c in SRC:
        im,T=src_teeth(c);o=im.copy();o[T==0]=o[T==0]//3
        cv2.imwrite(f'../work/srcT-{c}.png',cv2.resize(np.hstack([im,o]),None,fx=2.5,fy=2.5,interpolation=cv2.INTER_CUBIC))

def src_curves(c,deg=2):
    im,T=src_teeth(c);h,w=T.shape
    cols=np.array([x for x in range(w) if T[:,x].sum()>=5])
    top=np.array([np.nonzero(T[:,x])[0].min() for x in cols],np.float32)
    bot=np.array([np.nonzero(T[:,x])[0].max() for x in cols],np.float32)
    pt=np.polyfit(cols,top,deg);pb=np.polyfit(cols,bot,deg)
    return im,T,cols,pt,pb
def tex_map(c,W,H,xa,xb,ytop,edge,pad=10,inset=1.5):
    im,T,cols,pt,pb=src_curves(c)
    sx0=cols[0]-pad;sx1=cols[-1]+pad
    xs=np.arange(W,dtype=np.float32);u=np.clip((xs-xa)/(xb-xa),0,1);sx=sx0+u*(sx1-sx0)
    ts=np.polyval(pt,sx)+inset;bs=np.polyval(pb,sx)+0.5
    yy=np.arange(H,dtype=np.float32)[:,None]
    v=np.clip((yy-ytop[None,:])/np.maximum(edge[None,:]-ytop[None,:],1),-0.1,1.1)
    ysrc=(ts[None,:]+v*(bs-ts)[None,:]).astype(np.float32)
    mx=np.tile(sx[None,:],(H,1)).astype(np.float32)
    tex=cv2.remap(im,mx,ysrc,cv2.INTER_CUBIC,borderMode=cv2.BORDER_REPLICATE)
    al=cv2.remap(T.astype(np.float32),mx,ysrc,cv2.INTER_LINEAR,borderMode=cv2.BORDER_CONSTANT,borderValue=0)
    return tex,al
