from synth import *
REL_UP=[1.22,0.86,0.80,0.58]   # central -> premolar widths
REL_LO=[0.62,0.66,0.84,0.9]
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
    n=len(b)-1;dl=rs.normal(0,sigL,n);db=rs.normal(0,sigb,n);ln=rs.uniform(-2.2,1.5,n);rot=rs.uniform(-0.8,0.8,n)
    return u,idx,dl,db,ln,rot
def fld(idx,vals,fill=0):
    out=np.full(idx.shape,fill,np.float32);m=idx>=0;out[m]=vals[idx[m]];return out
def paint_open(c,name,D,tongue_up=False,lr=0.40,taper_pow=0.8,tongue_scale=1.0,show=False,UPH=0.17):
    f=frame(c,name);H,W=f.shape[:2];mw=man(c)['mouth_width'];g=open_geom(f,c)
    info=g['info'];yb=g['yb'].astype(np.float32)
    rs=np.random.RandomState(seed(c,name));xs=np.arange(W,dtype=np.float32);yy=np.arange(H,dtype=np.float32)[:,None]
    ytop=g['ytop'].copy();ybot=g['ybot'].copy()
    EXL,EXR=14,6;x0i,x1i=int(g['xl']),int(g['xr'])
    for x in range(x0i-EXL,x0i):
        s=((x0i-x)/EXL)**1.3;mid=(ytop[x0i]+ybot[x0i])/2;ytop[x]=ytop[x0i]+(mid-ytop[x0i])*s;ybot[x]=ybot[x0i]-(ybot[x0i]-mid)*s
    for x in range(x1i+1,x1i+EXR+1):
        s=((x-x1i)/EXR)**1.3;mid=(ytop[x1i]+ybot[x1i])/2;ytop[x]=ytop[x1i]+(mid-ytop[x1i])*s;ybot[x]=ybot[x1i]-(ybot[x1i]-mid)*s
    ytop=blur(ytop.reshape(-1,1),2.5).ravel()-1.0
    xl,xr=g['xl']-EXL,g['xr']+EXR;cx=info['cx'];hw=(xr-xl)/2*1.02
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
    endf=np.clip(np.minimum(xs-xl,xr-xs)/2.0,0,1)[None,:]
    Ao=Ao*endf;Ao=blur(Ao,0.5)
    # clean the dark lip-contact rim: re-grow lip colour 2 px into the opening edge so teeth do not sit in a black outline
    op=(Ao>0.3).astype(np.uint8);ring=cv2.dilate(op,np.ones((7,7),np.uint8))-cv2.erode(op,np.ones((3,3),np.uint8))
    Lw0=lab(Wp)[...,0];dk=((ring>0)&(Lw0<48)).astype(np.uint8)
    fm=np.clip(cv2.dilate(op,np.ones((3,3),np.uint8))+cv2.dilate(dk,np.ones((3,3),np.uint8)),0,1).astype(np.uint8)
    Wp=cv2.inpaint(Wp,fm*255,3,cv2.INPAINT_TELEA)
    # ----- layers
    Lb,ab,bb=BASE[c]
    tx=(xs[None,:]-cx)/hw;ax=np.abs(tx)
    span=(xr-xl)*0.90
    hU0=np.minimum(ybx-ytop[None,:],UPH*span);ctop=ytop[None,:]+hU0;cbot=ybx+dx;Hc=np.maximum(cbot-ctop,6)
    # ---- cavity
    gtop=ytop[None,:]+0.35*(ybx-ytop[None,:]);gbot=ybot2[None,:]
    ty=np.clip((yy-ctop)/Hc,0,1)     # 0 right under the upper edge, 1 above lower teeth
    Lc=5+13*ty**1.4+0*yy
    Lc=np.maximum(Lc*(1-0.55*np.clip(ax-0.35,0,1)**1.5),9)
    cav=np.stack([Lc,10+10*ty,4.5+5*ty],-1).astype(np.float32)
    cnr=np.clip((ax-0.74)/0.26,0,1)[...,None]**1.2*0.85
    cav=cav*(1-cnr)+np.array([30,21,11],np.float32)*cnr
    # tongue
    tcy=ctop+Hc*(0.42 if tongue_up else 0.62)
    ry=Hc*(0.36 if tongue_up else 0.50)*tongue_scale
    rx=0.46*hw*(1.1 if tongue_up else 1.0)
    e=((xs[None,:]-cx)/rx)**2+((yy-tcy)/ry)**2
    tm=blur(np.clip((1.1-e)/0.45,0,1),1.2)
    rim=np.clip(e,0,1.2)
    hl=np.exp(-(((xs[None,:]-cx-0.1*rx)/(0.55*rx))**2+((yy-(tcy-0.35*ry))/(0.40*ry))**2))
    tL=50-20*rim**1.2+11*hl
    tL=tL*(0.55+0.45*np.clip(((yy-ctop)/Hc)*1.1+0.2,0,1))
    groove=np.exp(-((xs[None,:]-cx)/1.1)**2)*np.clip(1-np.abs(yy-tcy)/(ry*0.85),0,1)
    tL=tL-6*groove
    nz=blur(rs.normal(0,1,(H,W)).astype(np.float32),0.7)*2.0
    ta=29+5*hl-5*rim;tb=17+2*hl-2.5*rim
    tl=np.stack([tL+nz,ta+0*tL,tb+0*tL],-1)
    cav=cav*(1-tm[...,None])+tl*tm[...,None]
    cav[...,0]+=blur(rs.normal(0,1,(H,W)).astype(np.float32),0.7)*1.1
    cavb=unlab(cav).astype(np.float32)
    # lip-side shadow: darken the inner few px under the upper lip / above lower lip
    out=Wp.astype(np.float32)*(1-Ao[...,None])+cavb*Ao[...,None]
    # dark-red lip-contact shadow along the inside of both lips
    sh_top=np.exp(-np.clip(yy-ytop[None,:],0,20)/2.2)*Ao*0.0
    sh_bot=np.exp(-np.clip(ybot2[None,:]-yy,0,20)/2.5)*Ao*0.22
    lipcol=unlab(np.stack([np.full((H,W),16,np.float32),np.full((H,W),16,np.float32),np.full((H,W),8,np.float32)],-1)).astype(np.float32)
    S=np.clip(sh_top+sh_bot,0,0.6)[...,None]
    out=out*(1-S)+lipcol*S
    # ---- upper teeth
    bU=layout(cx,span,REL_UP,rs);u,idx,dl,db,ln,rot=per_col_tooth(W,bU,rs,2.0,1.0)
    ln_c=fld(idx,ln);cu=np.abs(2*u-1);cu[idx<0]=1
    pointed=np.zeros(W,np.float32)
    n=len(bU)-1;mid=n//2
    for k in (mid-3,mid+2):
        if 0<=k<n: pointed+=((idx==k)*1.0)*(1-cu)*0.6
    hU=np.minimum(ybx-ytop[None,:],UPH*span)
    edge0=blur((ytop[None,:]+hU).reshape(-1,1) if False else (ytop+hU[0]).reshape(-1,1),14).ravel()[None,:]
    edge=edge0+ln_c[None,:]*0.8+pointed[None,:]-2.2*cu[None,:]**4
    edge=edge-1.4*np.exp(-((xs[None,:]*0+0)))*0
    Au=np.clip(edge-yy+0.5,0,1)*(idx>=0)[None,:]
    Au=blur(Au,0.5)*Ao*np.clip((yy-ytop[None,:])/1.8+0.3,0,1)*np.clip((span/2-np.abs(xs[None,:]-cx))/12+0.2,0,1)
    vv=np.clip((yy-ytop[None,:])/np.maximum(edge-ytop[None,:],1),0,1)
    dLf=fld(idx,dl)[None,:];dbf=fld(idx,db)[None,:];uu=u[None,:]
    prof=1-0.30*np.exp(-vv/0.14)-0.04*np.clip((vv-0.80)/0.2,0,1)+0.03*np.exp(-((vv-0.5)/0.25)**2)
    fall=1-0.30*np.clip(ax-0.25,0,1.2)**1.6
    conv=1-0.08*(2*uu-1)**2
    Lm=(Lb+dLf)*prof*fall*conv
    # interdental lines
    lines=np.zeros(W,np.float32)
    for bb_ in bU[1:-1]: lines+=np.exp(-((xs-bb_)/0.85)**2)
    Lm=Lm*(1-0.10*lines[None,:]*(1.0-0.6*vv))+2.6*np.exp(-(((uu-0.38)/0.22)**2))*np.exp(-((vv-0.45)/0.3)**2)
    # per-tooth tiny enamel striation/mottle
    mott=blur(rs.normal(0,1,(H,W)).astype(np.float32),1.6)*1.0+blur(rs.normal(0,1,(H,W)).astype(np.float32)[:, :],0.6)*0.5
    Lorig=lab(f)[...,0];Lcl=cv2.morphologyEx(Lorig,cv2.MORPH_CLOSE,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(7,7)))
    Lcl=np.minimum(blur(Lcl,0.7),Lb+8);hi=np.clip(Lorig-blur(Lorig,2.0),-4,4)
    Lm=0.7*Lm+0.3*np.maximum(Lcl*(prof/ prof.mean())**0.5*fall**0.6,0.85*Lm)+mott*0.6+0.25*hi
    sh=np.clip(1-Lm/Lb,0,0.5)
    tU=np.stack([Lm,ab+3*sh+0*Lm,bb+dbf+16*sh-3*np.exp(-((vv-0.95)/0.08)**2)],-1)
    # translucent incisal edge: mix a little cavity colour
    tr=np.clip((vv-0.78)/0.22,0,1)[...,None]*0.22
    tUb=unlab(tU).astype(np.float32);tUb=tUb*(1-tr)+cavb*tr
    out=out*(1-Au[...,None])+tUb*Au[...,None]
    # ---- lower teeth
    spanL=span*0.88
    bL=layout(cx,spanL,REL_LO,rs,0.1);uL,idxL,dlL,dbL,lnL,_=per_col_tooth(W,bL,rs,1.8,0.9)
    cuL=np.abs(2*uL-1);cuL[idxL<0]=1
    topL=ybx+dx+0.0+fld(idxL,lnL)[None,:]*0.8+3.0*cuL[None,:]**3
    # lower teeth arch is lower than the bite line in the corners; keep it under the cavity
    AL=np.clip(yy-topL+0.5,0,1)*(idxL>=0)[None,:]
    AL=blur(AL,0.5)*Ao*np.clip((spanL/2-np.abs(xs[None,:]-cx))/12+0.2,0,1)
    vL=np.clip((yy-topL)/np.maximum(ybot2[None,:]-topL,1),0,1)
    fallL=1-0.34*np.clip(ax-0.2,0,1.2)**1.5
    profL=0.97+0.06*np.sin(np.pi*np.clip(vL*1.3,0,1))-0.13*np.clip((vL-0.55)/0.45,0,1)
    LmL=(Lb+4+fld(idxL,dlL)[None,:])*profL*fallL*(1-0.10*(2*uL[None,:]-1)**2)
    linesL=np.zeros(W,np.float32)
    for bb_ in bL[1:-1]: linesL+=np.exp(-((xs-bb_)/0.9)**2)
    LmL=LmL*(1-0.08*linesL[None,:])+3.0*np.exp(-((yy-topL)/1.8)**2)*(idxL>=0)[None,:]
    LoW=lab(Wp)[...,0];LclW=cv2.morphologyEx(LoW,cv2.MORPH_CLOSE,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(3,5)))
    LclW=np.minimum(blur(LclW,0.6),Lb-1)
    LmL=0.5*LmL+0.5*np.maximum(LclW*(profL**0.7)*fallL**0.6,0.8*LmL)+blur(rs.normal(0,1,(H,W)).astype(np.float32),1.1)*1.2
    shL=np.clip(1-LmL/Lb,0,0.55)
    tL_=np.stack([LmL,ab+0.8+2.5*shL+0*LmL,bb+0.5+fld(idxL,dbL)[None,:]+6*shL+0*LmL],-1)
    # top rim of lower teeth: slight darkening where upper teeth shade them
    tLb=unlab(tL_).astype(np.float32)
    out=out*(1-AL[...,None])+tLb*AL[...,None]
    res=np.clip(out,0,255).astype(np.uint8)
    E=blur(ell(c,f.shape,0.55,0.34).astype(np.float32),4)[...,None]
    res=np.clip(res.astype(np.float32)*E+f.astype(np.float32)*(1-E),0,255).astype(np.uint8)
    return res,g
if __name__=='__main__':
    import sys
    c=sys.argv[1];rows=[]
    for n,D,tu in [('a',12,False),('a2',8,False),('l',1,True)]:
        o,g=paint_open(c,n,D,tu);f=frame(c,n)
        rows.append(cv2.resize(np.hstack([f[80:250,90:380],o[80:250,90:380]]),None,fx=2.5,fy=2.5,interpolation=cv2.INTER_CUBIC))
    cv2.imwrite(f'../work/p-{c}.png',np.vstack(rows))
