from paint import *
def teeth_band(f,c,n):
    L=lab(f);mw=man(c)['mouth_width']
    al=np.clip((L[...,0]-58)/9,0,1)*np.clip((15-L[...,1])/4,0,1)*cv2.dilate((ell(c,f.shape,0.5,0.25,0.0)),np.ones((3,3),np.uint8))
    m=(al>0.5).astype(np.uint8);nn,lb,st,_=cv2.connectedComponentsWithStats(m);k=1+int(np.argmax(st[1:,4]));m=(lb==k)
    ys,xs=np.nonzero(m);return blur(al*m,0.6),xs.min(),xs.max(),ys.min(),ys.max(),m
def enhance(c,n,strength=1.0):
    f=frame(c,n);H,W=f.shape[:2];mw=man(c)['mouth_width'];rs=np.random.RandomState(seed(c,n))
    al,x0,x1,y0,y1,m=teeth_band(f,c,n);L=lab(f);xs=np.arange(W,dtype=np.float32);yy=np.arange(H,dtype=np.float32)[:,None]
    cx=(x0+x1)/2;span=(x1-x0)*0.98
    b=layout(cx,span,[1.15,0.9,0.8,0.62],rs,0.14)
    u,idx,dl,db,ln,rot=per_col_tooth(W,b,rs,2.4,0.9)
    # vertical coordinate per column from the mask
    top=np.full(W,np.nan,np.float32);bot=np.full(W,np.nan,np.float32)
    for x in range(x0,x1+1):
        ys=np.nonzero(m[:,x])[0]
        if len(ys): top[x]=ys.min();bot[x]=ys.max()
    ok=~np.isnan(top);xi=np.arange(W);top=np.interp(xi,xi[ok],top[ok]);bot=np.interp(xi,xi[ok],bot[ok])
    v=np.clip((yy-top[None,:])/np.maximum(bot[None,:]-top[None,:],2),0,1)
    ax=np.clip(np.abs(xs[None,:]-cx)/(span/2),0,1.1)
    Lorig=L[...,0];Lcl=np.minimum(cv2.morphologyEx(Lorig,cv2.MORPH_CLOSE,np.ones((3,5),np.uint8)),90)
    Lb=BASE[c][0]
    uu=np.clip(u,0,1)[None,:];conv=1-0.075*(2*uu-1)**2
    prof=1-0.10*np.exp(-v/0.2)-0.07*np.clip((v-0.7)/0.3,0,1)+0.025*np.exp(-((v-0.45)/0.25)**2)
    lines=np.zeros((H,W),np.float32)
    for bb_ in b[1:-1]:
        sl=rs.uniform(-2.0,2.0);amp=rs.uniform(0.5,1.0)
        lines+=np.exp(-((xs[None,:]-bb_-sl*(v-0.5))/1.25)**2)*amp
    lines=lines*np.clip(1.15-0.7*v,0.3,1)
    Lm=(0.5*np.minimum(Lcl,Lb+8)+0.5*(Lb+3+fld(idx,dl)[None,:]))*prof*conv*(1-0.22*np.clip(ax-0.3,0,1.2)**1.6)
    Lm=Lm*(1-0.04*strength*lines)+blur(rs.normal(0,1,(H,W)).astype(np.float32),0.9)*0.9
    sh=np.clip(1-Lm/Lb,0,0.4)
    a_=0.25*L[...,1]+0.75*(BASE[c][1]+2.5*sh);b_=0.25*L[...,2]+0.75*(BASE[c][2]+fld(idx,db)[None,:]+12*sh)
    out=L.copy();w=al;out[...,0]=Lorig*(1-w)+Lm*w;out[...,1]=L[...,1]*(1-w)+a_*w;out[...,2]=L[...,2]*(1-w)+b_*w
    return unlab(out)
if __name__=='__main__':
    c='sofia';rows=[]
    for n in ['i2','sh']:
        rows.append(np.hstack([frame(c,n)[90:230,100:400],enhance(c,n)[90:230,100:400]]))
    cv2.imwrite('../work/si.png',cv2.resize(np.vstack(rows),None,fx=2.6,fy=2.6,interpolation=cv2.INTER_CUBIC))
