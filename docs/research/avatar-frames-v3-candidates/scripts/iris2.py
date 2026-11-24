from eyes_meas import *
def lab_(img):
    l=cv2.cvtColor(img,cv2.COLOR_BGR2LAB).astype(np.float32);l[...,0]*=100/255.;l[...,1:]-=128;return l
def iris_mask(img,pt,iod,Lthr=40):
    H,W=img.shape[:2];R=int(0.30*iod);x,y=int(pt[0]),int(pt[1])
    x0,y0,x1,y1=max(0,x-R),max(0,y-R),min(W,x+R),min(H,y+R)
    L=lab_(img[y0:y1,x0:x1]);m=(L[...,0]<Lthr).astype(np.uint8)
    k=max(5,int(0.045*iod))|1
    m=cv2.morphologyEx(m,cv2.MORPH_OPEN,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(k,k)))
    n,lb,st,cen=cv2.connectedComponentsWithStats(m)
    best=None;bd=1e9
    for i in range(1,n):
        if st[i,4]<30: continue
        d=np.hypot(cen[i][0]+x0-pt[0],cen[i][1]+y0-pt[1])
        if d<bd: bd=d;best=i
    if best is None: return None
    c=(lb==best).astype(np.uint8)
    cnt,_=cv2.findContours(c,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE);f=np.zeros_like(c);cv2.drawContours(f,cnt,-1,1,-1)
    full=np.zeros(img.shape[:2],np.uint8);full[y0:y1,x0:x1]=f;return full
def iris_stats(img,mask):
    L=lab_(img);v=L[mask>0];Ls=v[:,0]
    keep=(Ls>np.percentile(Ls,15))&(Ls<np.percentile(Ls,85))   # not pupil, not highlight
    return v[keep].mean(0)
if __name__=='__main__':
    fdir=sys.argv[1]
    for c in ['ava','ethan','sofia','diego']:
        m,hero=setup(c,fdir);mst=verify.analyse(hero);f=mst['face'];iod=float(np.hypot(f[6]-f[4],f[7]-f[5]))
        gi=comp(hero,m,fdir,c,'gaze');g=verify.analyse(gi)['face']
        x,y,w,h=m['frames']['gaze']['rect'];tiles=[]
        for im,face,tag in [(hero,f,'rest'),(gi,g,'gaze')]:
            v=im.copy()
            for ei in ((4,5),(6,7)):
                mk=iris_mask(im,(face[ei[0]],face[ei[1]]),iod)
                if mk is not None:
                    cnt,_=cv2.findContours(mk,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE);cv2.drawContours(v,cnt,-1,(0,255,0),1)
                    print(c,tag,ei,mk.sum(),np.round(iris_stats(im,mk),1))
            tiles.append(v[y:y+h,x:x+w])
        cv2.imwrite(f'../work/iris-{c}.png',cv2.resize(np.vstack(tiles),None,fx=1.5,fy=1.5))
