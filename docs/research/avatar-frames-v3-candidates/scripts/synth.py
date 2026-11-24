from render import *
def medf(a,k):
    from numpy.lib.stride_tricks import sliding_window_view
    p=k//2;ap=np.pad(a,(p,p),mode='edge');return np.median(sliding_window_view(ap,k),axis=1)
def maxf(a,k):
    from numpy.lib.stride_tricks import sliding_window_view
    p=k//2;ap=np.pad(a,(p,p),mode='edge');return sliding_window_view(ap,k).max(axis=1)
def minf(a,k):
    from numpy.lib.stride_tricks import sliding_window_view
    p=k//2;ap=np.pad(a,(p,p),mode='edge');return sliding_window_view(ap,k).min(axis=1)
def open_geom(f,c):
    H,W=f.shape[:2];L=lab(f);mw=man(c)['mouth_width']
    T,info,yb=geometry(f,c)
    lo=TONE[c].get('alo',60)
    alt=(np.clip((L[...,0]-lo)/8,0,1)*np.clip((15-L[...,1])/4,0,1)*cv2.dilate(T,np.ones((5,5),np.uint8)))
    near=cv2.dilate((alt>0.4).astype(np.uint8),cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(15,15)))
    dark=((L[...,0]<34)&(near>0)&(L[...,1]<22)).astype(np.uint8)
    sh=((L[...,0]>42)&(L[...,1]<12.5)&(near>0)).astype(np.uint8)
    M=((alt>0.3)|(dark>0)|(sh>0)).astype(np.uint8)
    M=cv2.morphologyEx(M,cv2.MORPH_OPEN,np.ones((2,2),np.uint8))
    n,lb,st,_=cv2.connectedComponentsWithStats(cv2.morphologyEx(M,cv2.MORPH_CLOSE,np.ones((9,9),np.uint8)))
    k=1+int(np.argmax(st[1:,4]));M=M*(lb==k)
    xs_=np.nonzero(M.any(0))[0];xl,xr=xs_.min(),xs_.max()
    ytop=np.full(W,np.nan,np.float32);ybot=np.full(W,np.nan,np.float32)
    for x in range(xl,xr+1):
        ys=np.nonzero(M[:,x])[0]
        if len(ys): ytop[x]=ys.min();ybot[x]=ys.max()
    ok=~np.isnan(ytop);xi=np.arange(W)
    ytop=np.interp(xi,xi[ok],ytop[ok]);ybot=np.interp(xi,xi[ok],ybot[ok])
    ytop=blur(minf(ytop,17).reshape(-1,1),4.0).ravel()-0.3
    ybot=blur(maxf(ybot,9).reshape(-1,1),1.8).ravel()+0.5
    return dict(T=T,info=info,yb=yb,ytop=ytop,ybot=ybot,xl=float(xl),xr=float(xr),alt=alt,M=M)
if __name__=='__main__':
    rows=[]
    for c in ['ava','ethan','sofia','diego']:
        r=[]
        for n in ['a','l']:
            f=frame(c,n);g=open_geom(f,c);v=f.copy()
            for x in range(int(g['xl']),int(g['xr'])):
                cv2.circle(v,(x,int(round(g['ytop'][x]))),0,(0,255,0),-1);cv2.circle(v,(x,int(round(g['ybot'][x]))),0,(0,255,255),-1);cv2.circle(v,(x,int(round(g['yb'][x]))),0,(255,0,255),-1)
            r.append(v[80:250,90:380])
        rows.append(np.hstack(r))
    cv2.imwrite('../work/ogeom.png',cv2.resize(np.vstack(rows),None,fx=1.6,fy=1.6,interpolation=cv2.INTER_NEAREST))
