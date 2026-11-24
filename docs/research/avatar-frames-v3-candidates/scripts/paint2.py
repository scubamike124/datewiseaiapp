from synth import *
REL_UP=[1.12,0.80,0.72,0.55]   # central -> premolar widths
REL_LO=[0.72,0.76,0.86,0.9]
def layout(xc,span,rel,rs,jit=0.16):
    """boundaries for a symmetric-ish arch centred at xc, total width span"""
    ws=[]
    for side in (-1,1): ws.append([r*(1+rs.uniform(-jit,jit)) for r in rel])
    # asymmetry: shift centre a bit
    tot=sum(ws[0])+sum(ws[1]);k=span/tot
    xl=xc-sum(ws[0])*k;b=[xl]
    seq=list(reversed(ws[0]))+ws[1]
    for w in seq: b.append(b[-1]+w*k)
    return b
def per_col_tooth(W,b,rs,sigL=1.8,sigb=0.9):
    xs=np.arange(W,dtype=np.float32);u=np.full(W,-1,np.float32);idx=np.full(W,-1,np.int32)
    for i in range(len(b)-1):
        m=(xs>=b[i])&(xs<b[i+1]);u[m]=(xs[m]-b[i])/(b[i+1]-b[i]);idx[m]=i
    n=len(b)-1;dl=rs.normal(0,sigL,n);db=rs.normal(0,sigb,n);ln=rs.uniform(-1.8,1.2,n);rot=rs.uniform(-0.8,0.8,n)
    return u,idx,dl,db,ln,rot
def fld(idx,vals,fill=0):
    out=np.full(idx.shape,fill,np.float32);m=idx>=0;out[m]=vals[idx[m]];return out
