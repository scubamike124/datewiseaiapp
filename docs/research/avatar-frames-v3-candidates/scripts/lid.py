from eyes_meas import *
def labL(img): 
    l=cv2.cvtColor(img,cv2.COLOR_BGR2LAB).astype(np.float32);return l[...,0]*100/255.
def eye_boxes(c,fdir):
    m,hero=setup(c,fdir);f=verify.analyse(hero)['face'];x,y,w,h=m['frames']['blink_half']['rect']
    return m,hero,[(f[4]-x,f[5]-y),(f[6]-x,f[7]-y)],f
def smooth(a,s): return cv2.GaussianBlur(a.reshape(-1,1).astype(np.float32),(0,0),s).ravel()
def half_blink(c,fdir,t=0.5,halfw=None,eyes=(0,1),edge=0.35,base='rest'):
    m,hero,pts,f=eye_boxes(c,fdir);x,y,w,h=m['frames']['blink_half']['rect']
    iod=float(np.hypot(f[6]-f[4],f[7]-f[5]));hw=int(0.27*iod) if halfw is None else halfw
    R=hero[y:y+h,x:x+w].copy();C=cv2.imread(f'{fdir}/{c}/blink_closed.jpg');LR=labL(R);LC=labL(C)
    out=R.copy().astype(np.float32);dbg={}
    yy,xx=np.mgrid[0:h,0:w].astype(np.float32)
    mapy=yy.copy();alpha=np.zeros((h,w),np.float32);edgeline=np.zeros((h,w),np.float32)
    for k,(ex,ey) in enumerate(pts):
        if k not in eyes: continue
        xs=np.arange(max(0,int(ex-hw)),min(w,int(ex+hw)))
        yu=np.zeros(len(xs));yc=np.zeros(len(xs))
        for i,xc in enumerate(xs):
            a=int(ey-0.20*iod);b=int(ey+0.04*iod);col=smooth(LR[a:b,xc],1.0);yu[i]=a+np.argmin(col)
            a2=int(ey-0.06*iod);b2=int(ey+0.14*iod);col2=smooth(LC[a2:b2,xc],1.0);yc[i]=a2+np.argmin(col2)
        from numpy.lib.stride_tricks import sliding_window_view
        def med(a,k=15):
            p=k//2;return np.median(sliding_window_view(np.pad(a,(p,p),mode='edge'),k),axis=1)
        yu=smooth(med(yu),4);yc=smooth(med(yc),4)
        mu=np.median(yu);yu=np.clip(yu,mu-0.05*iod,mu+0.05*iod);yu=smooth(yu,3)
        yc=np.clip(yc,mu-0.02*iod,mu+0.22*iod);yc=np.maximum(yc,yu+2)
        yh=yu+t*(np.maximum(yc,yu+4)-yu)
        ytop=yu-0.12*iod
        for i,xc in enumerate(xs):
            # dest rows ytop..yh come from closed frame rows ytop..yc (vertical compression)
            wgt=np.clip(1-((xc-ex)/hw)**6,0,1)  # fade to the rest at the window sides
            for yd in range(int(ytop[i]),int(yh[i])+1):
                sr=ytop[i]+(yd-ytop[i])*(max(yc[i],yh[i])-ytop[i])/max(yh[i]-ytop[i],1)
                mapy[yd,xc]=sr;alpha[yd,xc]=wgt
        dbg[k]=(xs,yu,yc,yh)
        for i,xc in enumerate(xs):
            wgt=np.clip(1-((xc-ex)/(hw*0.8))**4,0,1);edgeline[:,xc]+=wgt*np.exp(-((np.arange(h)-yh[i])/1.5)**2)
    # build the lid layer by remapping the closed frame, composite over rest with soft alpha
    lid=cv2.remap(C,xx.astype(np.float32),mapy.astype(np.float32),cv2.INTER_CUBIC,borderMode=cv2.BORDER_REPLICATE)
    a=cv2.GaussianBlur(alpha,(0,0),1.0)[...,None]
    B=R if base=='rest' else cv2.imread(f'{fdir}/{c}/blink_half.jpg')
    res=B.astype(np.float32)*(1-a)+lid.astype(np.float32)*a
    res=res*(1-edge*np.clip(edgeline,0,1)[...,None])
    return np.clip(res,0,255).astype(np.uint8),R,C,dbg
if __name__=='__main__':
    fdir='/home/user/datewiseaiapp/assets/avatar'
    for c,eyes,t in [('ava',(0,),0.5),('diego',(1,),0.62)]:
        o,R,C,dbg=half_blink(c,fdir,t=t,eyes=eyes,base='prod');P=cv2.imread(f'{fdir}/{c}/blink_half.jpg')
        cv2.imwrite(f'../work/hb-{c}.png',cv2.resize(np.vstack([np.hstack([R,P]),np.hstack([o,C])]),None,fx=1.4,fy=1.4,interpolation=cv2.INTER_CUBIC))
