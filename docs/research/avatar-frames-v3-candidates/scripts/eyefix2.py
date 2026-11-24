from eyefix import *
# approximate iris centres in patch coords (read off 2x grids), radius
IRIS={'ava':dict(rest=[(127,115),(375,116)],gaze=[(132,94),(385,96)],r=14),
      'ethan':dict(rest=[(122,104),(345,106)],gaze=[(128,91),(360,93)],r=12),
      'sofia':dict(rest=[(131,111),(369,111)],gaze=[(135,98),(377,90)],r=14),
      'diego':dict(rest=[(127,106),(345,105)],gaze=[(135,91),(357,92)],r=13)}
def refine(img,cx,cy,r,rect):
    x,y,w,h=rect;g=cv2.cvtColor(img[y:y+h,x:x+w],cv2.COLOR_BGR2GRAY);g=cv2.GaussianBlur(g,(0,0),1.2)
    best=(cx,cy);bs=1e9
    for dx in range(-6,7):
        for dy in range(-6,7):
            m=np.zeros(g.shape,np.uint8);cv2.circle(m,(int(cx+dx),int(cy+dy)),int(r*0.85),1,-1)
            ring=np.zeros(g.shape,np.uint8);cv2.circle(ring,(int(cx+dx),int(cy+dy)),int(r*1.35),1,-1);ring=ring-m
            ring=ring.astype(bool);m=m.astype(bool)
            s=g[m].mean()-0.5*g[ring].mean()+0.4*np.hypot(dx,dy)  # dark disc on lighter surround, prefer near guess
            if s<bs: bs=s;best=(cx+dx,cy+dy)
    return best
def stats(img,pt,r,rect):
    x,y,w,h=rect;L=lab_(img[y:y+h,x:x+w]);yy,xx=np.mgrid[0:h,0:w].astype(np.float32)
    d=np.hypot(xx-pt[0],yy-pt[1]);m=d<r*0.95
    v=L[m];ch=np.hypot(v[:,1],v[:,2]);ok=(v[:,0]>7)&(v[:,0]<42)&(ch>2)
    v=v[ok];lo,hi=np.percentile(v[:,0],[20,85]);v=v[(v[:,0]>=lo)&(v[:,0]<=hi)];return v.mean(0)
def correct(img,pt,r,rect,delta,damp=1.0):
    x,y,w,h=rect;sub=img[y:y+h,x:x+w];L=lab_(sub);yy,xx=np.mgrid[0:h,0:w].astype(np.float32)
    d=np.hypot(xx-pt[0],yy-pt[1]);disc=np.clip((r*1.1-d)/2.0,0,1)
    ch=np.hypot(L[...,1],L[...,2])
    cls=np.clip((L[...,0]-5)/3,0,1)*np.clip((46-L[...,0])/6,0,1)*np.clip((ch-0.6)/1.5,0,1)
    w_=cv2.GaussianBlur(disc*cls,(0,0),0.7)
    for k in range(3): L[...,k]+=w_*delta[k]*damp
    return unlab_(L)
def run(c,fdir,out,dbg=True):
    m,hero=setup(c,fdir);rect=m['frames']['gaze']['rect'];I=IRIS[c];r=I['r']
    patch=cv2.imread(f'{fdir}/{c}/gaze.jpg');res={}
    R=hero[rect[1]:rect[1]+rect[3],rect[0]:rect[0]+rect[2]]
    # per-eye stats rest (portrait) & gaze
    cr=[refine(hero,*p,r,rect) for p in I['rest']];cg=[refine(np.where(True,hero,hero),*p,r,rect) for p in I['gaze']]
    full=hero.copy();full[rect[1]:rect[1]+rect[3],rect[0]:rect[0]+rect[2]]=patch
    cg=[refine(full,*p,r,rect) for p in I['gaze']]
    t=[stats(hero,p,r,rect) for p in cr];g0=[stats(full,p,r,rect) for p in cg]
    new=patch.copy()
    for it in range(3):
        cur=_paste(hero,new,rect)
        for i in range(2):
            st=stats(cur,cg[i],r,rect);delta=t[i]-st
            delta=np.array([np.clip(delta[0],-5,5),np.clip(delta[1],-4,4),np.clip(delta[2],-4,4)])
            new=correct(new,cg[i],r,(0,0,rect[2],rect[3]),delta,0.9)
    g1=[stats(np.pad(new,0) if False else _paste(hero,new,rect),p,r,rect) for p in cg]
    os.makedirs(f'{out}/{c}',exist_ok=True)
    cv2.imwrite(f'{out}/{c}/gaze.jpg',new,[cv2.IMWRITE_JPEG_QUALITY,92])
    return dict(rest=t,gaze_before=g0,gaze_after=g1,cr=cr,cg=cg)
def _paste(hero,patch,rect):
    im=hero.copy();x,y,w,h=rect;im[y:y+h,x:x+w]=patch;return im
if __name__=='__main__':
    fdir='/home/user/datewiseaiapp/assets/avatar';out=sys.argv[1]
    for c in ['ava','ethan','sofia','diego']:
        r=run(c,fdir,out)
        print(c,'centres rest',[tuple(map(int,p)) for p in r['cr']],'gaze',[tuple(map(int,p)) for p in r['cg']])
        for i,n in enumerate(['L','R']):
            print('  eye',n,'portrait',np.round(r['rest'][i],1),'gaze before',np.round(r['gaze_before'][i],1),'after',np.round(r['gaze_after'][i],1))
