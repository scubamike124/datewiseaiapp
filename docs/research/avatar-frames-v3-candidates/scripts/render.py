from ov import soft_teeth,analyse,bite_curve,ell,unlab,lab,frame,man,cv2,np,warm_darks
from lib import *
from tones import TONE
def blur(a,s): return cv2.GaussianBlur(a.astype(np.float32),(0,0),s)
BASE={'ava':(78,3.0,10.0),'ethan':(75,4.0,10.5),'sofia':(75,3.0,9.5),'diego':(74,2.5,11.0)}
def seed(c,n): return (sum(map(ord,c+n))*7919)%100000
def geometry(f,c):
    H,W=f.shape[:2];T,info=analyse(f,c);info['Lbright']=float(np.percentile(info['Lc'][T>0],85))
    tn=TONE[c];yb=bite_curve(T,info,W,tn.get('win',7),tn.get('deg',2));return T,info,yb
def col_edge(al,y_lo,y_hi,info,W,fn):
    xs=np.arange(W);v=np.full(W,np.nan,np.float32)
    for x in range(int(info['xl']),int(info['xr'])):
        col=np.nonzero(al[int(y_lo[x]):int(y_hi[x])+1,x]>0.5)[0]
        if len(col)>2: v[x]=fn(col)+int(y_lo[x])
    ok=~np.isnan(v);p=np.polyfit(xs[ok],v[ok],2);return np.polyval(p,xs)
def tooth_bounds(L,info,topc,yb,mw,rs):
    W=L.shape[1];xl,xr=info['xl'],info['xr'];prof=np.zeros(W,np.float32)
    for x in range(W):
        a=int(topc[x])+3;b=int(yb[x])-2;prof[x]=L[a:b,x].mean() if b>a else 0
    prof=blur(prof.reshape(-1,1),0.9).ravel();xs=[]
    for x in range(int(xl)+8,int(xr)-8):
        w=prof[x-3:x+4]
        if prof[x]==w.min() and w.max()-prof[x]>2.0 and (not xs or x-xs[-1]>0.07*mw): xs.append(x)
    bs=[xl]+xs+[xr];res=[bs[0]]
    for b in bs[1:]:
        g=b-res[-1];n=int(round(g/(0.125*mw)))
        for k in range(1,max(n,1)): res.append(res[-1]+g/n)
        res.append(b)
    # jitter inner boundaries a little
    res=[res[0]]+[r+rs.uniform(-1.2,1.2) for r in res[1:-1]]+[res[-1]]
    return sorted(res)
def tooth_field(W,bnds,rs,sig):
    """per-column tooth index fields: u in [0,1] inside tooth, dL, db random per tooth, offset for incisal edge"""
    xs=np.arange(W,dtype=np.float32);u=np.zeros(W,np.float32);dl=np.zeros(W,np.float32);db=np.zeros(W,np.float32);off=np.zeros(W,np.float32);line=np.zeros(W,np.float32)
    for i in range(len(bnds)-1):
        a,b=bnds[i],bnds[i+1];m=(xs>=a)&(xs<b)
        u[m]=(xs[m]-a)/max(b-a,1);dl[m]=rs.normal(0,sig[0]);db[m]=rs.normal(0,sig[1]);off[m]=rs.uniform(-1.0,1.0)
    for b in bnds[1:-1]: line+=np.exp(-((xs-b)/0.9)**2)*rs.uniform(0.7,1.1)
    return u,blur(dl.reshape(-1,1),0.8).ravel(),blur(db.reshape(-1,1),0.8).ravel(),blur(off.reshape(-1,1),1.0).ravel(),line,
