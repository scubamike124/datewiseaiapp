from lib import *
def gaussian_filter1d(a,s):
    return cv2.GaussianBlur(np.asarray(a,np.float32).reshape(-1,1),(0,0),s).ravel()

def ell(c,shape,rx=0.46,ry=0.24,dy=0.03):
    m=man(c);x0,y0=m['frames']['a']['rect'][:2];mx=m['mouth'][0]-x0;my=m['mouth'][1]-y0;mw=m['mouth_width']
    e=np.zeros(shape[:2],np.uint8);cv2.ellipse(e,(int(mx),int(my+dy*mw)),(int(rx*mw),int(ry*mw)),0,0,360,1,-1);return e
LM={'ava':(52,14),'sofia':(52,14),'diego':(50,14),'ethan':(42,15)}
def analyse(img,c):
    lm,am=LM[c];T=teeth_mask(img,lm,am)*ell(c,img.shape)
    n,lb,st,_=cv2.connectedComponentsWithStats(T)
    keep=[i for i in range(1,n) if st[i,4]>25];T=np.isin(lb,keep).astype(np.uint8)
    ys,xs=np.nonzero(T);L=lab(img)[...,0]
    cx=float(np.median(xs));xl,xr=np.percentile(xs,[1,99]);top=ys.min();bot=ys.max()
    cen=cv2.GaussianBlur(L[:,int(cx-22):int(cx+22)].mean(1).reshape(-1,1),(0,0),1.0).ravel()
    lo=int(top+0.3*(bot-top));hi=int(top+0.78*(bot-top))
    y0=lo+int(np.argmin(cen[lo:hi]))
    return T,dict(cx=cx,xl=xl,xr=xr,y0=y0,top=top,bot=bot,Lc=L)

def bite_curve(T,info,W,win=7,deg=2):
    y0=info['y0'];L=info['Lc'];ys=np.full(W,np.nan)
    for x in range(int(info['xl'])+2,int(info['xr'])-1):
        col=L[y0-win:y0+win+1,max(0,x-1):x+2].mean(1)
        # require teeth-bright on both sides
        if col.max()<info['Lbright']*0.8: continue
        ys[x]=y0-win+float(np.argmin(col))
    xs=np.arange(W);ok=~np.isnan(ys)
    if ok.sum()<10: return np.full(W,float(y0))
    p=np.polyfit(xs[ok],ys[ok],deg);cur=np.polyval(p,xs);cur=y0+0.45*(cur-y0);return np.clip(cur,y0-win+2,y0+win-2)

def soft_teeth(img,alo=60):
    L=lab(img);al=np.clip((L[...,0]-alo)/10,0,1)*np.clip((15-L[...,1])/4,0,1)
    return cv2.GaussianBlur(al,(0,0),0.7)

def repair_teeth(img,c,T,info,yb,tone):
    """close thin dark vertical gaps between teeth (keeps a hint of shading)"""
    L=lab(img);H,W=T.shape
    reg=cv2.dilate(T,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(5,5)))
    yy=np.arange(H)[:,None];band=(np.abs(yy-yb[None,:])<=tone.get('band',3.5))
    Lc=cv2.morphologyEx(L[...,0],cv2.MORPH_CLOSE,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(tone.get('kw',5),tone.get('kh',5))))
    Lc=cv2.morphologyEx(Lc,cv2.MORPH_OPEN,np.ones((1,3),np.uint8)) if False else Lc
    m=cv2.GaussianBlur((reg*(~band)).astype(np.float32),(0,0),1.0)
    Lt=np.percentile(L[...,0][T>0],70)
    tgt=np.minimum(Lc,Lt)
    new=np.maximum(L[...,0],tone['gap_floor']*np.minimum(tgt,Lt))
    new=0.55*L[...,0]+0.45*np.maximum(L[...,0],tgt*tone['gap_floor'])
    d=(L[...,0]<0.9*tgt)
    mm=m*d
    L2=L.copy();L2[...,0]=L[...,0]*(1-mm)+new*mm
    L2[...,1]=L[...,1]*(1-mm)+np.minimum(L[...,1],tone['a']+2)*mm
    return unlab(L2)

