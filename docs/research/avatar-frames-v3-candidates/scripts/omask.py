from render import *
def opening(f,c,thr_dark=34):
    H,W=f.shape[:2];L=lab(f);mw=man(c)['mouth_width']
    e=ell(c,f.shape,0.50,0.27,0.02)
    teeth=((L[...,0]>52)&(L[...,1]<14)).astype(np.uint8)
    dark=((L[...,0]<thr_dark)).astype(np.uint8)
    m=((teeth|dark)*e).astype(np.uint8)
    m=cv2.morphologyEx(m,cv2.MORPH_CLOSE,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(7,7)))
    n,lb,st,_=cv2.connectedComponentsWithStats(m)
    k=1+int(np.argmax(st[1:,4]));m=(lb==k).astype(np.uint8)
    # fill holes
    ff=m.copy();cv2.floodFill(ff,None,(0,0),2) if False else None
    cnt,_=cv2.findContours(m,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE);o=np.zeros_like(m);cv2.drawContours(o,cnt,-1,1,-1)
    return o
if __name__=='__main__':
    rows=[]
    for c in ['ava','ethan','sofia','diego']:
        r=[]
        for n in ['a','l']:
            f=frame(c,n);o=opening(f,c);v=f.copy();cnt,_=cv2.findContours(o,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE);cv2.drawContours(v,cnt,-1,(0,255,0),1)
            r.append(v[80:250,90:380])
        rows.append(np.hstack(r))
    cv2.imwrite('../work/omask.png',cv2.resize(np.vstack(rows),None,fx=1.6,fy=1.6,interpolation=cv2.INTER_NEAREST))