def shade_upper(f,c,n,T,info,yb,mw,Au,topc):
    H,W=f.shape[:2];L=lab(f);rs=np.random.RandomState(seed(c,n))
    bnds=tooth_bounds(L[...,0],info,topc,yb,mw,rs)
    u,dl,db,off,line=tooth_field(W,bnds,rs,(2.0,1.0))[:5]
    yy=np.arange(H,dtype=np.float32)[:,None];xs=np.arange(W,dtype=np.float32)[None,:]
    v=np.clip((yy-topc[None,:])/np.maximum(yb[None,:]-topc[None,:],1),0,1)
    Lb,ab,bb=BASE[c];hx=np.clip(np.abs(xs-info['cx'])/((info['xr']-info['xl'])/2),0,1.1)
    prof=1-0.16*np.exp(-v/0.16)*1.0-0.05*np.clip((v-0.82)/0.18,0,1)   # lip shadow on top, slight dimming at the incisal edge
    prof=prof+0.025*np.exp(-((v-0.5)/0.25)**2)
    ut=(2*u[None,:]-1)
    Lm=(Lb+dl[None,:])*prof*(1-0.20*hx**2)*(1-0.05*ut**2)
    Lm=Lm*(1-0.10*line[None,:]*(1-0.5*v))
    hi=np.clip(L[...,0]-blur(L[...,0],2.2),-6,6)
    Ln=Lm+0.4*hi
    shade=np.clip(1-Lm/Lb,0,0.4)
    an=ab+3.0*shade-0.5;bn=bb+db[None,:]+14*shade+3.0*np.exp(-((v-0.92)/0.1)**2)*(-0.4)
    out=L.copy();w=Au
    out[...,0]=L[...,0]*(1-w)+Ln*w;out[...,1]=L[...,1]*(1-w)+an*w;out[...,2]=L[...,2]*(1-w)+bn*w
    return unlab(out),bnds,off,line
def shade_lower(img,c,n,Alw,info,mw,ytop,ybot):
    H,W=img.shape[:2];L=lab(img);rs=np.random.RandomState(seed(c,n)+5)
    yy=np.arange(H,dtype=np.float32)[:,None];xs=np.arange(W,dtype=np.float32)[None,:]
    v=np.clip((yy-ytop[None,:])/np.maximum(ybot[None,:]-ytop[None,:],1),0,1)
    Lb,ab,bb=BASE[c];Lb-=5;hx=np.clip(np.abs(xs-info['cx'])/((info['xr']-info['xl'])/2),0,1.1)
    # keep the production tooth separations (they are the coach's own), softened
    Ls=L[...,0];Lc=cv2.morphologyEx(Ls,cv2.MORPH_CLOSE,np.ones((5,3),np.uint8));Lc=np.minimum(Lc,np.percentile(Ls[Alw>0.6],75) if (Alw>0.6).any() else 80)
    mix=0.5*Ls+0.5*np.maximum(Ls,Lc*0.93)
    prof=0.94+0.06*np.sin(np.pi*np.clip(v*1.15,0,1))-0.16*np.clip((v-0.7)/0.3,0,1)
    Lm=np.minimum(mix,Lb+4)
    Lm=Lm*0.55+0.45*(Lb*prof)
    Lm=Lm*prof**0.5*(1-0.26*hx**2)
    shade=np.clip(1-Lm/Lb,0,0.5)
    out=L.copy();w=Alw
    out[...,0]=L[...,0]*(1-w)+Lm*w;out[...,1]=L[...,1]*(1-w)+(ab+2.5*shade)*w;out[...,2]=L[...,2]*(1-w)+(bb+12*shade)*w
    return unlab(out)