def tone_teeth(img,info,yb,d,tone,hw):
    L=lab(img);H,W=L.shape[:2];al=soft_teeth(img,tone.get('alo',60))[...,None]
    xx=np.arange(W)[None,:].astype(np.float32);yy=np.arange(H)[:,None].astype(np.float32)
    # lift/limit brightness to target
    Lm=np.percentile(L[...,0][al[...,0]>0.8],85)
    s=min(tone['Ltarget']/Lm,1.04)
    Ln=np.minimum(L[...,0]*s,tone['Lmax'])
    # shading
    hx=np.abs(xx-info['cx'])/hw
    sh=1-tone['corner']*np.clip(hx,0,1.2)**2
    ybx=yb[None,:]
    up=(yy<ybx);dn=(yy>=ybx+d[None,:])
    dist_up=np.clip(ybx-yy,0,60);dist_dn=np.clip(yy-(ybx+d[None,:]),0,60)
    sh=sh*np.where(up,1-tone['edge']*np.exp(-dist_up/4.0),1)
    sh=sh*np.where(dn,1-tone['edge_dn']*np.exp(-dist_dn/5.0),1)
    Ln=Ln*sh
    an=L[...,1]*0.4+tone['a']*0.6;bn=L[...,2]*0.35+tone['b']*0.65
    out=L.copy();w=al[...,0]
    shade=np.clip(1-sh,0,1)  # shaded teeth go warm, not grey
    bn=bn+shade*10;an=an+shade*3
    out[...,0]=L[...,0]*(1-w)+Ln*w;out[...,1]=L[...,1]*(1-w)+an*w;out[...,2]=L[...,2]*(1-w)+bn*w
    return unlab(out)

def open_vowel(c,name,D,tone,tongue=True,lr=0.40,taper_pow=0.8,tongue_up=False,src=None):
    f=frame(c,name) if src is None else src.copy()
    H,W=f.shape[:2];T,info=analyse(f,c);info['Lbright']=float(np.percentile(info['Lc'][T>0],85));yb=bite_curve(T,info,W,tone.get('win',7),tone.get('deg',2))
    mw=man(c)['mouth_width'];hw=(info['xr']-info['xl'])/2*1.05
    f=repair_teeth(f,c,T,info,yb,tone)
    xs=np.arange(W,dtype=np.float32)
    tap=np.clip(1-((xs-info['cx'])/hw)**2,0,1)**taper_pow
    d=D*tap
    yy=np.arange(H,dtype=np.float32)[:,None]
    ybx=yb[None,:].astype(np.float32);dx=d[None,:]
    t=np.clip((yy-(ybx+dx))/(lr*mw),0,1);g=0.5*(1+np.cos(np.pi*t))
    srcy=np.where(yy<=ybx,yy,np.where(yy<=ybx+dx,ybx,yy-dx*g))
    mapx=np.tile(xs[None,:],(H,1));mapy=srcy.astype(np.float32)
    Wp=cv2.remap(f,mapx,mapy,cv2.INTER_CUBIC,borderMode=cv2.BORDER_REPLICATE)
    # cavity fill
    tw=mw*0.058;ph=np.random.RandomState(hash(c)%1000).rand()*6
    bump=(1-np.cos(2*np.pi*(xs[None,:]+ph)/tw))/2
    cen=np.clip(1-np.abs(xs[None,:]-info['cx'])/(hw*0.6),0,1)
    gapm=((yy>=ybx-2.5+1.4*np.clip(1-np.abs(xs[None,:]-info['cx'])/(hw*0.5),0,1)**1.5)&(yy<=ybx+dx+2.2+1.3*bump)&(dx>0.9)).astype(np.float32)
    gapm=cv2.GaussianBlur(gapm,(0,0),1.15)
    u=np.clip((yy-(ybx-3))/(dx+5),0,1)
    Lc=9+16*u**1.3;ac=13+8*u;bc=7+3*u
    # side darkening toward corners
    hxn=np.clip(np.abs(xs[None,:]-info['cx'])/hw,0,1);Lc=Lc*(1-0.3*hxn**2)
    cav=np.stack([Lc,ac+0*Lc,bc+0*Lc],-1).astype(np.float32)
    if tongue:
        ty=ybx+dx*(0.8 if not tongue_up else 0.3)+1
        e=((xs[None,:]-info['cx'])/(0.2*(info['xr']-info['xl'])))**2+((yy-ty)/(max(dx.max(),4)*(0.5)))**2
        tm=np.clip(1.5-e*1.1,0,1);tm=cv2.GaussianBlur(tm,(0,0),2.2)*(dx>2)
        tl=np.stack([32+8*np.clip(1-e,0,1),21+0*e,12+0*e],-1)
        cav=cav*(1-tm[...,None]*0.65)+tl*tm[...,None]*0.65
    cavb=unlab(cav)
    out=Wp.astype(np.float32)*(1-gapm[...,None])+cavb.astype(np.float32)*gapm[...,None]
    base=out.astype(np.uint8)
    out=tone_teeth(base,info,yb,d,tone,hw)
    out=soften_cracks(out,gapm,tone)
    out=warm_darks(out,c)
    E=cv2.GaussianBlur(ell(c,f.shape,0.50,0.30).astype(np.float32),(0,0),4)[...,None]
    return np.clip(out.astype(np.float32)*E+base.astype(np.float32)*(1-E),0,255).astype(np.uint8)

