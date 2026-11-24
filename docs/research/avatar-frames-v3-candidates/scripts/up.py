from ov import *
from srcteeth import src_teeth
from tones import TONE
def fitq(xs,ys,deg=2):
    p=np.polyfit(xs,ys,deg);return p
def src_strip(c):
    im,T=src_teeth(c);H,W=T.shape
    cols=[x for x in range(W) if T[:,x].sum()>=6]
    xs=np.array(cols);bot=np.array([np.nonzero(T[:,x])[0].max() for x in cols],np.float32)
    hh=np.array([T[:,x].sum() for x in cols],np.float32)
    # robust: use upper envelope of heights
    h=float(np.percentile(hh,75))
    pb=np.polyfit(xs,bot,2)
    return im,dict(xl=float(np.percentile(xs,2)),xr=float(np.percentile(xs,98)),pb=pb,h=h)
def up_texture(f,c,T,info,yb,ext=0.06):
    """returns RGB float image same size as f with the coach's own upper teeth texture mapped into the upper-teeth region, and column top curve"""
    H,W=f.shape[:2];im,s=src_strip(c)
    al=soft_teeth(f,50)
    xs=np.arange(W)
    up=np.zeros((H,W),np.float32)
    top=np.full(W,np.nan,np.float32)
    for x in range(int(info['xl']),int(info['xr'])):
        col=np.nonzero((al[:int(yb[x])+1,x]>0.5))[0]
        if len(col)>3: top[x]=col.min()
    ok=~np.isnan(top);pt=np.polyfit(xs[ok],top[ok],2);topc=np.polyval(pt,xs)
    topc=np.minimum(topc,yb-8)
    xlt,xrt=info['xl'],info['xr'];wt=xrt-xlt
    u=(xs-xlt)/wt;xsrc=s['xl']+u*(s['xr']-s['xl'])
    bs=np.polyval(s['pb'],xsrc)
    yy=np.arange(H,dtype=np.float32)[:,None]
    v=np.clip((yy-topc[None,:])/np.maximum(yb[None,:]-topc[None,:],1),-0.3,1.3)
    ysrc=(bs[None,:]-s['h']+v*s['h']).astype(np.float32)
    mapx=np.tile(xsrc[None,:],(H,1)).astype(np.float32)
    tex=cv2.remap(im,mapx,ysrc,cv2.INTER_CUBIC,borderMode=cv2.BORDER_REPLICATE)
    return tex,topc
if __name__=='__main__':
    import sys
    for c in ['ava','ethan','sofia']:
        f=frame(c,'a');H,W=f.shape[:2];T,info=analyse(f,c);info['Lbright']=float(np.percentile(info['Lc'][T>0],85))
        tn=TONE[c];yb=bite_curve(T,info,W,tn.get('win',7),tn.get('deg',2))
        tex,topc=up_texture(f,c,T,info,yb)
        al=soft_teeth(f,50);yy=np.arange(H)[:,None]
        m=(al*(yy<yb[None,:]+0.5))[...,None]
        o=(f*(1-m)+tex*m).astype(np.uint8)
        cv2.imwrite(f'../work/up-{c}.png',cv2.resize(np.hstack([f,o])[60:260,70:400+0],None,fx=2,fy=2) if False else cv2.resize(np.hstack([f[90:230,100:360],o[90:230,100:360]]),None,fx=3,fy=3,interpolation=cv2.INTER_CUBIC))