def open_frame(c,name,D,tongue_up=False,lr=0.40,taper_pow=0.8,dbg=False):
    f=frame(c,name);H,W=f.shape[:2];mw=man(c)['mouth_width']
    T,info,yb=geometry(f,c);rs=np.random.RandomState(seed(c,name))
    L=lab(f);xs=np.arange(W,dtype=np.float32);yy=np.arange(H,dtype=np.float32)[:,None]
    lo=TONE[c].get('alo',60)
    alt=np.clip((L[...,0]-lo)/8,0,1)*np.clip((15-L[...,1])/4,0,1)
    alt=alt*cv2.dilate(T,np.ones((5,5),np.uint8))
    up=(yy<yb[None,:]+0.5).astype(np.float32)
    Au=blur(alt*up,0.5);topc=col_edge(alt*up,yb-40,yb,info,W,np.min);topc=np.minimum(topc,yb-8)
    fu,bnds,off,line=shade_upper(f,c,name,T,info,yb,mw,Au,topc)
    # lower-teeth: warp
    hw=(info['xr']-info['xl'])/2*1.05
    tap=np.clip(1-((xs-info['cx'])/hw)**2,0,1)**taper_pow;d=D*tap
    ybx=yb[None,:].astype(np.float32);dx=d[None,:]
    t=np.clip((yy-(ybx+dx))/(lr*mw),0,1);g=0.5*(1+np.cos(np.pi*t))
    srcy=np.where(yy<=ybx,yy,np.where(yy<=ybx+dx,ybx,yy-dx*g)).astype(np.float32)
    mapx=np.tile(xs[None,:],(H,1))
    Wp=cv2.remap(fu,mapx,srcy,cv2.INTER_CUBIC,borderMode=cv2.BORDER_REPLICATE)
    Alw=cv2.remap((alt*(1-up)).astype(np.float32),mapx,srcy,cv2.INTER_LINEAR,borderMode=cv2.BORDER_REPLICATE)
    Alw=blur(Alw,0.5)
    ytop=yb+d;ybot=col_edge(Alw,(yb+d).astype(np.float32),(yb+d+40).astype(np.float32),info,W,np.max)
    ybot=np.maximum(ybot,ytop+10)
    Wl=shade_lower(Wp,c,name,Alw,info,mw,ytop,ybot)
    # cavity
    cxx=info['cx'];tx=np.clip((xs[None,:]-cxx)/hw,-1,1)
    gtop=ybx-3.0;gbot=ybx+dx+2.5
    gapm=((yy>=gtop)&(yy<=gbot)&(dx>0.9)).astype(np.float32);gapm=blur(gapm,1.0)
    ty=np.clip((yy-gtop)/np.maximum(gbot-gtop,1),0,1)
    Lc=7+14*ty**1.2;Lc=Lc*(1-0.45*np.abs(tx)**2.5)
    cav=np.stack([Lc,12+9*ty,5+5*ty],-1).astype(np.float32)
    # tongue
    tc_y=ybx+dx*(0.30 if tongue_up else 0.80);ry=np.maximum(dx*(0.55 if tongue_up else 0.78),3.0);rx=0.30*hw*(1.1 if tongue_up else 1.0)
    e=((xs[None,:]-cxx)/rx)**2+((yy-tc_y)/ry)**2
    tm=np.clip((1.12-e)/0.5,0,1);tm=blur(tm,1.3)*(dx>1.5)
    rim=np.clip(e,0,1)
    tL=44-14*rim**1.4+8*np.exp(-(((xs[None,:]-cxx-0.05*rx)/(0.5*rx))**2+((yy-(tc_y-0.25*ry))/(0.45*ry))**2))
    tL=tL*(0.55+0.45*np.clip(ty*1.6,0,1))   # darker where the upper teeth shade it
    groove=np.exp(-((xs[None,:]-cxx)/1.0)**2)*np.clip(1-np.abs(yy-tc_y)/(ry*0.9),0,1)
    tL=tL-5*groove
    nz=blur(rs.normal(0,1,(H,W)).astype(np.float32),0.8)*2.2
    tl=np.stack([tL+nz,25+4*np.clip(1-rim,0,1)+0*tL,14+2*np.clip(1-rim,0,1)+0*tL],-1)
    cav=cav*(1-0.9*tm[...,None])+tl*0.9*tm[...,None]
    cav[...,0]+=blur(rs.normal(0,1,(H,W)).astype(np.float32),0.7)*1.2
    cavb=unlab(cav)
    # remove hard dark leftovers (corner wedges) before painting: grade them
    base=Wl.astype(np.float32)*(1-gapm[...,None])+cavb.astype(np.float32)*gapm[...,None]
    base=np.clip(base,0,255).astype(np.uint8)
    # re-draw upper teeth over the cavity with scalloped lower edges
    # (upper teeth already in base via fu above yb; the cavity starts 3px above yb so redraw alpha-scalloped teeth)
    cut=(yb[None,:]+off[None,:]*0.0)
    notch=1.4*line[None,:]
    edge=yb[None,:]+0.6*off[None,:]-notch
    Aup=np.clip(Au*np.clip((edge-yy)/1.0+0.5,0,1),0,1)
    Aup=Aup*(dx>0.9)+Au*(dx<=0.9)   # near the corners keep as is
    Aup=blur(Aup,0.45)
    out=base.astype(np.float32)*(1-Aup[...,None])+fu.astype(np.float32)*Aup[...,None]
    out=np.clip(out,0,255).astype(np.uint8)
    out=warm_darks(out,c)
    E=blur(ell(c,f.shape,0.50,0.30).astype(np.float32),4)[...,None]
    res=np.clip(out.astype(np.float32)*E+Wp.astype(np.float32)*(1-E)*0+f.astype(np.float32)*(1-E),0,255).astype(np.uint8)
    return res
if __name__=='__main__':
    import sys
    c=sys.argv[1];rows=[]
    for n,D,tu in [('a',16,False),('a2',12,False),('l',9,True)]:
        o=open_frame(c,n,D,tu);f=frame(c,n)
        rows.append(cv2.resize(np.hstack([f[80:250,90:380],o[80:250,90:380]]),None,fx=2.5,fy=2.5,interpolation=cv2.INTER_CUBIC))
    cv2.imwrite(f'../work/r-{c}.png',np.vstack(rows))