def teeth_detail(img,cx,tw,seed,tone,depth=0.13,al=None,lift=0.0):
    """subtle interdental lines, per-tooth edge shading, ivory tint inside the (soft) teeth mask"""
    H,W=img.shape[:2];L=lab(img);al=soft_teeth(img) if al is None else al
    rs=np.random.RandomState(seed);offs=[0,1.15,2.05,2.85,3.55,4.15]
    xs=np.arange(W,dtype=np.float32)
    bounds=[cx+rs.uniform(-0.12,0.12)*tw]
    for k in offs[1:]:
        bounds+= [cx+k*tw+rs.uniform(-.14,.14)*tw, cx-k*tw+rs.uniform(-.14,.14)*tw]
    bounds=sorted(bounds)
    line=np.zeros(W,np.float32)
    for i,b in enumerate(bounds):
        k=abs(b-cx)/tw;line+=np.exp(-((xs-b)/0.95)**2)*(1-0.1*k)*rs.uniform(.75,1.1)
    # per-tooth edge shading
    seg=np.zeros(W,np.float32)
    bb=[-1e9]+bounds+[1e9]
    for i in range(len(bb)-1):
        lo,hi=max(bb[i],cx-6*tw),min(bb[i+1],cx+6*tw)
        if hi-lo<2: continue
        m=(xs>=lo)&(xs<=hi);xc=(lo+hi)/2;w=hi-lo
        seg[m]=((xs[m]-xc)/(w/2))**2
    mod=1-depth*line-0.07*seg
    Ln=L[...,0]*(mod[None,:]*al+(1-al))+lift*al*(100-L[...,0])*0
    L2=L.copy();L2[...,0]=Ln
    w=al
    L2[...,1]=L[...,1]*(1-w*0.6)+tone['a']*w*0.6
    L2[...,2]=L[...,2]*(1-w*0.6)+tone['b']*w*0.6
    return unlab(L2)


def warm_darks(img,c):
    """near-black interior pixels (corner wedges, bite remnants) -> dark red-brown cavity colour"""
    L=lab(img);e=cv2.dilate(ell(c,img.shape,0.40,0.20),np.ones((3,3),np.uint8)).astype(np.float32)
    dark=np.clip((34-L[...,0])/12,0,1)*np.clip((20-L[...,1])/8,0,1)*e
    dark=cv2.GaussianBlur(dark,(0,0),0.8)
    L2=L.copy();L2[...,0]=np.maximum(L[...,0],L[...,0]*(1-dark)+22*dark)
    L2[...,1]=L[...,1]*(1-dark)+13*dark;L2[...,2]=L[...,2]*(1-dark)+6*dark
    return unlab(L2)


def soften_cracks(img,gapm,tone):
    L=lab(img);Tn=(soft_teeth(img,tone.get('alo',60))>0.6).astype(np.uint8)
    near=cv2.dilate(Tn,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(11,11))).astype(np.float32)
    # neighbours both above and below... keep simple: only inside the teeth hull
    hull=cv2.morphologyEx(Tn,cv2.MORPH_CLOSE,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(25,15)))
    gm=cv2.dilate((gapm>0.15).astype(np.uint8),np.ones((5,5),np.uint8)).astype(np.float32)
    dark=np.clip((40-L[...,0])/10,0,1)*np.clip((22-L[...,1])/6,0,1)*cv2.GaussianBlur(hull.astype(np.float32),(0,0),1.5)*(1-np.clip(gm,0,1))
    dark=cv2.GaussianBlur(dark,(0,0),0.7)
    L2=L.copy();tgt=tone.get('crack',44.0)
    L2[...,0]=L[...,0]*(1-dark*0.8)+np.maximum(L[...,0],tgt)*dark*0.8
    L2[...,1]=L[...,1]*(1-dark*0.7)+5*dark*0.7;L2[...,2]=L[...,2]*(1-dark*0.7)+14*dark*0.7
    return unlab(L2)