def paint_open2(c,name,D,tongue_up=False,lr=0.40,taper_pow=0.8,tongue_scale=1.0,show=False):
    f=frame(c,name);H,W=f.shape[:2];mw=man(c)['mouth_width'];g=open_geom(f,c)
    info=g['info'];yb=g['yb'].astype(np.float32);ytop=g['ytop']-1.0;ybot=g['ybot']
    rs=np.random.RandomState(seed(c,name));xs=np.arange(W,dtype=np.float32);yy=np.arange(H,dtype=np.float32)[:,None]
    xl,xr=g['xl'],g['xr'];cx=info['cx'];hw=(xr-xl)/2*1.02
    tap=np.clip(1-((xs-cx)/hw)**2,0,1)**taper_pow;d=D*tap
    ybx=yb[None,:];dx=d[None,:]
    t=np.clip((yy-(ybx+dx))/(lr*mw),0,1);gg=0.5*(1+np.cos(np.pi*t))
    srcy=np.where(yy<=ybx,yy,np.where(yy<=ybx+dx,ybx,yy-dx*gg)).astype(np.float32)
    mapx=np.tile(xs[None,:],(H,1))
    Wp=cv2.remap(f,mapx,srcy,cv2.INTER_CUBIC,borderMode=cv2.BORDER_REPLICATE)
    # warped bottom of the opening: find y' with srcy(y')=ybot
    ybot2=ybot.copy()
    for x in range(int(xl),int(xr)+1):
        col=srcy[:,x];ybot2[x]=np.interp(ybot[x],col,np.arange(H)) if np.all(np.diff(col)>=0) else ybot[x]+d[x]
    # smooth/ensure at least covers lower region
    ybot2=blur(np.maximum(ybot2,ybot).reshape(-1,1),1.5).ravel()
    xa=np.arange(W)
    inx=((xs>=xl)&(xs<=xr)).astype(np.float32)
    # vertical alpha
    Ao=np.clip(np.minimum(yy-ytop[None,:],ybot2[None,:]-yy)+0.6,0,1)*inx[None,:]
    # taper the ends horizontally so the opening closes smoothly
    endf=np.clip(np.minimum(xs-xl,xr-xs)/4.0,0,1)[None,:]
    Ao=Ao*endf;Ao=blur(Ao,0.5)
    # ----- layers
    Lb,ab,bb=BASE[c]
    tx=(xs[None,:]-cx)/hw;ax=np.abs(tx)
    span=(xr-xl)*0.90
    # ---- cavity
    gtop=ytop[None,:]+0.35*(ybx-ytop[None,:]);gbot=ybot2[None,:]
    ty=np.clip((yy-(ybx-4))/np.maximum(dx+8,1),0,1)     # 0 right under the upper edge, 1 above lower teeth
    Lc=5+13*ty**1.4+0*yy
    Lc=Lc*(1-0.55*np.clip(ax-0.35,0,1)**1.5)
    cav=np.stack([Lc,10+10*ty,4.5+5*ty],-1).astype(np.float32)
    # tongue
    tcy=ybx+dx*(0.35 if tongue_up else 0.62)+ (0 if tongue_up else 2.0)
    ry=np.maximum(dx*(0.70 if tongue_up else 0.85),5.5)*tongue_scale
    rx=0.36*hw*(1.1 if tongue_up else 1.0)
    e=((xs[None,:]-cx)/rx)**2+((yy-tcy)/ry)**2
    tm=blur(np.clip((1.1-e)/0.45,0,1),1.2)
    rim=np.clip(e,0,1.2)
    hl=np.exp(-(((xs[None,:]-cx-0.1*rx)/(0.55*rx))**2+((yy-(tcy-0.35*ry))/(0.40*ry))**2))
    tL=46-16*rim**1.3+9*hl
    tL=tL*(0.50+0.50*np.clip(((yy-ybx)/np.maximum(dx,1))*1.2+0.45,0,1))
    groove=np.exp(-((xs[None,:]-cx)/1.1)**2)*np.clip(1-np.abs(yy-tcy)/(ry*0.85),0,1)
    tL=tL-6*groove
    nz=blur(rs.normal(0,1,(H,W)).astype(np.float32),0.7)*2.0
    ta=26+5*hl-3*rim;tb=15+2*hl-1.5*rim
    tl=np.stack([tL+nz,ta+0*tL,tb+0*tL],-1)
    cav=cav*(1-tm[...,None])+tl*tm[...,None]
    cav[...,0]+=blur(rs.normal(0,1,(H,W)).astype(np.float32),0.7)*1.1
    cavb=unlab(cav).astype(np.float32)
    # cavity extra shadow
    # lip-side shadow: darken the inner few px under the upper lip / above lower lip
    out=Wp.astype(np.float32)*(1-Ao[...,None])+cavb*Ao[...,None]
    # dark-red lip-contact shadow along the inside of both lips
    sh_top=np.exp(-np.clip(yy-ytop[None,:],0,20)/2.2)*Ao*0.0
    sh_bot=np.exp(-np.clip(ybot2[None,:]-yy,0,20)/2.5)*Ao*0.40
    lipcol=unlab(np.stack([np.full((H,W),16,np.float32),np.full((H,W),16,np.float32),np.full((H,W),8,np.float32)],-1)).astype(np.float32)
    S=np.clip(sh_top+sh_bot,0,0.6)[...,None]
    out=out*(1-S)+lipcol*S
    # ---- photographic teeth: the coach's own (production) teeth, cleaned, split into individual teeth
    Lf=lab(f);Lw=lab(Wp);alt=g['alt']
    def teeth_fill(Lab_,alpha,Lcap,lo=0.0):
        """bleed interior tooth colour outward so edge pixels carry tooth colour, not dark-gap grey"""
        core=(alpha>0.85).astype(np.uint8);core=cv2.erode(core,np.ones((3,3),np.uint8)) if core.sum()>200 else core
        res=Lab_.copy()
        for ch in range(3):
            v=Lab_[...,ch].copy();m=core>0
            vv=np.where(m,v,-1e3 if ch==0 else -1e3).astype(np.float32)
            # nearest-valid fill by iterated dilation of masked average
            num=np.where(m,v,0).astype(np.float32);den=m.astype(np.float32)
            for _ in range(3):
                num=cv2.GaussianBlur(num,(0,0),1.2);den=cv2.GaussianBlur(den,(0,0),1.2)
            fill=num/np.maximum(den,1e-3)
            w=np.clip(1-alpha*1.0,0,1)*(1-core)
            res[...,ch]=np.where(m,v,fill)
        return res
    up_a=np.clip(alt*(yy<ybx+0.5),0,1);up_a=cv2.morphologyEx(up_a,cv2.MORPH_CLOSE,np.ones((5,5),np.uint8))
    # upper alpha: real teeth pixels (closed), top at the lip, scalloped bottom edge
    notchU=np.zeros(W,np.float32)
    rsU=np.random.RandomState(seed(c,name)+11)
    bU=layout(cx,span,REL_UP,rsU,0.16);uU,idxU,dlU,dbU,lnU,_=per_col_tooth(W,bU,rsU)
    cuU=np.abs(2*uU-1);cuU[idxU<0]=1
    edgeU=ybx+0.7*fld(idxU,lnU)[None,:]-1.8*cuU[None,:]**4
    AU=np.clip(up_a*np.clip(edgeU-yy+0.5,0,1),0,1);AU=blur(AU,0.45)
    AU=AU*Ao*np.clip((yy-ytop[None,:])/1.6+0.35,0,1)
    LfU=teeth_fill(Lf,up_a,0)
    Lcl=cv2.morphologyEx(LfU[...,0],cv2.MORPH_CLOSE,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(9,9)))
    Lcl=np.minimum(blur(Lcl,0.6),Lb+9)
    vv=np.clip((yy-ytop[None,:])/np.maximum(edgeU-ytop[None,:],1),0,1)
    profU=1-0.20*np.exp(-vv/0.15)-0.04*np.clip((vv-0.8)/0.2,0,1)
    fallU=1-0.26*np.clip(ax-0.25,0,1.2)**1.6
    dLf=fld(idxU,dlU)[None,:];dbf=fld(idxU,dbU)[None,:]
    linesU=np.zeros(W,np.float32)
    for bb_ in bU[1:-1]: linesU+=np.exp(-((xs-bb_)/0.85)**2)*rsU.uniform(0.6,1.1)
    LU=(0.78*Lcl+0.22*(Lb+dLf))*profU*fallU+1.3*dLf
    LU=LU*(1-0.10*linesU[None,:]*(0.45+0.8*vv))
    LU=LU+blur(rs.normal(0,1,(H,W)).astype(np.float32),0.9)*0.9
    shU=np.clip(1-LU/Lb,0,0.5)
    aU=0.45*LfU[...,1]+0.55*(ab+3*shU);bU_=0.4*LfU[...,2]+0.6*(bb+dbf+16*shU)
    tUb=unlab(np.stack([LU,aU,bU_],-1)).astype(np.float32)
    trU=np.clip((vv-0.88)/0.12,0,1)[...,None]*0.14
    tUb=tUb*(1-trU)+cavb*trU
    # lower teeth (warped production lower row)
    lo_a=np.clip(cv2.remap(alt*(yy>=ybx+0.5),mapx,srcy,cv2.INTER_LINEAR,borderMode=cv2.BORDER_REPLICATE),0,1)
    lo_a=cv2.morphologyEx(lo_a,cv2.MORPH_CLOSE,np.ones((3,3),np.uint8))
    AL=np.clip((lo_a-0.25)/0.6,0,1);AL=blur(AL,0.5)*Ao
    LfL=teeth_fill(Lw,lo_a,0)
    LclL=cv2.morphologyEx(LfL[...,0],cv2.MORPH_CLOSE,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(3,5)))
    LclL=np.minimum(blur(LclL,0.6),Lb)
    topL=ybx+dx
    ybl=ybot2[None,:]
    vL=np.clip((yy-topL)/np.maximum(ybl-topL,1),0,1)
    profL=0.95+0.05*np.sin(np.pi*np.clip(vL*1.3,0,1))-0.16*np.clip((vL-0.6)/0.4,0,1)
    fallL=1-0.30*np.clip(ax-0.2,0,1.2)**1.5
    LL=(0.80*LclL+0.20*(Lb-4))*profL*fallL
    # soften remaining dark gaps between lower teeth
    LL=np.maximum(LL,0.86*blur(LL,2.5))
    LL=LL+blur(rs.normal(0,1,(H,W)).astype(np.float32),0.9)*0.9
    shL=np.clip(1-LL/Lb,0,0.5)
    aL=0.45*LfL[...,1]+0.55*(ab+0.5+3*shL);bL_=0.4*LfL[...,2]+0.6*(bb+0.5+12*shL)
    tLb=unlab(np.stack([LL,aL,bL_],-1)).astype(np.float32)
    out=out*(1-AL[...,None])+tLb*AL[...,None]
    out=out*(1-AU[...,None])+tUb*AU[...,None]
    res=np.clip(out,0,255).astype(np.uint8)
    E=blur(ell(c,f.shape,0.55,0.34).astype(np.float32),4)[...,None]
    res=np.clip(res.astype(np.float32)*E+f.astype(np.float32)*(1-E),0,255).astype(np.uint8)
    return res,g
if False:
    import sys
    c=sys.argv[1];rows=[]
    for n,D,tu in [('a',22,False),('a2',16,False),('l',11,True)]:
        o,g=paint_open(c,n,D,tu);f=frame(c,n)
        rows.append(cv2.resize(np.hstack([f[80:250,90:380],o[80:250,90:380]]),None,fx=2.5,fy=2.5,interpolation=cv2.INTER_CUBIC))
    cv2.imwrite(f'../work/p-{c}.png',np.vstack(rows))
