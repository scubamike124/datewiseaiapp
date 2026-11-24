from eyefix import *
def refine_center(img,pt,iod,rad=0.14):
    H,W=img.shape[:2];L=lab_(img);R=int(rad*iod)
    x0,y0=max(0,int(pt[0])-R),max(0,int(pt[1])-R);sub=L[y0:int(pt[1])+R,x0:int(pt[0])+R]
    yy,xx=np.mgrid[0:sub.shape[0],0:sub.shape[1]].astype(np.float32)
    ch=np.hypot(sub[...,1],sub[...,2])
    w=((sub[...,0]>7)&(sub[...,0]<36)&(ch>3)).astype(np.float32)
    w=cv2.GaussianBlur(w,(0,0),2.0)
    # largest blurred mass = iris
    k=np.unravel_index(np.argmax(w),w.shape);cy,cx=k
    for _ in range(4):
        m=((yy-cy)**2+(xx-cx)**2<(0.07*iod)**2)*w
        if m.sum()<1e-3: break
        cy=(m*yy).sum()/m.sum();cx=(m*xx).sum()/m.sum()
    return (cx+x0,cy+y0)
def disc_stats(img,c_,iod,rr=0.058):
    H,W=img.shape[:2];L=lab_(img);yy,xx=np.mgrid[0:H,0:W].astype(np.float32)
    d=np.hypot(xx-c_[0],yy-c_[1]);m=d<rr*iod
    v=L[m];ch=np.hypot(v[:,1],v[:,2]);ok=(v[:,0]>6)&(v[:,0]<45)&(ch>2.5)
    if ok.sum()<20: return None,m
    v=v[ok];lo,hi=np.percentile(v[:,0],[20,85]);v=v[(v[:,0]>=lo)&(v[:,0]<=hi)]
    return v.mean(0),m
if __name__=='__main__':
    fdir=sys.argv[1]
    for c in ['ava','ethan','sofia','diego']:
        m,hero=setup(c,fdir);mst=verify.analyse(hero);f=mst['face'];iod=float(np.hypot(f[6]-f[4],f[7]-f[5]))
        gi=comp(hero,m,fdir,c,'gaze');g=verify.analyse(gi)['face'];x,y,w,h=m['frames']['gaze']['rect'];tiles=[]
        print(c,'iod',round(iod))
        for im,face,tag in [(hero,f,'rest'),(gi,g,'gaze')]:
            v=im.copy()
            for ei in ((4,5),(6,7)):
                cc=refine_center(im,(face[ei[0]],face[ei[1]]),iod);st,mk=disc_stats(im,cc,iod)
                cv2.circle(v,(int(cc[0]),int(cc[1])),int(0.058*iod),(0,255,0),1)
                print(' ',tag,ei,None if st is None else np.round(st,1))
            tiles.append(v[y:y+h,x:x+w])
        cv2.imwrite(f'../work/iris-{c}.png',cv2.resize(np.vstack(tiles),None,fx=1.8,fy=1.8))
