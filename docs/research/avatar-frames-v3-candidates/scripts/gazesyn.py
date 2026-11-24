from eyefix2 import *
from eyefix2 import _paste
def eye_layers(R,ctr,r):
    """R: rest patch (BGR). returns iris layer alpha (float), opening mask O (uint8), sclera model colour image"""
    h,w=R.shape[:2];L=lab_(R);yy,xx=np.mgrid[0:h,0:w].astype(np.float32)
    d=np.hypot(xx-ctr[0],yy-ctr[1])
    near=(d<r*3.4)
    dark=((L[...,0]<54)&(d<r*1.5)).astype(np.uint8)
    k=int(r*0.9)|1
    core=cv2.morphologyEx(dark,cv2.MORPH_OPEN,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(k,k)))
    n,lb,st,cen=cv2.connectedComponentsWithStats(core)
    best=0;bd=1e9
    for i in range(1,n):
        dd=np.hypot(cen[i][0]-ctr[0],cen[i][1]-ctr[1])
        if dd<bd and st[i,4]>25: bd=dd;best=i
    ic=(lb==best).astype(np.uint8) if best else (d<r*0.8).astype(np.uint8)
    ic=ic*(d<r*1.12).astype(np.uint8)
    cat=((L[...,0]>68)&(d<r*0.62)).astype(np.uint8)
    ic=cv2.dilate(np.maximum(ic,cat),np.ones((3,3),np.uint8))*(d<r*1.15).astype(np.uint8)
    sclera=((L[...,0]>34)&(L[...,1]<9)&(L[...,2]<12)&near).astype(np.uint8)
    O=cv2.morphologyEx(np.maximum(sclera,ic),cv2.MORPH_CLOSE,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(7,7)))
    cnt,_=cv2.findContours(O,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE)
    O2=np.zeros_like(O)
    # keep the contour that contains the iris centre
    for c_ in cnt:
        if cv2.pointPolygonTest(c_,(float(ctr[0]),float(ctr[1])),False)>=0: cv2.drawContours(O2,[c_],-1,1,-1)
    if O2.sum()==0: O2=O
    return ic.astype(np.float32),O2,sclera
def sclera_fill(R,sclera,O,sig=6):
    num=cv2.GaussianBlur((R.astype(np.float32))*sclera[...,None],(0,0),sig);den=cv2.GaussianBlur(sclera.astype(np.float32),(0,0),sig)[...,None]
    return num/np.maximum(den,1e-3)
def synth(c,fdir,shift=(6,-4),verbose=False):
    m,hero=setup(c,fdir);rect=m['frames']['gaze']['rect'];I=IRIS[c];r=I['r']
    x,y,w,h=rect;R=hero[y:y+h,x:x+w].copy();out=R.astype(np.float32).copy();L=lab_(R)
    dbg={}
    for k,p in enumerate(I['rest']):
        ctr=refine(hero,*p,r,rect);ic,O,scl=eye_layers(R,ctr,r)
        # layer alpha: iris pixels (soft)
        a=cv2.GaussianBlur(ic,(0,0),0.9)
        M=np.float32([[1,0,shift[0]],[0,1,shift[1]]])
        a2=cv2.warpAffine(a,M,(w,h),flags=cv2.INTER_LINEAR);Rs=cv2.warpAffine(R,M,(w,h),flags=cv2.INTER_CUBIC,borderMode=cv2.BORDER_REPLICATE).astype(np.float32)
        Of=cv2.GaussianBlur(O.astype(np.float32),(0,0),0.8)
        a2=a2*Of
        # upper-lid shadow on the moved iris
        dt=cv2.distanceTransform(O,cv2.DIST_L2,3)
        a_shadow=1-0.22*np.exp(-dt/3.0)
        Rs=Rs*a_shadow[...,None]
        # vacated iris area: inpaint the old iris from its surroundings (sclera / liner shadow), then paste the moved iris
        mk=cv2.dilate(ic.astype(np.uint8),cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(7,7)))*O
        mk=cv2.dilate(mk,np.ones((3,3),np.uint8))
        base=cv2.inpaint(np.clip(out,0,255).astype(np.uint8),mk*255,4,cv2.INPAINT_TELEA).astype(np.float32)
        bf=cv2.GaussianBlur(mk.astype(np.float32),(0,0),1.0)[...,None]
        out=out*(1-bf)+base*bf
        out=out*(1-a2[...,None])+Rs*a2[...,None]
        dbg[k]=(ctr,O)
    return np.clip(out,0,255).astype(np.uint8),R,dbg
if __name__=='__main__':
    fdir='/home/user/datewiseaiapp/assets/avatar'
    for c in ['ava','ethan','sofia','diego']:
        o,R,dbg=synth(c,fdir);P=cv2.imread(f'{fdir}/{c}/gaze.jpg')
        v=R.copy()
        for k,(ctr,O) in dbg.items():
            cnt,_=cv2.findContours(O,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE);cv2.drawContours(v,cnt,-1,(0,255,0),1)
        cv2.imwrite(f'../work/gs-{c}.png',cv2.resize(np.vstack([np.hstack([R,v]),np.hstack([o,P])]),None,fx=1.0,fy=1.0))
        cv2.imwrite(f'../work/gsz-{c}.png',cv2.resize(np.hstack([R,o,P]),None,fx=1.7,fy=1.7,interpolation=cv2.INTER_CUBIC))
