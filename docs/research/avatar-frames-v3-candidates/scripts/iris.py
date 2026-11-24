from eyes_meas import *
def iris_circle(img,pt,iod,hint=None):
    r0=int(0.075*iod);R=int(0.4*iod)
    x,y=int(pt[0]),int(pt[1]);x0,y0=max(0,x-R),max(0,y-R)
    win=img[y0:y+R,x0:x+R];g=cv2.cvtColor(win,cv2.COLOR_BGR2GRAY);g=cv2.GaussianBlur(g,(0,0),1.5)
    cs=cv2.HoughCircles(g,cv2.HOUGH_GRADIENT,dp=1,minDist=10,param1=60,param2=12,minRadius=max(5,int(0.05*iod)),maxRadius=int(0.1*iod))
    if cs is None: return None
    # choose the circle with the darkest interior near the landmark
    best=None;bs=1e9
    for cx,cy,r in cs[0]:
        m=np.zeros(g.shape,np.uint8);cv2.circle(m,(int(cx),int(cy)),int(r*0.8),1,-1)
        s=g[m>0].mean()+0.6*np.hypot(cx+x0-pt[0],cy+y0-pt[1])
        if s<bs: bs=s;best=(cx+x0,cy+y0,r)
    return best
if __name__=='__main__':
    fdir=sys.argv[1]
    for c in ['ava','ethan','sofia','diego']:
        m,hero=setup(c,fdir);mst=verify.analyse(hero);f=mst['face'];iod=float(np.hypot(f[6]-f[4],f[7]-f[5]))
        gi=comp(hero,m,fdir,c,'gaze');g=verify.analyse(gi)['face']
        x,y,w,h=m['frames']['gaze']['rect'];tiles=[]
        for im,face,tag in [(hero,f,'rest'),(gi,g,'gaze')]:
            v=im.copy()
            for ei in ((4,5),(6,7)):
                ci=iris_circle(im,(face[ei[0]],face[ei[1]]),iod)
                if ci: cv2.circle(v,(int(ci[0]),int(ci[1])),int(ci[2]),(0,255,0),1)
                cv2.circle(v,(int(face[ei[0]]),int(face[ei[1]])),2,(0,0,255),-1)
            tiles.append(v[y:y+h,x:x+w])
        cv2.imwrite(f'../work/iris-{c}.png',cv2.resize(np.vstack(tiles),None,fx=1.0,fy=1.0))
